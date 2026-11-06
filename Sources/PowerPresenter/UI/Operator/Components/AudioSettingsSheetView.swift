import SwiftUI

public struct AudioSettingsSheetView: View {
    @ObservedObject var audioManager = AudioOutputManager.shared
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "speaker.wave.3.fill")
                            .font(.title2)
                            .foregroundColor(.accentColor)
                        Text("Audio Output Configuration")
                            .font(.title2.bold())
                    }
                    Text("Select the hardware destination for presentation video and audio playback.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }

            Divider()

            // Active Routing Status Banner
            HStack(spacing: 12) {
                Image(systemName: audioManager.currentSelectedDevice?.iconName ?? "speaker.wave.2.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.accentColor)
                    .frame(width: 32, height: 32)
                    .background(Color.accentColor.opacity(0.12))
                    .cornerRadius(8)

                VStack(alignment: .leading, spacing: 2) {
                    Text("ACTIVE AUDIO ROUTE")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                    Text(audioManager.currentSelectedDeviceName)
                        .font(.system(size: 14, weight: .semibold))
                }

                Spacer()

                // Test sound button
                Button(action: {
                    audioManager.playTestSound()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: audioManager.isPlayingTestSound ? "waveform" : "speaker.wave.2")
                            .symbolEffect(.pulse, isActive: audioManager.isPlayingTestSound)
                        Text(audioManager.isPlayingTestSound ? "Playing Test..." : "Test Output")
                    }
                    .font(.caption.bold())
                }
                .buttonStyle(.bordered)
                .tint(audioManager.isPlayingTestSound ? .orange : .accentColor)
                .disabled(audioManager.isPlayingTestSound)
                .help("Play a short test chime directly to the selected audio hardware.")
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )

            // Audio Device List
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("AVAILABLE AUDIO OUTPUT DEVICES (\(audioManager.availableDevices.count))")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)

                    Spacer()

                    Button(action: {
                        audioManager.refreshDevices()
                    }) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                }

                ScrollView {
                    VStack(spacing: 8) {
                        // 1. macOS System Default Card
                        AudioDeviceRowCard(
                            title: "macOS System Default",
                            subtitle: audioManager.systemDefaultDevice.map { "\($0.name) (\($0.transportType.rawValue))" } ?? "Default Output",
                            iconName: "gearshape.2",
                            badgeText: "Dynamic",
                            channelText: audioManager.systemDefaultDevice.map { "\($0.channelCount) Channels" } ?? "",
                            isSelected: audioManager.selectedDeviceUID == AudioOutputManager.systemDefaultID
                        ) {
                            audioManager.selectSystemDefault()
                        }

                        // 2. Hardware Devices List
                        ForEach(audioManager.availableDevices) { device in
                            AudioDeviceRowCard(
                                title: device.name,
                                subtitle: device.transportType.rawValue,
                                iconName: device.iconName,
                                badgeText: device.isDefault ? "Default" : nil,
                                channelText: "\(device.channelCount) Channels",
                                isSelected: audioManager.selectedDeviceUID == device.id
                            ) {
                                audioManager.selectDevice(uid: device.id)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 260)
            }

            Divider()

            // Volume Controls & Helpers
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Image(systemName: audioManager.mediaVolume == 0 ? "speaker.slash.fill" : (audioManager.mediaVolume < 0.5 ? "speaker.wave.1.fill" : "speaker.wave.3.fill"))
                        .foregroundColor(.secondary)
                        .frame(width: 18)

                    Text("Media Volume:")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)

                    Slider(value: $audioManager.mediaVolume, in: 0.0...1.0)
                        .frame(maxWidth: 220)

                    Text("\(Int(audioManager.mediaVolume * 100))%")
                        .font(.caption.monospacedDigit())
                        .frame(width: 40, alignment: .trailing)

                    Spacer()

                    Button("Reset to 100%") {
                        audioManager.mediaVolume = 1.0
                    }
                    .font(.caption2)
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                }

                Text("※ Selected sound destination applies to all video clips, background audio tracks, and test signals in presentations.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .padding(24)
        .frame(width: 580)
    }
}

private struct AudioDeviceRowCard: View {
    let title: String
    let subtitle: String
    let iconName: String
    let badgeText: String?
    let channelText: String
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 14) {
                // Device Icon
                Image(systemName: iconName)
                    .font(.system(size: 18))
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .frame(width: 32, height: 32)
                    .background(isSelected ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.05))
                    .cornerRadius(8)

                // Name & Type
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                            .foregroundColor(.primary)

                        if let badge = badgeText {
                            Text(badge)
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(Color.secondary.opacity(0.18))
                                .cornerRadius(4)
                                .foregroundColor(.secondary)
                        }
                    }

                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Channel Info
                if !channelText.isEmpty {
                    Text(channelText)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                // Checkmark / Selection Indicator
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundColor(isSelected ? .accentColor : .secondary.opacity(0.4))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(isSelected ? Color.accentColor.opacity(0.08) : Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor.opacity(0.5) : Color.primary.opacity(0.05), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}
