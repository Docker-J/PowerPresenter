import SwiftUI
import CoreMIDI

public struct MIDISettingsSheetView: View {
    @ObservedObject var midi = MIDIManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var testChannel: Int = 1
    @State private var testCCNumber: Int = 20
    @State private var testCCValue: Int = 127
    @State private var testNoteNumber: Int = 60
    @State private var testSentBanner: String? = nil

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Image(systemName: "pianokeys")
                            .font(.title2)
                            .foregroundColor(.yellow)
                        Text("CoreMIDI Configuration")
                            .font(.title2.bold())
                    }
                    Text("Broadcast MIDI Action Cues to lighting desks, DAWs (Ableton, Logic), and digital audio mixers.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(18)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // 1. General MIDI Output Toggle & Virtual Port Status
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label("MIDI OUTPUT STATUS", systemImage: "bolt.fill")
                                .font(.caption.bold())
                                .foregroundColor(.secondary)

                            Spacer()

                            Toggle("Enable MIDI Out", isOn: $midi.isMidiOutEnabled)
                                .toggleStyle(.switch)
                        }

                        HStack(spacing: 12) {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(midi.isVirtualSourceActive ? Color.green : Color.red)
                                    .frame(width: 8, height: 8)
                                Text("Virtual Port: PowerPresenter MIDI Out")
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.12))
                            .cornerRadius(6)

                            Text("• Any DAW (Ableton, QLab) on this Mac can receive this directly")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(14)
                    .background(Color(NSColor.windowBackgroundColor))
                    .cornerRadius(10)

                    // 2. Output Destinations Routing
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label("HARDWARE & NETWORK DESTINATIONS", systemImage: "cable.connector")
                                .font(.caption.bold())
                                .foregroundColor(.secondary)

                            Spacer()

                            Button(action: {
                                midi.refreshDestinations()
                            }) {
                                Label("Refresh Ports", systemImage: "arrow.clockwise")
                                    .font(.caption2)
                            }
                            .buttonStyle(.borderless)
                        }

                        Picker("Target Route:", selection: $midi.selectedDestinationIndex) {
                            Text("All Destinations (Broadcast Everywhere)").tag(-1)
                            Divider()
                            ForEach(midi.availableDestinations) { dest in
                                Text("\(dest.name) (Port #\(dest.id))").tag(dest.id)
                            }
                        }
                        .pickerStyle(.menu)

                        if midi.availableDestinations.isEmpty {
                            Text("No physical external MIDI hardware currently connected. (PowerPresenter virtual port is active and broadcasting to local DAWs).")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        } else {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Detected Endpoints:")
                                    .font(.caption2.bold())
                                    .foregroundColor(.secondary)
                                ForEach(midi.availableDestinations) { dest in
                                    HStack(spacing: 6) {
                                        Image(systemName: "circle.fill")
                                            .font(.system(size: 5))
                                            .foregroundColor(.cyan)
                                        Text(dest.name)
                                            .font(.caption.monospaced())
                                    }
                                }
                            }
                            .padding(8)
                            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                            .cornerRadius(6)
                        }
                    }
                    .padding(14)
                    .background(Color(NSColor.windowBackgroundColor))
                    .cornerRadius(10)

                    // 3. Live MIDI Test Panel
                    VStack(alignment: .leading, spacing: 12) {
                        Label("MANUAL MIDI SIGNAL TEST", systemImage: "waveform.path")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)

                        HStack(spacing: 14) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Test Channel:")
                                    .font(.caption2.bold())
                                Picker("", selection: $testChannel) {
                                    ForEach(1...16, id: \.self) { ch in
                                        Text("Ch \(ch)").tag(ch)
                                    }
                                }
                                .frame(width: 90)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Test CC #:")
                                    .font(.caption2.bold())
                                TextField("", value: $testCCNumber, formatter: NumberFormatter())
                                    .frame(width: 60)
                                    .textFieldStyle(.roundedBorder)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("CC Val:")
                                    .font(.caption2.bold())
                                TextField("", value: $testCCValue, formatter: NumberFormatter())
                                    .frame(width: 60)
                                    .textFieldStyle(.roundedBorder)
                            }

                            Button {
                                midi.sendControlChange(channel: UInt8(testChannel), controller: UInt8(testCCNumber), value: UInt8(testCCValue))
                                triggerBanner("Sent CC #\(testCCNumber) Val \(testCCValue) on Ch \(testChannel)")
                            } label: {
                                Label("Send CC", systemImage: "paperplane")
                            }
                            .buttonStyle(.bordered)

                            Divider()
                                .frame(height: 24)

                            Button {
                                midi.sendNoteOn(channel: UInt8(testChannel), note: UInt8(testNoteNumber), velocity: 127)
                                triggerBanner("Sent Note \(MIDICue.noteName(for: UInt8(testNoteNumber))) (\(testNoteNumber)) on Ch \(testChannel)")
                            } label: {
                                Label("Send Note C4", systemImage: "pianokeys")
                            }
                            .buttonStyle(.bordered)
                        }

                        if let banner = testSentBanner {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text(banner)
                                    .font(.caption.bold())
                                    .foregroundColor(.green)
                            }
                            .transition(.opacity)
                        }
                    }
                    .padding(14)
                    .background(Color(NSColor.windowBackgroundColor))
                    .cornerRadius(10)

                    // 4. Remote Slide Control (MIDI In)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label("INCOMING MIDI REMOTE CONTROL (MIDI IN)", systemImage: "arrow.down.left.circle")
                                .font(.caption.bold())
                                .foregroundColor(.secondary)

                            Spacer()

                            Toggle("Enable MIDI In", isOn: $midi.isMidiInEnabled)
                                .toggleStyle(.switch)
                        }

                        Text("When enabled, external MIDI devices (foot controllers, Ableton tracks, StreamDeck) can advance or control slides:")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        HStack(spacing: 16) {
                            Text("• Note 60 (C4) or CC 20 → Next Slide")
                                .font(.caption.monospaced())
                            Text("• Note 59 (B3) or CC 19 → Prev Slide")
                                .font(.caption.monospaced())
                            Text("• Note 58 (A#3) or CC 18 → Blackout")
                                .font(.caption.monospaced())
                        }
                        .foregroundColor(.primary)
                    }
                    .padding(14)
                    .background(Color(NSColor.windowBackgroundColor))
                    .cornerRadius(10)

                    // 5. Activity Log
                    HStack {
                        Image(systemName: "clock")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Last Sent Signal: \(midi.lastSentDescription)")
                            .font(.caption.monospaced())
                            .foregroundColor(.secondary)
                        Spacer()
                        if let ts = midi.lastSentTimestamp {
                            Text(ts.formatted(date: .omitted, time: .standard))
                                .font(.caption2.monospaced())
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .padding(18)
            }
        }
        .frame(minWidth: 620, minHeight: 520)
    }

    private func triggerBanner(_ text: String) {
        withAnimation {
            testSentBanner = text
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation {
                testSentBanner = nil
            }
        }
    }
}
