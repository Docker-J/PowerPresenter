import SwiftUI

public struct SlideThumbnailCard: View {
    let slide: SlideItem
    let isCurrent: Bool
    let isSelected: Bool
    let assignedPreset: StageLayoutPreset?
    let availablePresets: [StageLayoutPreset]
    let onSelect: () -> Void
    let onAssignPreset: (UUID?) -> Void
    let onAssignMIDICue: (MIDICue?) -> Void
    let onAssignServiceSection: (ServiceSection?) -> Void
    let onEditSlide: () -> Void

    public init(
        slide: SlideItem,
        isCurrent: Bool,
        isSelected: Bool = false,
        assignedPreset: StageLayoutPreset? = nil,
        availablePresets: [StageLayoutPreset] = [],
        onSelect: @escaping () -> Void,
        onAssignPreset: @escaping (UUID?) -> Void = { _ in },
        onAssignMIDICue: @escaping (MIDICue?) -> Void = { _ in },
        onAssignServiceSection: @escaping (ServiceSection?) -> Void = { _ in },
        onEditSlide: @escaping () -> Void = {}
    ) {
        self.slide = slide
        self.isCurrent = isCurrent
        self.isSelected = isSelected
        self.assignedPreset = assignedPreset
        self.availablePresets = availablePresets
        self.onSelect = onSelect
        self.onAssignPreset = onAssignPreset
        self.onAssignMIDICue = onAssignMIDICue
        self.onAssignServiceSection = onAssignServiceSection
        self.onEditSlide = onEditSlide
    }

    public var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 5) {
                ZStack {
                    Color.black

                    if let img = slide.visualRepresentation {
                        Image(decorative: img, scale: 1.0)
                            .resizable()
                            .aspectRatio(16/9, contentMode: .fit)
                    } else {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .aspectRatio(16/9, contentMode: .fit)
                    }

                    // Overlay Badges (Top & Bottom)
                    VStack {
                        // Top Row: Slide Number, Service Section Tag & LIVE badge
                        HStack(spacing: 4) {
                            Text("\(slide.index + 1)")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.black.opacity(0.78))
                                .foregroundColor(.white)
                                .cornerRadius(3)

                            // Service Section Pill (e.g. 찬양, 말씀, 광고)
                            if let secName = slide.serviceSectionName, !secName.isEmpty {
                                let secColor = Color(hex: slide.serviceSectionColorHex ?? "#3B82F6") ?? .blue
                                Text(secName)
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(secColor.opacity(0.9))
                                    .foregroundColor(.white)
                                    .cornerRadius(3)
                            }

                            Spacer()

                            if isCurrent {
                                Text("LIVE")
                                    .font(.system(size: 9, weight: .black, design: .monospaced))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.red)
                                    .foregroundColor(.white)
                                    .cornerRadius(3)
                            }

                            if slide.isVideoMedia {
                                HStack(spacing: 3) {
                                    Image(systemName: "video.fill")
                                        .font(.system(size: 8))
                                    Text("VIDEO")
                                        .font(.system(size: 8, weight: .heavy, design: .monospaced))
                                }
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.purple.opacity(0.9))
                                .foregroundColor(.white)
                                .cornerRadius(3)
                            } else if slide.isAudioMedia {
                                HStack(spacing: 3) {
                                    Image(systemName: "speaker.wave.2.fill")
                                        .font(.system(size: 8))
                                    Text("AUDIO")
                                        .font(.system(size: 8, weight: .heavy, design: .monospaced))
                                }
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.9))
                                .foregroundColor(.white)
                                .cornerRadius(3)
                            }
                        }

                        Spacer()

                        // Bottom Row: Stage Layout Preset Cue & MIDI Action Cue Badges
                        HStack(spacing: 4) {
                            if let preset = assignedPreset {
                                HStack(spacing: 3) {
                                    Image(systemName: "bolt.fill")
                                        .font(.system(size: 8))
                                    Text(preset.name)
                                        .font(.system(size: 9, weight: .bold))
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.black.opacity(0.85))
                                .foregroundColor(preset.config.colorTheme.accentColor)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 3)
                                        .stroke(preset.config.colorTheme.accentColor.opacity(0.8), lineWidth: 1)
                                )
                                .cornerRadius(3)
                            }

                            if let cue = slide.midiCue {
                                HStack(spacing: 3) {
                                    Image(systemName: "pianokeys")
                                        .font(.system(size: 8))
                                    Text(cue.shortBadgeText)
                                        .font(.system(size: 9, weight: .bold))
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.black.opacity(0.85))
                                .foregroundColor(.yellow)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 3)
                                        .stroke(Color.yellow.opacity(0.8), lineWidth: 1)
                                )
                                .cornerRadius(3)
                            }

                            Spacer()
                        }
                    }
                    .padding(6)
                }
                .aspectRatio(16/9, contentMode: .fit)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(borderColor, lineWidth: borderWidth)
                )

                HStack(spacing: 4) {
                    Text(slide.title)
                        .font(.caption)
                        .fontWeight(isCurrent ? .bold : .regular)
                        .lineLimit(1)
                        .foregroundColor(isCurrent ? .primary : .secondary)

                    Spacer()

                    Menu {
                        slideActionsMenuContent
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 18)
                    .help("Slide Stage Preset Cue & Edit Options")
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            slideActionsMenuContent
        }
    }

    private var borderColor: Color {
        if isCurrent {
            return .red
        } else if isSelected {
            return .accentColor
        } else if let hex = slide.serviceSectionColorHex, let secColor = Color(hex: hex) {
            return secColor.opacity(0.7)
        } else if assignedPreset != nil {
            return Color.cyan.opacity(0.5)
        } else {
            return Color.white.opacity(0.12)
        }
    }

    private var borderWidth: CGFloat {
        if isCurrent {
            return 3.0
        } else if isSelected {
            return 3.0
        } else if slide.serviceSectionColorHex != nil {
            return 1.8
        } else {
            return 1.2
        }
    }

    @ViewBuilder
    private var slideActionsMenuContent: some View {
        Button {
            onSelect()
        } label: {
            Label("Trigger Slide #\(slide.index + 1) Live", systemImage: "play.fill")
        }

        Button {
            onEditSlide()
        } label: {
            Label("Edit Slide Text & Cues...", systemImage: "slider.horizontal.below.rectangle")
        }

        Divider()

        // Service Section Menu
        Menu("Assign to Service Section") {
            Button {
                onAssignServiceSection(nil)
            } label: {
                if slide.serviceSectionID == nil {
                    Label("None (Clear Section) ✓", systemImage: "minus.circle")
                } else {
                    Text("None (Clear Section)")
                }
            }

            Divider()

            ForEach(ServiceFlowManager.shared.sections) { sec in
                Button {
                    onAssignServiceSection(sec)
                } label: {
                    if slide.serviceSectionID == sec.id {
                        Text("\(sec.name) ✓")
                    } else {
                        Text(sec.name)
                    }
                }
            }
        }

        Divider()

        // Stage Layout Preset Cue Menu
        Menu("Assign Stage Layout Preset Cue") {
            Button {
                onAssignPreset(nil)
            } label: {
                if slide.stageLayoutPresetID == nil {
                    Label("None (Keep Previous Layout) ✓", systemImage: "minus.circle")
                } else {
                    Text("None (Keep Previous Layout)")
                }
            }

            Divider()

            ForEach(availablePresets) { preset in
                Button {
                    onAssignPreset(preset.id)
                } label: {
                    if slide.stageLayoutPresetID == preset.id {
                        Text("⚡ \(preset.name) ✓")
                    } else {
                        Text("⚡ \(preset.name)")
                    }
                }
            }
        }

        if slide.stageLayoutPresetID != nil {
            Button(role: .destructive) {
                onAssignPreset(nil)
            } label: {
                Label("Remove Stage Preset Cue", systemImage: "trash")
            }
        }

        Divider()

        // MIDI Action Cue Menu (Direct Access)
        if let midiCue = slide.midiCue {
            Menu("MIDI Cue (\(midiCue.shortBadgeText))") {
                Button {
                    MIDIManager.shared.testSend(cue: midiCue)
                } label: {
                    Label("Test Fire MIDI (\(midiCue.displayName))", systemImage: "paperplane.fill")
                }

                Button {
                    onEditSlide()
                } label: {
                    Label("Edit MIDI Cue Parameters...", systemImage: "pencil")
                }

                Divider()

                Button(role: .destructive) {
                    onAssignMIDICue(nil)
                } label: {
                    Label("Remove MIDI Cue", systemImage: "trash")
                }
            }
        } else {
            Button {
                onEditSlide()
            } label: {
                Label("Add MIDI Action Cue...", systemImage: "pianokeys")
            }
        }
    }
}
