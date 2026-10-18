import SwiftUI

public struct StageControlsView: View {
    @ObservedObject var engine: PresentationEngine
    @ObservedObject var screens: ScreenCoordinator
    @State private var alertInputText: String = ""

    public init(engine: PresentationEngine, screens: ScreenCoordinator) {
        self.engine = engine
        self.screens = screens
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("STAGE CONTROLS", systemImage: "person.wave.2.fill")
                    .font(.caption.bold())
                    .foregroundColor(.cyan)

                Spacer()

                HStack(spacing: 5) {
                    Circle()
                        .fill(screens.isStageWindowVisible ? Color.cyan : Color.secondary.opacity(0.4))
                        .frame(width: 7, height: 7)
                    Text(screens.isStageWindowVisible ? "OUTPUT ACTIVE" : "OUTPUT OFF")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(screens.isStageWindowVisible ? .cyan : .secondary)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(screens.isStageWindowVisible ? Color.cyan.opacity(0.12) : Color.clear)
                .cornerRadius(4)
            }

            // Active Stage Layout Preset Switcher
            HStack(spacing: 8) {
                Image(systemName: "bolt.fill")
                    .font(.caption)
                    .foregroundColor(.cyan)

                Text("Preset:")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)

                Picker("", selection: Binding(
                    get: { engine.activeStagePresetID },
                    set: { engine.applyStagePreset(id: $0) }
                )) {
                    ForEach(engine.stagePresets) { preset in
                        Text(preset.name).tag(preset.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            // Stage Timer Bar
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "timer")
                        .foregroundColor(engine.isTimerRunning ? .green : .orange)
                    Text(engine.formattedTimer)
                        .font(.system(size: 18, weight: .black, design: .monospaced))
                        .foregroundColor(engine.isTimerRunning ? .green : .primary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color(NSColor.textBackgroundColor).opacity(0.5))
                .cornerRadius(6)

                Button(action: {
                    if engine.isTimerRunning {
                        engine.pauseTimer()
                    } else {
                        engine.startTimer()
                    }
                }) {
                    Text(engine.isTimerRunning ? "Pause" : "Start")
                        .font(.caption.bold())
                }
                .buttonStyle(.bordered)

                Button("Reset") {
                    engine.resetTimer()
                }
                .buttonStyle(.bordered)
                .font(.caption)

                Spacer()
            }

            // Stage Alert Message Bar
            HStack(spacing: 8) {
                TextField("Message to stage...", text: $alertInputText)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .onSubmit {
                        postAlert()
                    }

                Button("Send Alert") {
                    postAlert()
                }
                .buttonStyle(.borderedProminent)
                .tint(.yellow)
                .foregroundColor(.black)
                .font(.caption.bold())
                .disabled(alertInputText.trimmingCharacters(in: .whitespaces).isEmpty)

                if !engine.stageAlertMessage.isEmpty {
                    Button(action: {
                        engine.stageAlertMessage = ""
                        alertInputText = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear Stage Alert")
                }
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
        .cornerRadius(8)
    }

    private func postAlert() {
        let trimmed = alertInputText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        engine.stageAlertMessage = trimmed
    }
}
