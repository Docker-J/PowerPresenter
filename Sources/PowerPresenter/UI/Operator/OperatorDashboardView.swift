import SwiftUI

public enum MonitorDisplayMode: String, CaseIterable {
    case audience = "Audience (Live)"
    case stage = "Stage View"
}

private struct EditingSlideIdentifier: Identifiable {
    let id: Int
}

public struct OperatorDashboardView: View {
    @ObservedObject var engine = PresentationEngine.shared
    @ObservedObject var screens = ScreenCoordinator.shared
    @ObservedObject var flow = ServiceFlowManager.shared
    @ObservedObject var updater = AppUpdateManager.shared
    @AppStorage("operatorThumbnailSize") private var thumbnailSize: Double = 210.0
    @State private var selectedMonitor: MonitorDisplayMode = .audience
    @State private var editingSlide: EditingSlideIdentifier? = nil
    @State private var selectedSlideIndices: Set<Int> = []
    @State private var lastClickedIndex: Int? = nil
    @State private var isShowingServiceFlowSheet: Bool = false

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Top Toolbar
            DeckToolbarView(engine: engine, screens: screens)

            Divider()

            // Main Workspace Split
            HSplitView {
                // Left Pane: Expanded Slides Matrix Section (Primary Wide Real Estate)
                VStack(alignment: .leading, spacing: 0) {
                    // Service Liturgy Flow Quick Bar & Multi-Select Batch Bar
                    VStack(spacing: 0) {
                        HStack(spacing: 8) {
                            HStack(spacing: 4) {
                                Image(systemName: "list.bullet.indent")
                                    .font(.caption2.bold())
                                    .foregroundColor(.accentColor)
                                Text("Liturgy Flow:")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.trailing, 2)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(flow.sections) { sec in
                                        Button {
                                            applySectionToSelection(sec)
                                        } label: {
                                            HStack(spacing: 4) {
                                                Image(systemName: sec.iconName)
                                                    .font(.system(size: 9))
                                                Text(sec.name)
                                                    .font(.system(size: 11, weight: .medium))
                                            }
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(sec.color.opacity(0.18))
                                            .foregroundColor(sec.color)
                                            .cornerRadius(5)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 5)
                                                    .stroke(sec.color.opacity(0.5), lineWidth: 1)
                                            )
                                        }
                                        .buttonStyle(.plain)
                                        .help("Assign selected slides to \(sec.name) (Cues apply to 1st slide)")
                                    }

                                    Button {
                                        isShowingServiceFlowSheet = true
                                    } label: {
                                        HStack(spacing: 3) {
                                            Image(systemName: "gearshape")
                                                .font(.system(size: 10))
                                            Text("순서 편집")
                                                .font(.system(size: 10))
                                        }
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 4)
                                        .background(Color.secondary.opacity(0.12))
                                        .foregroundColor(.secondary)
                                        .cornerRadius(5)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Edit Church Service Liturgy Sections")
                                }
                            }

                            Spacer()

                            if selectedSlideIndices.count > 1 {
                                HStack(spacing: 6) {
                                    Text("\(selectedSlideIndices.count) selected")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.accentColor)

                                    Button("Deselect") {
                                        selectedSlideIndices.removeAll()
                                    }
                                    .font(.caption2)
                                    .buttonStyle(.bordered)
                                    .controlSize(.mini)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.accentColor.opacity(0.12))
                                .cornerRadius(5)
                            } else if let curSlide = engine.currentSlide {
                                Menu {
                                    Button("None (Keep Previous Layout)") {
                                        engine.assignStagePreset(nil, toSlideAt: curSlide.index)
                                    }
                                    Divider()
                                    ForEach(engine.stagePresets) { preset in
                                        Button("⚡ \(preset.name)") {
                                            engine.assignStagePreset(preset.id, toSlideAt: curSlide.index)
                                        }
                                    }
                                } label: {
                                    Label(
                                        engine.preset(for: curSlide.stageLayoutPresetID).map { "Slide #\(curSlide.index + 1) Cue: \($0.name)" }
                                            ?? "Stage Preset: #\(curSlide.index + 1)...",
                                        systemImage: "bolt.fill"
                                    )
                                    .font(.caption2)
                                }
                                .menuStyle(.borderlessButton)
                                .fixedSize()
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                    }

                    Divider()

                    ScrollView {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: CGFloat(thumbnailSize), maximum: CGFloat(thumbnailSize * 1.35)), spacing: 16)],
                            spacing: 16
                        ) {
                            ForEach(engine.slides) { slide in
                                SlideThumbnailCard(
                                    slide: slide,
                                    isCurrent: engine.currentSlideIndex == slide.index,
                                    isSelected: selectedSlideIndices.contains(slide.index),
                                    assignedPreset: engine.preset(for: slide.stageLayoutPresetID),
                                    availablePresets: engine.stagePresets,
                                    onSelect: {
                                        handleSlideClick(slideIndex: slide.index)
                                    },
                                    onAssignPreset: { presetID in
                                        if selectedSlideIndices.contains(slide.index) {
                                            engine.assignStagePreset(presetID, toSlideIndices: selectedSlideIndices)
                                        } else {
                                            engine.assignStagePreset(presetID, toSlideAt: slide.index)
                                        }
                                    },
                                    onAssignMIDICue: { midiCue in
                                        if selectedSlideIndices.contains(slide.index) {
                                            engine.assignMIDICue(midiCue, toSlideIndices: selectedSlideIndices)
                                        } else {
                                            engine.assignMIDICue(midiCue, toSlideAt: slide.index)
                                        }
                                    },
                                    onAssignServiceSection: { sec in
                                        if selectedSlideIndices.contains(slide.index) {
                                            engine.assignServiceSection(sec, toSlideIndices: selectedSlideIndices)
                                        } else {
                                            engine.assignServiceSection(sec, toSlideIndices: [slide.index])
                                        }
                                    },
                                    onEditSlide: {
                                        editingSlide = EditingSlideIdentifier(id: slide.index)
                                    }
                                )
                            }
                        }
                        .padding(20)
                    }

                    Divider()

                    // Bottom Status & Slide Zoom Bar
                    HStack(spacing: 14) {
                        HStack(spacing: 6) {
                            Image(systemName: "square.grid.2x2")
                                .foregroundColor(.secondary)
                                .font(.caption2)
                            Text("\(engine.slides.count) Slides")
                                .font(.caption2.bold())
                                .foregroundColor(.secondary)

                            if !engine.slides.isEmpty {
                                Text("• Slide \(engine.currentSlideIndex + 1) Selected")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Spacer()

                        // Thumbnail size zoom controls
                        HStack(spacing: 8) {
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    thumbnailSize = max(110, thumbnailSize - 25)
                                }
                            } label: {
                                Image(systemName: "minus.magnifyingglass")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Decrease Thumbnail Size (⌘-)")

                            Slider(value: $thumbnailSize, in: 110...400, step: 5)
                                .frame(width: 120)
                                .controlSize(.mini)

                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    thumbnailSize = min(400, thumbnailSize + 25)
                                }
                            } label: {
                                Image(systemName: "plus.magnifyingglass")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Increase Thumbnail Size (⌘+)")

                            Menu {
                                Button("Small (130px)") { thumbnailSize = 130 }
                                Button("Medium (210px) - Default") { thumbnailSize = 210 }
                                Button("Large (290px)") { thumbnailSize = 290 }
                                Button("Extra Large (380px)") { thumbnailSize = 380 }
                                Divider()
                                Button("Reset to Default (210px)") { thumbnailSize = 210 }
                            } label: {
                                Text("\(Int(thumbnailSize))px")
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                            .help("Preset Sizes / Reset")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.35))
                }
                .frame(minWidth: 560, maxWidth: .infinity)

                // Right Pane: Single Switchable Monitor & Controls Sidebar
                VStack(spacing: 12) {
                    // Monitor Mode Switcher
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("SCREEN MONITOR")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(.secondary)

                            Spacer()

                            Picker("", selection: $selectedMonitor) {
                                ForEach(MonitorDisplayMode.allCases, id: \.self) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(width: 210)
                        }

                        // Single Screen View with Live / Stage switching
                        if selectedMonitor == .audience {
                            StageMonitorView(
                                title: "LIVE (AUDIENCE)",
                                subtitle: engine.currentSlide?.title,
                                slide: engine.currentSlide,
                                borderColor: .red,
                                badgeText: "ON AIR",
                                badgeColor: .red,
                                isBlackedOut: engine.isBlackoutActive
                            )
                        } else {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("STAGE VIEW")
                                        .font(.caption.bold())
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text("⚡ \(engine.activeStagePreset?.name.uppercased() ?? "STAGE")")
                                        .font(.system(size: 10, weight: .heavy, design: .monospaced))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.cyan.opacity(0.2))
                                        .foregroundColor(.cyan)
                                        .cornerRadius(4)
                                }

                                StagePreviewCard(engine: engine)
                                    .aspectRatio(16/9, contentMode: .fit)
                                    .cornerRadius(6)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(Color.cyan.opacity(0.8), lineWidth: 2)
                                    )

                                Text("Preset: \(engine.activeStagePreset?.name ?? "Standard") • Slide \(engine.currentSlideIndex + 1)/\(max(1, engine.slides.count))")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                    // Presenter Notes & Slide Cues Box
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "note.text")
                                .foregroundColor(.secondary)
                            Text("SLIDE #\(engine.currentSlideIndex + 1) NOTES & CUES")
                                .font(.caption.bold())
                                .foregroundColor(.secondary)
                            Spacer()
                            Button(action: {
                                editingSlide = EditingSlideIdentifier(id: engine.currentSlideIndex)
                            }) {
                                Label("Edit Slide...", systemImage: "pencil")
                                    .font(.caption2)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        ScrollView {
                            VStack(alignment: .leading, spacing: 5) {
                                // Show assigned Stage Cue if any
                                if let presetID = engine.currentSlide?.stageLayoutPresetID, let preset = engine.preset(for: presetID) {
                                    HStack(spacing: 5) {
                                        Image(systemName: "bolt.fill")
                                            .font(.system(size: 9))
                                        Text("Stage Preset Cue: \(preset.name)")
                                            .font(.system(size: 11, weight: .bold))
                                    }
                                    .foregroundColor(.cyan)
                                }

                                // Show assigned MIDI Cue if any
                                if let midiCue = engine.currentSlide?.midiCue {
                                    HStack(spacing: 5) {
                                        Image(systemName: "pianokeys")
                                            .font(.system(size: 9))
                                        Text("MIDI Cue: \(midiCue.displayName)")
                                            .font(.system(size: 11, weight: .bold))
                                    }
                                    .foregroundColor(.yellow)
                                }

                                // Presenter Notes text
                                let notesText = engine.currentSlide?.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                                Text(notesText.isEmpty ? "No presenter notes for this slide." : notesText)
                                    .font(.system(size: 12, design: .default))
                                    .foregroundColor(notesText.isEmpty ? .secondary : .primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(8)
                        }
                        .background(Color(NSColor.textBackgroundColor).opacity(0.4))
                        .cornerRadius(6)
                    }
                    .frame(maxHeight: 110)
                    .padding(.horizontal, 16)

                    // Stage Controls (Preset switcher, Timer & Alert messaging to stage)
                    StageControlsView(engine: engine, screens: screens)
                        .padding(.horizontal, 16)

                    Spacer()

                    // Emergency & Transport Bar
                    EmergencyControlsBar(engine: engine, screens: screens)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 14)
                }
                .frame(width: 380)
                .background(Color(NSColor.windowBackgroundColor))
            }
        }
        .frame(minWidth: 1000, minHeight: 680)
        .sheet(item: $editingSlide) { item in
            SlideEditorSheetView(engine: engine, slideIndex: item.id)
        }
        .sheet(isPresented: $isShowingServiceFlowSheet) {
            ServiceFlowConfigSheetView()
        }
        .sheet(isPresented: $updater.showUpdateDialog) {
            UpdateDialogView()
        }
        .onChange(of: engine.slides.count) { _, newCount in
            selectedSlideIndices = selectedSlideIndices.filter { $0 >= 0 && $0 < newCount }
            if let last = lastClickedIndex, last >= newCount {
                lastClickedIndex = nil
            }
        }
    }

    private func handleSlideClick(slideIndex: Int) {
        guard engine.slides.indices.contains(slideIndex) else { return }
        let flags = NSEvent.modifierFlags
        if flags.contains(.shift) {
            let candidateStart = lastClickedIndex ?? engine.currentSlideIndex
            let start = engine.slides.indices.contains(candidateStart) ? candidateStart : slideIndex
            let range = min(start, slideIndex)...max(start, slideIndex)
            selectedSlideIndices.formUnion(range)
            lastClickedIndex = slideIndex
        } else if flags.contains(.command) {
            if selectedSlideIndices.contains(slideIndex) {
                selectedSlideIndices.remove(slideIndex)
            } else {
                selectedSlideIndices.insert(slideIndex)
            }
            lastClickedIndex = slideIndex
        } else {
            selectedSlideIndices = [slideIndex]
            lastClickedIndex = slideIndex
            engine.navigateTo(index: slideIndex)
        }
    }

    private func applySectionToSelection(_ sec: ServiceSection?) {
        let targets = selectedSlideIndices.isEmpty ? Set([engine.currentSlideIndex]) : selectedSlideIndices
        engine.assignServiceSection(sec, toSlideIndices: targets)
    }
}

// Compact stage preview card for the operator monitor slot - renders live stage preset layout
struct StagePreviewCard: View {
    @ObservedObject var engine: PresentationEngine

    var body: some View {
        StageDisplayView(engine: engine)
            .aspectRatio(16/9, contentMode: .fit)
            .clipped()
    }
}
