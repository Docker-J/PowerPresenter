import SwiftUI

public struct ServiceFlowConfigSheetView: View {
    @ObservedObject var flow = ServiceFlowManager.shared
    @ObservedObject var engine = PresentationEngine.shared
    @Environment(\.dismiss) private var dismiss

    @State private var selectedSectionID: UUID? = nil
    @State private var showingAddSheet = false

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "list.bullet.indent")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Service Flow Editor (예배 순서 템플릿)")
                        .font(.headline)
                    Text("Configure your church liturgy sections, default stage layouts, and start MIDI cues.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Reset to Church Defaults") {
                    flow.resetToDefaults()
                    selectedSectionID = flow.sections.first?.id
                }
                .buttonStyle(.bordered)
                .help("Reset to: 카운트다운영상 - 호스팅 - 찬양 - 말씀 - 결단찬양/기도 - 광고")

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(18)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Main Split: Section List on Left, Section Detail Editor on Right
            HSplitView {
                // Left: Sections List
                VStack(spacing: 0) {
                    HStack {
                        Text("ORDER OF SERVICE")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                        Spacer()
                        Button {
                            addNewSection()
                        } label: {
                            Label("Add Section", systemImage: "plus")
                                .font(.caption2)
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))

                    Divider()

                    List(selection: $selectedSectionID) {
                        ForEach(Array(flow.sections.enumerated()), id: \.element.id) { index, sec in
                            SectionRow(index: index, section: sec)
                                .tag(sec.id)
                        }
                        .onMove { source, destination in
                            flow.moveSection(from: source, to: destination)
                        }
                        .onDelete { indexSet in
                            flow.removeSection(at: indexSet)
                            if selectedSectionID == nil || !flow.sections.contains(where: { $0.id == selectedSectionID }) {
                                selectedSectionID = flow.sections.first?.id
                            }
                        }
                    }
                    .listStyle(.sidebar)
                }
                .frame(minWidth: 260, idealWidth: 290, maxWidth: 340)

                // Right: Detail Inspector
                VStack(alignment: .leading, spacing: 0) {
                    if let selected = flow.sections.first(where: { $0.id == selectedSectionID }) {
                        SectionDetailInspector(
                            section: selected,
                            availablePresets: engine.stagePresets,
                            onSave: { updated in
                                flow.updateSection(updated)
                            },
                            onDelete: {
                                if let idx = flow.sections.firstIndex(where: { $0.id == selected.id }) {
                                    flow.removeSection(at: IndexSet(integer: idx))
                                    selectedSectionID = flow.sections.first?.id
                                }
                            }
                        )
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "hand.tap")
                                .font(.system(size: 36))
                                .foregroundColor(.secondary)
                            Text("Select a service section to edit its properties.")
                                .font(.callout)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(minWidth: 380, idealWidth: 440)
            }
        }
        .frame(minWidth: 700, minHeight: 480)
        .onAppear {
            if selectedSectionID == nil {
                selectedSectionID = flow.sections.first?.id
            }
        }
    }

    private func addNewSection() {
        let newSec = ServiceSection(
            name: "새 순서",
            iconName: "flag.fill",
            colorHex: "#3B82F6",
            defaultStagePresetID: engine.stagePresets.first?.id,
            triggerMIDICue: nil
        )
        flow.addSection(newSec)
        selectedSectionID = newSec.id
    }
}

private struct SectionRow: View {
    let index: Int
    let section: ServiceSection

    var body: some View {
        HStack(spacing: 10) {
            Text("\(index + 1)")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 18)

            ZStack {
                Circle()
                    .fill(section.color.opacity(0.2))
                    .frame(width: 26, height: 26)
                Image(systemName: section.iconName)
                    .font(.system(size: 12))
                    .foregroundColor(section.color)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(section.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)

                HStack(spacing: 4) {
                    if let presetID = section.defaultStagePresetID,
                       let preset = PresentationEngine.shared.preset(for: presetID) {
                        Text("⚡ \(preset.name)")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                    if section.triggerMIDICue != nil {
                        Text("🎹 MIDI")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.yellow)
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 3)
    }
}

private struct SectionDetailInspector: View {
    let section: ServiceSection
    let availablePresets: [StageLayoutPreset]
    let onSave: (ServiceSection) -> Void
    let onDelete: () -> Void

    @State private var name: String = ""
    @State private var iconName: String = "folder.fill"
    @State private var colorHex: String = "#3B82F6"
    @State private var defaultStagePresetID: UUID? = nil

    // MIDI Cue Settings
    @State private var hasMIDICue: Bool = false
    @State private var midiChannel: Int = 1
    @State private var midiType: MIDICueType = .controlChange
    @State private var midiNumber: Int = 20
    @State private var midiValue: Int = 1

    private let iconPresets = [
        "video.fill", "mic.fill", "music.note", "book.fill",
        "hands.sparkles.fill", "megaphone.fill", "cross.fill",
        "sparkles", "person.3.fill", "heart.fill", "flag.fill", "film.fill"
    ]

    private let colorPresets = [
        "#8B5CF6", "#F59E0B", "#3B82F6", "#10B981",
        "#EC4899", "#06B6D4", "#EF4444", "#6366F1", "#84CC16"
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Section Identity
                VStack(alignment: .leading, spacing: 12) {
                    Text("SECTION IDENTITY")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)

                    HStack(spacing: 12) {
                        TextField("Section Name (e.g. 찬양, 말씀, 광고)", text: $name)
                            .textFieldStyle(.roundedBorder)
                            .font(.body.weight(.semibold))

                        Button(role: .destructive, action: onDelete) {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("Delete this section")
                    }

                    // Icon Picker
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Icon")
                            .font(.caption2.bold())
                            .foregroundColor(.secondary)

                        HStack(spacing: 8) {
                            ForEach(iconPresets, id: \.self) { icon in
                                Button {
                                    iconName = icon
                                    commitChanges()
                                } label: {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(iconName == icon ? Color(hex: colorHex) ?? .blue : Color.secondary.opacity(0.12))
                                            .frame(width: 28, height: 28)
                                        Image(systemName: icon)
                                            .font(.caption)
                                            .foregroundColor(iconName == icon ? .white : .primary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // Color Picker
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Section Theme Color")
                            .font(.caption2.bold())
                            .foregroundColor(.secondary)

                        HStack(spacing: 8) {
                            ForEach(colorPresets, id: \.self) { cHex in
                                Button {
                                    colorHex = cHex
                                    commitChanges()
                                } label: {
                                    Circle()
                                        .fill(Color(hex: cHex) ?? .blue)
                                        .frame(width: 22, height: 22)
                                        .overlay(
                                            Circle()
                                                .stroke(Color.white, lineWidth: colorHex == cHex ? 2.5 : 0)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(16)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)

                // Stage Display Auto Cue
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "bolt.fill")
                            .foregroundColor(.cyan)
                        Text("DEFAULT STAGE DISPLAY LAYOUT")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                    }

                    Text("Automatically switches the confidence monitor when the first slide of this section goes live:")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Picker("Stage Preset", selection: $defaultStagePresetID) {
                        Text("None (Keep Current Layout)").tag(UUID?.none)
                        Divider()
                        ForEach(availablePresets) { preset in
                            Text("⚡ \(preset.name)").tag(UUID?.some(preset.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: defaultStagePresetID) {
                        commitChanges()
                    }
                }
                .padding(16)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)

                // Section Start MIDI Cue
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "pianokeys")
                            .foregroundColor(.yellow)
                        Text("SECTION START MIDI CUE (1회 자동 발송)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                        Spacer()
                        Toggle("", isOn: $hasMIDICue)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .onChange(of: hasMIDICue) {
                                commitChanges()
                            }
                    }

                    Text("Sends a MIDI signal (lighting scene / Ableton play) on the first slide of this section only:")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if hasMIDICue {
                        VStack(spacing: 10) {
                            HStack(spacing: 12) {
                                Picker("Type", selection: $midiType) {
                                    ForEach(MIDICueType.allCases, id: \.self) { type in
                                        Text(type.rawValue).tag(type)
                                    }
                                }
                                .frame(width: 170)

                                Picker("Ch", selection: $midiChannel) {
                                    ForEach(1...16, id: \.self) { ch in
                                        Text("Ch \(ch)").tag(ch)
                                    }
                                }
                                .frame(width: 80)
                            }

                            HStack(spacing: 12) {
                                HStack {
                                    Text(midiType == .noteOn ? "Note:" : (midiType == .programChange ? "Program #:" : "CC #:"))
                                        .font(.caption)
                                    TextField("0-127", value: $midiNumber, formatter: NumberFormatter())
                                        .textFieldStyle(.roundedBorder)
                                }

                                if midiType != .programChange {
                                    HStack {
                                        Text("Value:")
                                            .font(.caption)
                                        TextField("0-127", value: $midiValue, formatter: NumberFormatter())
                                            .textFieldStyle(.roundedBorder)
                                    }
                                }

                                Button {
                                    testFireMIDI()
                                } label: {
                                    Label("Test Fire", systemImage: "bolt.fill")
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(.top, 4)
                        .onChange(of: midiType) { commitChanges() }
                        .onChange(of: midiChannel) { commitChanges() }
                        .onChange(of: midiNumber) { commitChanges() }
                        .onChange(of: midiValue) { commitChanges() }
                    }
                }
                .padding(16)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }
            .padding(20)
        }
        .onAppear {
            syncFromSection()
        }
        .onChange(of: section.id) {
            syncFromSection()
        }
    }

    private func syncFromSection() {
        self.name = section.name
        self.iconName = section.iconName
        self.colorHex = section.colorHex
        self.defaultStagePresetID = section.defaultStagePresetID

        if let cue = section.triggerMIDICue {
            self.hasMIDICue = true
            self.midiType = cue.type
            self.midiChannel = Int(cue.channel)
            self.midiNumber = Int(cue.number)
            self.midiValue = Int(cue.value)
        } else {
            self.hasMIDICue = false
            self.midiType = .controlChange
            self.midiChannel = 1
            self.midiNumber = 20
            self.midiValue = 1
        }
    }

    private func commitChanges() {
        var cue: MIDICue? = nil
        if hasMIDICue {
            cue = MIDICue(
                type: midiType,
                channel: UInt8(max(1, min(16, midiChannel))),
                number: UInt8(max(0, min(127, midiNumber))),
                value: UInt8(max(0, min(127, midiValue)))
            )
        }

        let updated = ServiceSection(
            id: section.id,
            name: name.isEmpty ? "Section" : name,
            iconName: iconName,
            colorHex: colorHex,
            defaultStagePresetID: defaultStagePresetID,
            triggerMIDICue: cue
        )
        onSave(updated)
    }

    private func testFireMIDI() {
        let testCue = MIDICue(
            type: midiType,
            channel: UInt8(max(1, min(16, midiChannel))),
            number: UInt8(max(0, min(127, midiNumber))),
            value: UInt8(max(0, min(127, midiValue)))
        )
        MIDIManager.shared.send(cue: testCue)
    }
}
