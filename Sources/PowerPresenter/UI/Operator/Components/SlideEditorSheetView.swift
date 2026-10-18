import SwiftUI

public struct SlideEditorSheetView: View {
    @ObservedObject var engine: PresentationEngine
    let slideIndex: Int
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var notes: String = ""
    @State private var selectedPresetID: UUID? = nil
    @State private var hasMidiCue: Bool = false
    @State private var midiType: MIDICueType = .controlChange
    @State private var midiChannel: Int = 1
    @State private var midiNumber: Int = 20
    @State private var midiValue: Int = 127
    @State private var testSentSuccess: Bool = false
    @State private var elements: [SlideElement] = []
    @State private var namedEntries: [(key: String, value: String)] = []
    @State private var newElementKey: String = ""
    @State private var newElementValue: String = ""
    @State private var reRenderCanvasOnSave: Bool = true

    public init(engine: PresentationEngine, slideIndex: Int) {
        self.engine = engine
        self.slideIndex = slideIndex
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Edit Slide #\(slideIndex + 1)")
                        .font(.title2.bold())
                    Text("Modify slide text boxes, named elements (for Stage View), presenter notes, Stage Layout Preset, and MIDI Action Cue.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)

                Button("Save Changes") {
                    saveChanges()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(18)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // 1. Stage Layout Preset Cue Assignment
                    VStack(alignment: .leading, spacing: 10) {
                        Label("STAGE LAYOUT PRESET CUE (AUTO-SWITCH ON SLIDE TRIGGER)", systemImage: "bolt.Badge.clock.fill")
                            .font(.headline)
                            .foregroundColor(.cyan)

                        Picker("Assigned Stage Preset:", selection: $selectedPresetID) {
                            Text("None (Keep Current Stage Layout)").tag(UUID?.none)
                            Divider()
                            ForEach(engine.stagePresets) { preset in
                                Text("⚡ \(preset.name) (Target: \(preset.config.targetNamedElement))")
                                    .tag(UUID?.some(preset.id))
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    .padding(14)
                    .background(Color(NSColor.windowBackgroundColor))
                    .cornerRadius(10)

                    // 2. MIDI Action Cue (ProPresenter Action Cue Style)
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("MIDI ACTION CUE (TRIGGER LIGHTING / ABLETON / MIXER)", systemImage: "pianokeys")
                                .font(.headline)
                                .foregroundColor(.yellow)

                            Spacer()

                            Toggle("Enable MIDI Cue", isOn: $hasMidiCue)
                                .toggleStyle(.switch)
                        }

                        if hasMidiCue {
                            Divider()

                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 16) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Command Type:")
                                            .font(.caption.bold())
                                        Picker("", selection: $midiType) {
                                            ForEach(MIDICueType.allCases, id: \.self) { type in
                                                Text(type.rawValue).tag(type)
                                            }
                                        }
                                        .pickerStyle(.segmented)
                                        .frame(width: 320)
                                    }

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("MIDI Channel (1–16):")
                                            .font(.caption.bold())
                                        Picker("", selection: $midiChannel) {
                                            ForEach(1...16, id: \.self) { ch in
                                                Text("Channel \(ch)").tag(ch)
                                            }
                                        }
                                        .pickerStyle(.menu)
                                        .frame(width: 140)
                                    }
                                }

                                HStack(spacing: 16) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(midiType == .noteOn ? "Note Number (0–127):" : (midiType == .controlChange ? "CC Number (0–127):" : "Program Number (0–127):"))
                                                .font(.caption.bold())
                                            if midiType == .noteOn {
                                                Text("[\(MIDICue.noteName(for: UInt8(midiNumber)))]")
                                                    .font(.caption.monospaced().bold())
                                                    .foregroundColor(.yellow)
                                            }
                                        }
                                        HStack(spacing: 8) {
                                            Slider(value: Binding(get: { Double(midiNumber) }, set: { midiNumber = Int($0) }), in: 0...127, step: 1)
                                            TextField("", value: $midiNumber, formatter: NumberFormatter())
                                                .frame(width: 50)
                                                .textFieldStyle(.roundedBorder)
                                        }
                                    }

                                    if midiType != .programChange {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(midiType == .noteOn ? "Velocity (0–127):" : "CC Value (0–127):")
                                                .font(.caption.bold())
                                            HStack(spacing: 8) {
                                                Slider(value: Binding(get: { Double(midiValue) }, set: { midiValue = Int($0) }), in: 0...127, step: 1)
                                                TextField("", value: $midiValue, formatter: NumberFormatter())
                                                    .frame(width: 50)
                                                    .textFieldStyle(.roundedBorder)
                                            }
                                        }
                                    }
                                }

                                HStack {
                                    let tempCue = MIDICue(
                                        type: midiType,
                                        channel: UInt8(midiChannel),
                                        number: UInt8(midiNumber),
                                        value: UInt8(midiValue)
                                    )
                                    Text("Summary: \(tempCue.displayName)")
                                        .font(.caption.monospaced())
                                        .foregroundColor(.secondary)

                                    Spacer()

                                    Button {
                                        MIDIManager.shared.testSend(cue: tempCue)
                                        testSentSuccess = true
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                            testSentSuccess = false
                                        }
                                    } label: {
                                        Label(testSentSuccess ? "MIDI Sent! ✓" : "Test Fire MIDI", systemImage: testSentSuccess ? "checkmark.circle.fill" : "paperplane.fill")
                                            .foregroundColor(testSentSuccess ? .green : .primary)
                                    }
                                    .buttonStyle(.bordered)
                                }
                                .padding(.top, 4)
                            }
                        }
                    }
                    .padding(14)
                    .background(Color(NSColor.windowBackgroundColor))
                    .cornerRadius(10)

                    // 2. Slide Title & Presenter Notes
                    VStack(alignment: .leading, spacing: 10) {
                        Label("SLIDE TITLE & PRESENTER NOTES", systemImage: "note.text")
                            .font(.headline)
                            .foregroundColor(.accentColor)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Slide Title:")
                                .font(.caption.bold())
                            TextField("Slide Title", text: $title)
                                .textFieldStyle(.roundedBorder)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Presenter Notes:")
                                .font(.caption.bold())
                            TextEditor(text: $notes)
                                .font(.system(size: 13))
                                .frame(minHeight: 70, maxHeight: 110)
                                .cornerRadius(6)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                                )
                        }
                    }
                    .padding(14)
                    .background(Color(NSColor.windowBackgroundColor))
                    .cornerRadius(10)

                    // 3. Slide Text Elements & Named Elements
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .center) {
                            Label("SLIDE TEXT BOXES & NAMED ELEMENTS", systemImage: "character.textbox")
                                .font(.headline)
                                .foregroundColor(.accentColor)
                            Spacer()
                            Toggle("Update Audience Screen Graphic", isOn: $reRenderCanvasOnSave)
                                .font(.subheadline.bold())
                                .toggleStyle(.switch)
                        }

                        HStack(spacing: 6) {
                            Image(systemName: reRenderCanvasOnSave ? "sparkles" : "shield.checkered")
                                .foregroundColor(reRenderCanvasOnSave ? .accentColor : .secondary)
                            Text(reRenderCanvasOnSave
                                ? "Audience display will be re-rendered cleanly with the modified text (zero ghosting)."
                                : "Audience display keeps the original PowerPoint slide graphic. Changes apply to Stage Display & Notes only."
                            )
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 2)

                        if !elements.filter({ $0.kind == .text }).isEmpty {
                            ForEach($elements) { $element in
                                if element.kind == .text {
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Text("Shape Name:")
                                                .font(.caption.bold())
                                                .foregroundColor(.secondary)
                                            TextField("Element Name", text: $element.name)
                                                .textFieldStyle(.roundedBorder)
                                                .frame(width: 180)
                                            Spacer()
                                            Text("Font: \(Int(element.fontSizePt)) pt")
                                                .font(.caption.monospaced())
                                            Stepper("", value: $element.fontSizePt, in: 14...96, step: 2)
                                                .labelsHidden()
                                        }

                                        TextEditor(text: $element.text)
                                            .font(.system(size: 13))
                                            .frame(minHeight: 54, maxHeight: 90)
                                            .cornerRadius(6)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                                            )
                                    }
                                    .padding(10)
                                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                                    .cornerRadius(8)
                                }
                            }
                        }

                        Divider()

                        Text("Additional Stage Named Elements (Key / Value):")
                            .font(.caption.bold())

                        ForEach(namedEntries.indices, id: \.self) { idx in
                            HStack(spacing: 8) {
                                TextField("Name (e.g. something)", text: Binding(
                                    get: { namedEntries[idx].key },
                                    set: { namedEntries[idx].key = $0 }
                                ))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 160)

                                TextField("Value", text: Binding(
                                    get: { namedEntries[idx].value },
                                    set: { namedEntries[idx].value = $0 }
                                ))
                                .textFieldStyle(.roundedBorder)

                                Button(role: .destructive, action: {
                                    namedEntries.remove(at: idx)
                                }) {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        // Add new named element row
                        HStack(spacing: 8) {
                            TextField("New element name (e.g. something)", text: $newElementKey)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 200)

                            TextField("Element text content...", text: $newElementValue)
                                .textFieldStyle(.roundedBorder)

                            Button("Add Element") {
                                let k = newElementKey.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !k.isEmpty else { return }
                                namedEntries.append((key: k, value: newElementValue))
                                newElementKey = ""
                                newElementValue = ""
                            }
                            .buttonStyle(.bordered)
                            .disabled(newElementKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    .padding(14)
                    .background(Color(NSColor.windowBackgroundColor))
                    .cornerRadius(10)
                }
                .padding(18)
            }
        }
        .frame(minWidth: 680, minHeight: 580)
        .onAppear {
            loadSlideData()
        }
    }

    private func loadSlideData() {
        guard engine.slides.indices.contains(slideIndex) else { return }
        let slide = engine.slides[slideIndex]
        title = slide.title
        notes = slide.notes ?? ""
        selectedPresetID = slide.stageLayoutPresetID
        elements = slide.elements

        if let cue = slide.midiCue {
            hasMidiCue = true
            midiType = cue.type
            midiChannel = Int(cue.channel)
            midiNumber = Int(cue.number)
            midiValue = Int(cue.value)
        } else {
            hasMidiCue = false
            midiType = .controlChange
            midiChannel = 1
            midiNumber = 20
            midiValue = 127
        }

        // Deduplicate namedElements keys (prefer original case)
        var seenLower = Set<String>()
        var list: [(key: String, value: String)] = []
        for (k, v) in slide.namedElements.sorted(by: { $0.key < $1.key }) {
            let lower = k.lowercased()
            if !seenLower.contains(lower) {
                seenLower.insert(lower)
                list.append((key: k, value: v))
            }
        }
        namedEntries = list
    }

    private func saveChanges() {
        var updatedNamedMap: [String: String] = [:]
        for entry in namedEntries {
            let k = entry.key.trimmingCharacters(in: .whitespacesAndNewlines)
            if !k.isEmpty {
                updatedNamedMap[k] = entry.value
                updatedNamedMap[k.lowercased()] = entry.value
            }
        }
        // Sync updated text from elements into namedMap as well
        for elem in elements where elem.kind == .text {
            let k = elem.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !k.isEmpty && !elem.text.isEmpty {
                updatedNamedMap[k] = elem.text
                updatedNamedMap[k.lowercased()] = elem.text
            }
        }

        var updatedElements = elements

        // Sync element text into paragraphs so NativeSlideRenderer displays the edited text immediately
        for i in updatedElements.indices where updatedElements[i].kind == .text {
            let el = updatedElements[i]
            let run = SlideTextRun(
                text: el.text,
                fontSizePt: el.fontSizePt,
                isBold: el.isBold,
                isItalic: false,
                fontFamily: el.fontFamily,
                textColorHex: el.textColorHex
            )
            updatedElements[i].paragraphs = [SlideParagraph(runs: [run], alignment: el.alignment)]
        }

        // If slide had no text elements yet, create one if re-rendering
        if updatedElements.filter({ $0.kind == .text }).isEmpty && reRenderCanvasOnSave {
            updatedElements.append(
                SlideElement(
                    kind: .text,
                    name: "title",
                    text: title,
                    normalizedRect: CGRect(x: 0.08, y: 0.25, width: 0.84, height: 0.5),
                    fontSizePt: 44,
                    isBold: true,
                    alignment: .center,
                    zOrder: 100
                )
            )
        }

        let finalMidiCue: MIDICue? = hasMidiCue ? MIDICue(
            type: midiType,
            channel: UInt8(midiChannel),
            number: UInt8(midiNumber),
            value: UInt8(midiValue)
        ) : nil

        engine.updateSlide(
            at: slideIndex,
            title: title,
            notes: notes.isEmpty ? nil : notes,
            namedElements: updatedNamedMap,
            elements: updatedElements,
            stageLayoutPresetID: selectedPresetID,
            midiCue: finalMidiCue,
            reRenderVisual: reRenderCanvasOnSave
        )
    }
}
