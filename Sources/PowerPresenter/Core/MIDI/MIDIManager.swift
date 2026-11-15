import Foundation
import CoreMIDI
import Combine

public struct MIDIDestinationInfo: Identifiable, Hashable {
    public let id: Int
    public let name: String
    public let endpointRef: MIDIEndpointRef
}

@MainActor
public final class MIDIManager: ObservableObject {
    public static let shared = MIDIManager()

    @Published public var isMidiOutEnabled: Bool = true
    @Published public var isMidiInEnabled: Bool = false
    @Published public var isVirtualSourceActive: Bool = false
    @Published public var availableDestinations: [MIDIDestinationInfo] = []
    @Published public var selectedDestinationIndex: Int = -1 // -1 = All Destinations (Broadcast)
    @Published public var lastSentDescription: String = "None"
    @Published public var lastSentTimestamp: Date? = nil

    private var midiClient = MIDIClientRef()
    private var virtualSourceEndpoint = MIDIEndpointRef()
    private var outputPort = MIDIPortRef()
    private var inputPort = MIDIPortRef()

    private init() {
        setupMIDI()
    }

    private func setupMIDI() {
        // Create MIDI Client with Notification Callback for hot-plugging devices
        var client = MIDIClientRef()
        let status = MIDIClientCreateWithBlock("PowerPresenterMIDI" as CFString, &client) { [weak self] notificationPtr in
            let notif = notificationPtr.pointee
            if notif.messageID == .msgSetupChanged || notif.messageID == .msgObjectAdded || notif.messageID == .msgObjectRemoved {
                Task { @MainActor [weak self] in
                    self?.refreshDestinations()
                }
            }
        }

        guard status == noErr else {
            print("⚠️ Failed to create MIDI Client: status \(status)")
            return
        }
        self.midiClient = client

        // Create Virtual MIDI Source Endpoint ("PowerPresenter MIDI Out")
        // Any DAW (Ableton, Logic, QLab) on this Mac can directly select this port
        var vSource = MIDIEndpointRef()
        let vStatus = MIDISourceCreate(client, "PowerPresenter MIDI Out" as CFString, &vSource)
        if vStatus == noErr {
            self.virtualSourceEndpoint = vSource
            self.isVirtualSourceActive = true
            print("✅ CoreMIDI Virtual Source 'PowerPresenter MIDI Out' created.")
        } else {
            print("⚠️ Failed to create CoreMIDI Virtual Source: status \(vStatus)")
        }

        // Create Output Port for sending to external hardware (USB MIDI, IAC Driver, Network MIDI)
        var outPort = MIDIPortRef()
        let outStatus = MIDIOutputPortCreate(client, "PowerPresenter Output Port" as CFString, &outPort)
        if outStatus == noErr {
            self.outputPort = outPort
        }

        // Create Input Port for optional slide control from external MIDI
        var inPort = MIDIPortRef()
        let inStatus = MIDIInputPortCreateWithBlock(client, "PowerPresenter Input Port" as CFString, &inPort) { [weak self] packetListPtr, srcConnRefCon in
            self?.handleIncomingMIDIPacketList(packetListPtr)
        }
        if inStatus == noErr {
            self.inputPort = inPort
            connectAllSourcesToInputPort()
        }

        refreshDestinations()
    }

    public func refreshDestinations() {
        var list: [MIDIDestinationInfo] = []
        let count = MIDIGetNumberOfDestinations()

        for i in 0..<count {
            let dest = MIDIGetDestination(i)
            if dest != 0 {
                var name: Unmanaged<CFString>?
                MIDIObjectGetStringProperty(dest, kMIDIPropertyDisplayName, &name)
                let destName = name?.takeRetainedValue() as String? ?? "MIDI Destination \(i + 1)"
                list.append(MIDIDestinationInfo(id: i, name: destName, endpointRef: dest))
            }
        }

        self.availableDestinations = list
    }

    private func connectAllSourcesToInputPort() {
        guard inputPort != 0 else { return }
        let srcCount = MIDIGetNumberOfSources()
        for i in 0..<srcCount {
            let src = MIDIGetSource(i)
            if src != 0 && src != virtualSourceEndpoint {
                MIDIPortConnectSource(inputPort, src, nil)
            }
        }
    }

    // MARK: - Sending MIDI

    public func send(cue: MIDICue) {
        guard isMidiOutEnabled else { return }

        switch cue.type {
        case .controlChange:
            sendControlChange(channel: cue.channel, controller: cue.number, value: cue.value)
        case .noteOn:
            sendNoteOn(channel: cue.channel, note: cue.number, velocity: cue.value)
        case .programChange:
            sendProgramChange(channel: cue.channel, program: cue.number)
        }

        self.lastSentDescription = cue.displayName
        self.lastSentTimestamp = Date()
    }

    public func testSend(cue: MIDICue) {
        send(cue: cue)
    }

    public func sendControlChange(channel: UInt8, controller: UInt8, value: UInt8) {
        let ch = max(0, min(15, channel - 1))
        let status = UInt8(0xB0 | ch)
        let bytes: [UInt8] = [status, controller & 0x7F, value & 0x7F]
        sendRawBytes(bytes)
    }

    public func sendNoteOn(channel: UInt8, note: UInt8, velocity: UInt8, autoNoteOffDelay: TimeInterval = 0.1) {
        let ch = max(0, min(15, channel - 1))
        let statusOn = UInt8(0x90 | ch)
        let bytesOn: [UInt8] = [statusOn, note & 0x7F, velocity & 0x7F]
        sendRawBytes(bytesOn)

        // Automatically dispatch Note Off after 100ms for clean action trigger in DAWs / lighting desks
        if autoNoteOffDelay > 0 {
            DispatchQueue.global().asyncAfter(deadline: .now() + autoNoteOffDelay) { [weak self] in
                let statusOff = UInt8(0x80 | ch)
                let bytesOff: [UInt8] = [statusOff, note & 0x7F, 0]
                Task { @MainActor [weak self] in
                    self?.sendRawBytes(bytesOff)
                }
            }
        }
    }

    public func sendProgramChange(channel: UInt8, program: UInt8) {
        let ch = max(0, min(15, channel - 1))
        let status = UInt8(0xC0 | ch)
        let bytes: [UInt8] = [status, program & 0x7F]
        sendRawBytes(bytes)
    }

    private func sendRawBytes(_ bytes: [UInt8]) {
        guard !bytes.isEmpty else { return }
        let bufferSize = 1024
        let rawPtr = UnsafeMutableRawPointer.allocate(
            byteCount: bufferSize,
            alignment: MemoryLayout<MIDIPacketList>.alignment
        )
        defer { rawPtr.deallocate() }
        rawPtr.initializeMemory(as: UInt8.self, repeating: 0, count: bufferSize)

        let packetList = rawPtr.assumingMemoryBound(to: MIDIPacketList.self)
        var cur = MIDIPacketListInit(packetList)
        cur = MIDIPacketListAdd(packetList, bufferSize, cur, 0, bytes.count, bytes)

        // 1. Always send to Virtual Source (local DAWs listening to PowerPresenter MIDI Out)
        if virtualSourceEndpoint != 0 {
            MIDIReceived(virtualSourceEndpoint, packetList)
        }

        // 2. Send to target external destinations
        if outputPort != 0 {
            if selectedDestinationIndex >= 0 && selectedDestinationIndex < availableDestinations.count {
                let dest = availableDestinations[selectedDestinationIndex].endpointRef
                if dest != 0 {
                    MIDISend(outputPort, dest, packetList)
                }
            } else {
                // Broadcast to all detected hardware / network / IAC destinations
                for destInfo in availableDestinations {
                    if destInfo.endpointRef != 0 {
                        MIDISend(outputPort, destInfo.endpointRef, packetList)
                    }
                }
            }
        }
    }

    // MARK: - MIDI In Handling (Slide Remote Control)

    nonisolated private func handleIncomingMIDIPacketList(_ packetListPtr: UnsafePointer<MIDIPacketList>) {
        let packetList = packetListPtr.pointee
        var packet = packetList.packet

        for _ in 0..<packetList.numPackets {
            let length = packet.length
            if length >= 2 {
                let data = Mirror(reflecting: packet.data).children.map { $0.value as! UInt8 }
                let status = data[0] & 0xF0
                let byte1 = data[1]
                let byte2 = (length >= 3) ? data[2] : 0

                Task { @MainActor in
                    self.processIncomingMIDI(status: status, byte1: byte1, byte2: byte2)
                }
            }
            packet = MIDIPacketNext(&packet).pointee
        }
    }

    private func processIncomingMIDI(status: UInt8, byte1: UInt8, byte2: UInt8) {
        guard isMidiInEnabled else { return }

        // Standard default mappings:
        // Note 60 (C4) or CC 20 = Next Slide
        // Note 59 (B3) or CC 19 = Previous Slide
        // Note 58 (A#3) or CC 18 = Blackout Toggle
        if status == 0x90 && byte2 > 0 { // Note On
            if byte1 == 60 {
                PresentationEngine.shared.next()
            } else if byte1 == 59 {
                PresentationEngine.shared.previous()
            } else if byte1 == 58 {
                PresentationEngine.shared.toggleBlackout()
            }
        } else if status == 0xB0 { // Control Change
            if byte1 == 20 && byte2 > 0 {
                PresentationEngine.shared.next()
            } else if byte1 == 19 && byte2 > 0 {
                PresentationEngine.shared.previous()
            } else if byte1 == 18 && byte2 > 0 {
                PresentationEngine.shared.toggleBlackout()
            }
        }
    }
}
