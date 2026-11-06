import Foundation
import CoreAudio
import AVFoundation
import SwiftUI

public enum AudioDeviceTransportType: String, CaseIterable {
    case builtIn = "내장 스피커"
    case usb = "USB 오디오 인터페이스"
    case bluetooth = "블루투스"
    case bluetoothLE = "블루투스 LE"
    case hdmi = "HDMI"
    case displayPort = "DisplayPort"
    case airPlay = "AirPlay"
    case virtual = "가상 오디오"
    case unknown = "기타"
}

public struct AudioOutputDevice: Identifiable, Hashable {
    public let id: String // Unique Device UID (e.g. "BuiltInSpeakerDevice", "AppleUSBAudioEngine:...")
    public let deviceID: AudioDeviceID
    public let name: String
    public let isDefault: Bool
    public let transportType: AudioDeviceTransportType
    public let channelCount: Int

    public var iconName: String {
        switch transportType {
        case .builtIn:
            return "laptopcomputer"
        case .usb:
            return "cable.connector"
        case .bluetooth, .bluetoothLE:
            return "headphones"
        case .hdmi, .displayPort:
            return "tv"
        case .airPlay:
            return "airplayaudio"
        case .virtual:
            return "waveform.badge.magnifyingglass"
        case .unknown:
            return "speaker.wave.2.fill"
        }
    }
}

@MainActor
public final class AudioOutputManager: NSObject, ObservableObject {
    public static let shared = AudioOutputManager()

    /// Special sentinel ID representing macOS system default output device
    public static let systemDefaultID = "SYSTEM_DEFAULT"

    // Persisted selected audio output UID (Empty or SYSTEM_DEFAULT means follow macOS default output)
    @AppStorage("selectedAudioOutputDeviceUID") public var selectedDeviceUID: String = AudioOutputManager.systemDefaultID

    // Persisted audio volume (0.0 ... 1.0)
    @AppStorage("presentationMediaVolume") public var mediaVolume: Double = 1.0 {
        didSet {
            applyVolumeToActivePlayer()
        }
    }

    @Published public private(set) var availableDevices: [AudioOutputDevice] = []
    @Published public private(set) var systemDefaultDevice: AudioOutputDevice? = nil
    @Published public var isPlayingTestSound: Bool = false

    private var testPlayer: AVPlayer?
    private var isListenerRegistered = false

    // CoreAudio property addresses
    private var devicesPropertyAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    private var defaultOutputPropertyAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    private override init() {
        super.init()
        refreshDevices()
        registerCoreAudioListeners()
    }

    /// The effective device UID to pass to AVPlayer.audioOutputDeviceUniqueID
    /// Returns nil if SYSTEM_DEFAULT is chosen or device is not found, letting AVPlayer use macOS default.
    public var effectiveDeviceUID: String? {
        if selectedDeviceUID == Self.systemDefaultID || selectedDeviceUID.isEmpty {
            return nil
        }
        // Verify the device actually exists in currently connected devices
        if availableDevices.contains(where: { $0.id == selectedDeviceUID }) {
            return selectedDeviceUID
        }
        // If the selected device was unplugged, fallback to system default (nil)
        return nil
    }

    /// Returns the currently active selected device object
    public var currentSelectedDevice: AudioOutputDevice? {
        if let effective = effectiveDeviceUID {
            return availableDevices.first(where: { $0.id == effective })
        }
        return systemDefaultDevice
    }

    /// Display title for the active audio device
    public var currentSelectedDeviceName: String {
        if selectedDeviceUID == Self.systemDefaultID || selectedDeviceUID.isEmpty {
            if let def = systemDefaultDevice {
                return "\(def.name) (시스템 기본)"
            }
            return "시스템 기본 사운드"
        }
        if let dev = availableDevices.first(where: { $0.id == selectedDeviceUID }) {
            return dev.name
        }
        return "시스템 기본 사운드 (선택 기기 연결 안됨)"
    }

    /// Select audio output device by its unique ID
    public func selectDevice(uid: String) {
        selectedDeviceUID = uid
        applyAudioOutputToActivePlayer()
    }

    /// Select macOS system default
    public func selectSystemDefault() {
        selectedDeviceUID = Self.systemDefaultID
        applyAudioOutputToActivePlayer()
    }

    /// Applies current audio device setting and volume to an AVPlayer instance
    public func configurePlayer(_ player: AVPlayer) {
        player.audioOutputDeviceUniqueID = effectiveDeviceUID
        player.volume = Float(mediaVolume)
    }

    /// Applies audio device settings to the engine's active player
    public func applyAudioOutputToActivePlayer() {
        if let player = PresentationEngine.shared.activePlayer {
            player.audioOutputDeviceUniqueID = effectiveDeviceUID
            player.volume = Float(mediaVolume)
        }
    }

    private func applyVolumeToActivePlayer() {
        if let player = PresentationEngine.shared.activePlayer {
            player.volume = Float(mediaVolume)
        }
    }

    /// Refreshes the list of available CoreAudio output devices
    public func refreshDevices() {
        var propertySize: UInt32 = 0
        var address = devicesPropertyAddress

        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize
        ) == noErr else {
            return
        }

        let deviceCount = Int(propertySize) / MemoryLayout<AudioDeviceID>.stride
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize,
            &deviceIDs
        ) == noErr else {
            return
        }

        // Get system default output device ID
        var defaultDeviceAddress = defaultOutputPropertyAddress
        var defaultDeviceID: AudioDeviceID = 0
        var defaultSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        _ = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultDeviceAddress,
            0,
            nil,
            &defaultSize,
            &defaultDeviceID
        )

        var outputList: [AudioOutputDevice] = []
        var defaultDevObj: AudioOutputDevice? = nil

        for devID in deviceIDs {
            // Check if device has output streams
            let channelCount = getOutputChannelCount(for: devID)
            guard channelCount > 0 else { continue }

            guard let uid = getDeviceUID(for: devID) else { continue }
            let name = getDeviceName(for: devID) ?? "Audio Device (\(devID))"
            let transport = getDeviceTransportType(for: devID)
            let isDef = (devID == defaultDeviceID)

            let device = AudioOutputDevice(
                id: uid,
                deviceID: devID,
                name: name,
                isDefault: isDef,
                transportType: transport,
                channelCount: channelCount
            )

            outputList.append(device)
            if isDef {
                defaultDevObj = device
            }
        }

        // Sort: Built-in and USB first, then alphabetical
        self.availableDevices = outputList.sorted {
            if $0.isDefault != $1.isDefault { return $0.isDefault }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        self.systemDefaultDevice = defaultDevObj

        // Re-apply to active player in case device list changed
        applyAudioOutputToActivePlayer()
    }

    /// Plays a short test tone ping to verify sound routing on the selected device
    public func playTestSound() {
        guard !isPlayingTestSound else { return }

        // Find standard macOS sound file
        let candidatePaths = [
            "/System/Library/Sounds/Ping.aiff",
            "/System/Library/Sounds/Hero.aiff",
            "/System/Library/Sounds/Funk.aiff",
            "/System/Library/Sounds/Glass.aiff"
        ]

        guard let soundPath = candidatePaths.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            return
        }

        let soundURL = URL(fileURLWithPath: soundPath)
        let player = AVPlayer(url: soundURL)
        player.audioOutputDeviceUniqueID = effectiveDeviceUID
        player.volume = Float(mediaVolume)

        self.testPlayer = player
        self.isPlayingTestSound = true

        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isPlayingTestSound = false
                self?.testPlayer = nil
            }
        }

        player.play()

        // Fallback timer to reset state
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            Task { @MainActor [weak self] in
                if self?.isPlayingTestSound == true {
                    self?.isPlayingTestSound = false
                    self?.testPlayer = nil
                }
            }
        }
    }

    // MARK: - CoreAudio Internal Helpers

    private func getOutputChannelCount(for deviceID: AudioDeviceID) -> Int {
        var streamConfigAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &streamConfigAddress, 0, nil, &size) == noErr, size > 0 else {
            return 0
        }

        let rawBufferList = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { rawBufferList.deallocate() }

        guard AudioObjectGetPropertyData(deviceID, &streamConfigAddress, 0, nil, &size, rawBufferList) == noErr else {
            return 0
        }

        let bufferListPtr = rawBufferList.bindMemory(to: AudioBufferList.self, capacity: 1)
        let bufferList = UnsafeMutableAudioBufferListPointer(bufferListPtr)

        var totalChannels = 0
        for buffer in bufferList {
            totalChannels += Int(buffer.mNumberChannels)
        }
        return totalChannels
    }

    private func getDeviceUID(for deviceID: AudioDeviceID) -> String? {
        var uidAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var unmanagedString: Unmanaged<CFString>? = nil
        var propertySize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(deviceID, &uidAddress, 0, nil, &propertySize, &unmanagedString) == noErr,
              let unmanaged = unmanagedString else {
            return nil
        }
        return unmanaged.takeRetainedValue() as String
    }

    private func getDeviceName(for deviceID: AudioDeviceID) -> String? {
        var nameAddress = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var unmanagedString: Unmanaged<CFString>? = nil
        var propertySize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(deviceID, &nameAddress, 0, nil, &propertySize, &unmanagedString) == noErr,
              let unmanaged = unmanagedString else {
            return nil
        }
        return unmanaged.takeRetainedValue() as String
    }

    private func getDeviceTransportType(for deviceID: AudioDeviceID) -> AudioDeviceTransportType {
        var transportAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transport: UInt32 = 0
        var propertySize = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(deviceID, &transportAddress, 0, nil, &propertySize, &transport) == noErr else {
            return .unknown
        }

        switch transport {
        case kAudioDeviceTransportTypeBuiltIn:
            return .builtIn
        case kAudioDeviceTransportTypeUSB:
            return .usb
        case kAudioDeviceTransportTypeBluetooth:
            return .bluetooth
        case kAudioDeviceTransportTypeBluetoothLE:
            return .bluetoothLE
        case kAudioDeviceTransportTypeHDMI:
            return .hdmi
        case kAudioDeviceTransportTypeDisplayPort:
            return .displayPort
        case kAudioDeviceTransportTypeAirPlay:
            return .airPlay
        case kAudioDeviceTransportTypeVirtual:
            return .virtual
        default:
            return .unknown
        }
    }

    // MARK: - CoreAudio Event Listeners

    private func registerCoreAudioListeners() {
        guard !isListenerRegistered else { return }

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &devicesPropertyAddress,
            DispatchQueue.main
        ) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.refreshDevices()
            }
        }

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultOutputPropertyAddress,
            DispatchQueue.main
        ) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.refreshDevices()
            }
        }

        isListenerRegistered = true
    }
}
