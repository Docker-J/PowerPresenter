import SwiftUI
import AppKit
import UniformTypeIdentifiers

public struct DeckToolbarView: View {
    @ObservedObject var engine: PresentationEngine
    @ObservedObject var screens: ScreenCoordinator
    @ObservedObject var updater = AppUpdateManager.shared
    @ObservedObject var audioManager = AudioOutputManager.shared

    @State private var isShowingDisplayConfig = false
    @State private var isShowingStageEditor = false
    @State private var isShowingMIDISettings = false
    @State private var isShowingServiceFlow = false
    @State private var isShowingAudioSettings = false

    public init(engine: PresentationEngine, screens: ScreenCoordinator) {
        self.engine = engine
        self.screens = screens
    }

    public var body: some View {
        HStack(spacing: 12) {
            // Deck Title & Status
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(engine.deckTitle)
                        .font(.headline)
                        .lineLimit(1)

                    Text("\(engine.slides.count) Slides")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.2))
                        .cornerRadius(4)

                    if engine.isLoadingDeck {
                        ProgressView()
                            .controlSize(.small)
                        Text("Importing...")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }

                HStack(spacing: 6) {
                    Circle()
                        .fill(screens.connectedScreens.count > 1 ? Color.green : Color.blue)
                        .frame(width: 8, height: 8)

                    Text("\(screens.connectedScreens.count) Display(s) • Audio: \(audioManager.currentSelectedDeviceName) • Active Stage Preset: \(engine.activeStagePreset?.name ?? "Standard")")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if updater.isUpdateAvailable, let release = updater.latestRelease {
                Button {
                    updater.showUpdateDialog = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                            .foregroundColor(.orange)
                        Text("v\(release.versionDisplay) 업데이트")
                            .font(.caption.bold())
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.12))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .help("새로운 버전이 사용 가능합니다. 클릭하여 업데이트하세요.")
            }

            // Transition Selector
            Picker("Transition", selection: $engine.defaultTransition) {
                Text("Cut (Direct)").tag(TransitionType.cut)
                Text("Crossfade (0.35s)").tag(TransitionType.crossfade(duration: 0.35))
                Text("Crossfade (0.75s)").tag(TransitionType.crossfade(duration: 0.75))
                Text("Push Left (0.4s)").tag(TransitionType.push(direction: .left, duration: 0.4))
                Text("Push Right (0.4s)").tag(TransitionType.push(direction: .right, duration: 0.4))
                Text("Zoom In (0.4s)").tag(TransitionType.zoom(scale: 1.15, duration: 0.4))
            }
            .pickerStyle(.menu)
            .frame(width: 170)

            Divider()
                .frame(height: 24)

            // Service Flow (Liturgy Order) Button
            Button(action: { isShowingServiceFlow = true }) {
                Label("Service Flow...", systemImage: "list.bullet.indent")
            }
            .buttonStyle(.bordered)
            .help("Configure Church Service Liturgy sections (카운트다운영상, 호스팅, 찬양, 말씀, 결단찬양, 광고)")

            // Configure Displays Button
            Button(action: { isShowingDisplayConfig = true }) {
                Label("Displays...", systemImage: "display.2")
            }
            .buttonStyle(.bordered)
            .help("Assign specific physical monitors to Audience Output or Stage Display")

            // Edit Stage Layout & Presets Button
            Button(action: { isShowingStageEditor = true }) {
                Label("Stage Presets...", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.bordered)
            .help("Create & customize Stage Screen presets and extract named elements from slides")

            // MIDI Routing & Action Cues Button
            Button(action: { isShowingMIDISettings = true }) {
                Label("MIDI...", systemImage: "pianokeys")
            }
            .buttonStyle(.bordered)
            .help("Configure CoreMIDI output destinations, virtual ports, and test MIDI cues")

            // Audio Output Routing Button
            Button(action: { isShowingAudioSettings = true }) {
                Label("Audio...", systemImage: "speaker.wave.2")
            }
            .buttonStyle(.bordered)
            .help("Configure sound output source (USB Audio Interface, HDMI, Bluetooth, Built-in Speakers) & master volume")

            Divider()
                .frame(height: 24)

            // Audience Output Toggle
            Button(action: { screens.toggleAudienceWindow() }) {
                Label(screens.isAudienceWindowVisible ? "Audience: ON" : "Audience: OFF",
                      systemImage: screens.isAudienceWindowVisible ? "tv.fill" : "tv")
                    .font(.caption.bold())
            }
            .buttonStyle(.borderedProminent)
            .tint(screens.isAudienceWindowVisible ? .red : .secondary)
            .help("Toggle Audience Display Output [⌘D]")

            // Stage View Output Toggle
            Button(action: { screens.toggleStageWindow() }) {
                Label(screens.isStageWindowVisible ? "Stage: ON" : "Stage: OFF",
                      systemImage: "person.wave.2.fill")
                    .font(.caption.bold())
            }
            .buttonStyle(.borderedProminent)
            .tint(screens.isStageWindowVisible ? .cyan : .secondary)
            .help("Toggle Stage View (Confidence Monitor) Output [⌘S]")

            // Import PPTX / PDF Button
            Button(action: { openFileDialog() }) {
                Label("Import PPTX/PDF...", systemImage: "folder.badge.plus")
            }
            .buttonStyle(.bordered)
            .disabled(engine.isLoadingDeck)

            // Reload Demo Deck
            Button(action: { loadDemoDeck() }) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .help("Reset to Built-in Demo Deck")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(NSColor.controlBackgroundColor))
        .sheet(isPresented: $isShowingServiceFlow) {
            ServiceFlowConfigSheetView()
        }
        .sheet(isPresented: $isShowingDisplayConfig) {
            DisplayConfiguratorView()
        }
        .sheet(isPresented: $isShowingStageEditor) {
            StageLayoutEditorView()
        }
        .sheet(isPresented: $isShowingMIDISettings) {
            MIDISettingsSheetView()
        }
        .sheet(isPresented: $isShowingAudioSettings) {
            AudioSettingsSheetView()
        }
    }

    private func openFileDialog() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        var allowedTypes: [UTType] = [.pdf]
        if let pptxType = UTType(filenameExtension: "pptx") { allowedTypes.append(pptxType) }
        if let pptType = UTType(filenameExtension: "ppt") { allowedTypes.append(pptType) }
        panel.allowedContentTypes = allowedTypes

        if panel.runModal() == .OK, let url = panel.url {
            engine.isLoadingDeck = true
            Task {
                do {
                    let result = try await DeckLoader.shared.loadDeck(from: url)
                    await MainActor.run {
                        engine.loadDeck(title: result.title, slides: result.slides)
                        engine.isLoadingDeck = false
                    }
                } catch {
                    await MainActor.run {
                        engine.isLoadingDeck = false
                    }
                    print("Error loading deck: \(error.localizedDescription)")
                }
            }
        }
    }

    private func loadDemoDeck() {
        let demoSlides = SampleDeckBuilder.buildDemoDeck()
        engine.loadDeck(title: "PowerPresenter Demo Deck", slides: demoSlides)
    }
}
