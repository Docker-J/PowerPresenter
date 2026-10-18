import SwiftUI

public struct StageLayoutEditorView: View {
    @ObservedObject var engine = PresentationEngine.shared
    @Environment(\.dismiss) private var dismiss
    @State private var newPresetName: String = ""
    @State private var selectedElementID: UUID? = nil

    public init() {}

    private var activeElements: [StageElement] {
        if engine.stageLayout.elements.isEmpty {
            return StageLayoutConfig.defaultElements(for: engine.stageLayout.style, colorTheme: engine.stageLayout.colorTheme)
        }
        return engine.stageLayout.elements
    }

    private var selectedElement: StageElement? {
        activeElements.first(where: { $0.id == selectedElementID })
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Stage Screen Freeform Layout Editor")
                        .font(.title2.bold())
                    Text("ProPresenter-style layout designer: Add widgets, drag to reposition, resize frames, and customize typography.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()

                Button("Reset to Preset Defaults") {
                    engine.stageLayout.elements = StageLayoutConfig.defaultElements(for: engine.stageLayout.style, colorTheme: engine.stageLayout.colorTheme)
                    selectedElementID = nil
                }
                .buttonStyle(.bordered)

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // 3-Pane Workspace
            HSplitView {
                // Left Pane: Presets & Elements List
                VStack(spacing: 0) {
                    presetsSection
                    Divider()
                    elementsListSection
                }
                .frame(minWidth: 230, maxWidth: 270)

                // Center Pane: Interactive 16:9 Canvas Designer
                interactiveCanvasPane
                    .frame(minWidth: 500, maxWidth: .infinity)

                // Right Pane: Selected Element Inspector
                elementInspectorPane
                    .frame(minWidth: 280, maxWidth: 340)
            }
        }
        .frame(minWidth: 1140, minHeight: 740)
        .onAppear {
            if engine.stageLayout.elements.isEmpty {
                engine.stageLayout.elements = StageLayoutConfig.defaultElements(for: engine.stageLayout.style, colorTheme: engine.stageLayout.colorTheme)
            }
            if selectedElementID == nil {
                selectedElementID = engine.stageLayout.elements.first?.id
            }
        }
    }

    // MARK: - Left Pane 1: Presets

    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("STAGE PRESETS")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            ScrollView {
                VStack(spacing: 4) {
                    ForEach(engine.stagePresets) { preset in
                        let isSelected = (preset.id == engine.activeStagePresetID)
                        Button(action: {
                            engine.applyStagePreset(id: preset.id)
                            selectedElementID = engine.stageLayout.elements.first?.id
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: preset.iconName)
                                    .foregroundColor(isSelected ? .white : preset.config.colorTheme.accentColor)
                                    .frame(width: 18)

                                Text(preset.name)
                                    .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                                    .foregroundColor(isSelected ? .white : .primary)
                                    .lineLimit(1)

                                Spacer()

                                if isSelected {
                                    Text("ACTIVE")
                                        .font(.system(size: 8, weight: .black, design: .monospaced))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Color.white.opacity(0.25))
                                        .foregroundColor(.white)
                                        .cornerRadius(3)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(isSelected ? Color.accentColor : Color.clear)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
            }
            .frame(maxHeight: 150)

            HStack(spacing: 4) {
                TextField("New preset...", text: $newPresetName)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)

                Button(action: {
                    let name = newPresetName.trimmingCharacters(in: .whitespacesAndNewlines)
                    engine.createStagePreset(name: name.isEmpty ? "Custom Stage \(engine.stagePresets.count + 1)" : name)
                    newPresetName = ""
                }) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Left Pane 2: Elements Layer List

    private var elementsListSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("STAGE ELEMENTS")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()

                Menu {
                    ForEach(StageElementKind.allCases, id: \.self) { kind in
                        Button(kind.rawValue) {
                            engine.stageLayout.addElement(kind: kind)
                            selectedElementID = engine.stageLayout.elements.last?.id
                        }
                    }
                } label: {
                    Label("Add", systemImage: "plus.circle.fill")
                        .font(.caption.bold())
                }
                .menuStyle(.borderlessButton)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            ScrollView {
                VStack(spacing: 4) {
                    ForEach(engine.stageLayout.elements) { elem in
                        let isSelected = (elem.id == selectedElementID)
                        HStack(spacing: 6) {
                            Button(action: {
                                selectedElementID = elem.id
                            }) {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(colorFromHex(elem.borderColorHex, defaultColor: .yellow))
                                        .frame(width: 8, height: 8)

                                    Text(elem.label)
                                        .font(.system(size: 12, weight: isSelected ? .bold : .regular))
                                        .foregroundColor(isSelected ? .white : .primary)
                                        .lineLimit(1)

                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)

                            Button(action: {
                                var copy = elem
                                copy.isVisible.toggle()
                                engine.stageLayout.updateElement(copy)
                            }) {
                                Image(systemName: elem.isVisible ? "eye.fill" : "eye.slash")
                                    .font(.caption)
                                    .foregroundColor(elem.isVisible ? .secondary : .gray.opacity(0.5))
                            }
                            .buttonStyle(.plain)

                            Button(role: .destructive, action: {
                                engine.stageLayout.removeElement(id: elem.id)
                                if selectedElementID == elem.id {
                                    selectedElementID = engine.stageLayout.elements.first?.id
                                }
                            }) {
                                Image(systemName: "trash")
                                    .font(.caption2)
                                    .foregroundColor(.red.opacity(0.8))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(isSelected ? Color.accentColor : Color(NSColor.controlBackgroundColor).opacity(0.5))
                        .cornerRadius(6)
                    }
                }
                .padding(.horizontal, 8)
            }
        }
    }

    // MARK: - Center Pane: Interactive 16:9 Canvas Designer

    private var interactiveCanvasPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("STAGE SCREEN 16:9 CANVAS")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)

                Spacer()

                if let sel = selectedElement {
                    Text("Selected: \(sel.label)")
                        .font(.caption.bold())
                        .foregroundColor(.yellow)
                } else {
                    Text("Click any widget to reposition / resize")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            // Interactive Canvas
            GeometryReader { geo in
                let canvasW = geo.size.width
                let canvasH = geo.size.height

                ZStack(alignment: .topLeading) {
                    // Pure Black Stage Screen Background
                    Color.black

                    // Grid Guidelines (subtle 10% divisions)
                    CanvasGridOverlay()

                    // Render Elements with Drag & Resize
                    ForEach(engine.stageLayout.elements) { element in
                        if element.isVisible {
                            interactiveElementCard(element, canvasW: canvasW, canvasH: canvasH)
                        }
                    }
                }
                .aspectRatio(16/9, contentMode: .fit)
                .frame(width: canvasW, height: canvasH)
                .clipped()
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.3), lineWidth: 1.5)
                )
            }
            .aspectRatio(16/9, contentMode: .fit)

            // Canvas Quick Controls
            HStack {
                Menu {
                    ForEach(StageElementKind.allCases, id: \.self) { kind in
                        Button(kind.rawValue) {
                            engine.stageLayout.addElement(kind: kind)
                            selectedElementID = engine.stageLayout.elements.last?.id
                        }
                    }
                } label: {
                    Label("Add Widget...", systemImage: "plus.rectangle.on.rectangle")
                }

                if let sel = selectedElement {
                    Button(role: .destructive, action: {
                        engine.stageLayout.removeElement(id: sel.id)
                        selectedElementID = engine.stageLayout.elements.first?.id
                    }) {
                        Label("Delete Widget", systemImage: "trash")
                    }
                }

                Spacer()

                if let curSlide = engine.currentSlide {
                    if curSlide.stageLayoutPresetID == engine.activeStagePresetID {
                        Button("Remove Cue from Slide #\(curSlide.index + 1)") {
                            engine.assignStagePreset(nil, toSlideAt: curSlide.index)
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Button("⚡ Assign Preset to Slide #\(curSlide.index + 1)") {
                            engine.assignStagePreset(engine.activeStagePresetID, toSlideAt: curSlide.index)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .padding(.top, 4)
        }
        .padding(14)
    }

    @ViewBuilder
    private func interactiveElementCard(_ element: StageElement, canvasW: CGFloat, canvasH: CGFloat) -> some View {
        let isSelected = (element.id == selectedElementID)
        let elemX = element.rect.x * canvasW
        let elemY = element.rect.y * canvasH
        let elemW = max(30, element.rect.width * canvasW)
        let elemH = max(24, element.rect.height * canvasH)

        let borderColor = isSelected ? Color.yellow : colorFromHex(element.borderColorHex, defaultColor: .yellow)
        let bgColor = colorFromHex(element.backgroundColorHex, defaultColor: Color(white: 0.1))

        ZStack(alignment: .bottomTrailing) {
            // Main Widget Box
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(bgColor)

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(element.label.uppercased())
                            .font(.system(size: max(8, 10 * (canvasW / 900.0)), weight: .heavy, design: .monospaced))
                            .foregroundColor(borderColor)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 6)
                    .padding(.top, 4)

                    // Representative preview of content
                    Group {
                        switch element.kind {
                        case .clock:
                            Text("10:30:00 AM")
                                .font(.system(size: max(10, element.fontSize * 0.4 * (canvasW / 900.0)), weight: .black, design: .monospaced))
                        case .timer:
                            Text("25:00")
                                .font(.system(size: max(10, element.fontSize * 0.4 * (canvasW / 900.0)), weight: .black, design: .monospaced))
                                .foregroundColor(.green)
                        case .slideCounter:
                            Text("1/58")
                                .font(.system(size: max(10, element.fontSize * 0.4 * (canvasW / 900.0)), weight: .bold, design: .monospaced))
                                .foregroundColor(.cyan)
                        case .currentSlideText:
                            let t = engine.currentSlide?.primaryStageText ?? "Current Slide Lyrics / Body Text"
                            Text(t.isEmpty ? "(Lyrics / Body Text)" : t)
                                .font(.system(size: max(10, element.fontSize * 0.35 * (canvasW / 900.0)), weight: .bold))
                                .lineLimit(3)
                        case .nextSlideText:
                            let nt = engine.nextSlide?.primaryStageText ?? "Next Slide Lyrics..."
                            Text(nt.isEmpty ? "(Next Lyrics Preview)" : nt)
                                .font(.system(size: max(9, element.fontSize * 0.3 * (canvasW / 900.0)), weight: .semibold))
                                .foregroundColor(.cyan)
                                .lineLimit(2)
                        case .currentSlideVisual:
                            ZStack {
                                Color.black.opacity(0.8)
                                Text("SLIDE SCREEN").font(.system(size: 9, weight: .bold)).foregroundColor(.red)
                            }
                        case .nextSlideVisual:
                            ZStack {
                                Color.black.opacity(0.8)
                                Text("NEXT SCREEN").font(.system(size: 9, weight: .bold)).foregroundColor(.cyan)
                            }
                        case .namedElement:
                            Text("[\(element.targetKey.uppercased())]: Content")
                                .font(.system(size: max(9, element.fontSize * 0.3 * (canvasW / 900.0)), weight: .bold))
                        case .presenterNotes:
                            Text("Presenter notes text...")
                                .font(.system(size: max(9, element.fontSize * 0.3 * (canvasW / 900.0))))
                                .foregroundColor(.gray)
                        case .stageAlert:
                            Text("ALERT MESSAGE")
                                .font(.system(size: max(9, element.fontSize * 0.3 * (canvasW / 900.0)), weight: .black))
                                .foregroundColor(.yellow)
                        case .customLabel:
                            Text(element.label)
                                .font(.system(size: max(9, element.fontSize * 0.3 * (canvasW / 900.0)), weight: .bold))
                        }
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 6)
                    .padding(.bottom, 4)
                }

                // Border
                RoundedRectangle(cornerRadius: 6)
                    .stroke(borderColor, lineWidth: isSelected ? 2.5 : element.borderWidth)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                selectedElementID = element.id
            }
            // Drag gesture to move element position
            .gesture(
                DragGesture()
                    .onChanged { value in
                        selectedElementID = element.id
                        var updated = element
                        let newX = max(0.0, min(1.0 - element.rect.width, (elemX + value.translation.width) / canvasW))
                        let newY = max(0.0, min(1.0 - element.rect.height, (elemY + value.translation.height) / canvasH))
                        updated.rect.x = newX
                        updated.rect.y = newY
                        engine.stageLayout.updateElement(updated)
                    }
            )

            // Bottom-right resize handle when selected
            if isSelected {
                Image(systemName: "arrow.down.right.square.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.yellow)
                    .background(Color.black)
                    .padding(2)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                var updated = element
                                let newW = max(0.05, min(1.0 - element.rect.x, (elemW + value.translation.width) / canvasW))
                                let newH = max(0.04, min(1.0 - element.rect.y, (elemH + value.translation.height) / canvasH))
                                updated.rect.width = newW
                                updated.rect.height = newH
                                engine.stageLayout.updateElement(updated)
                            }
                    )
            }
        }
        .frame(width: elemW, height: elemH)
        .position(x: elemX + elemW / 2.0, y: elemY + elemH / 2.0)
    }

    // MARK: - Right Pane: Element Inspector

    private var elementInspectorPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let sel = selectedElement {
                    // Header
                    HStack {
                        Text("WIDGET PROPERTIES")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                        Spacer()
                    }

                    // Label & Kind
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Widget Label:")
                            .font(.caption.bold())
                        TextField("Label", text: Binding(
                            get: { sel.label },
                            set: {
                                var copy = sel
                                copy.label = $0
                                engine.stageLayout.updateElement(copy)
                            }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }

                    Divider()

                    // Position & Size Sliders
                    VStack(alignment: .leading, spacing: 10) {
                        Text("FRAME & POSITION")
                            .font(.caption.bold())
                            .foregroundColor(.accentColor)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text("X Position:")
                                    .font(.caption2)
                                Spacer()
                                Text("\(Int(sel.rect.x * 100))%")
                                    .font(.caption2.monospaced())
                            }
                            Slider(value: Binding(
                                get: { sel.rect.x },
                                set: {
                                    var copy = sel
                                    copy.rect.x = max(0, min(1.0 - copy.rect.width, $0))
                                    engine.stageLayout.updateElement(copy)
                                }
                            ), in: 0...0.95)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text("Y Position:")
                                    .font(.caption2)
                                Spacer()
                                Text("\(Int(sel.rect.y * 100))%")
                                    .font(.caption2.monospaced())
                            }
                            Slider(value: Binding(
                                get: { sel.rect.y },
                                set: {
                                    var copy = sel
                                    copy.rect.y = max(0, min(1.0 - copy.rect.height, $0))
                                    engine.stageLayout.updateElement(copy)
                                }
                            ), in: 0...0.95)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text("Width:")
                                    .font(.caption2)
                                Spacer()
                                Text("\(Int(sel.rect.width * 100))%")
                                    .font(.caption2.monospaced())
                            }
                            Slider(value: Binding(
                                get: { sel.rect.width },
                                set: {
                                    var copy = sel
                                    copy.rect.width = max(0.05, min(1.0 - copy.rect.x, $0))
                                    engine.stageLayout.updateElement(copy)
                                }
                            ), in: 0.05...1.0)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text("Height:")
                                    .font(.caption2)
                                Spacer()
                                Text("\(Int(sel.rect.height * 100))%")
                                    .font(.caption2.monospaced())
                            }
                            Slider(value: Binding(
                                get: { sel.rect.height },
                                set: {
                                    var copy = sel
                                    copy.rect.height = max(0.04, min(1.0 - copy.rect.y, $0))
                                    engine.stageLayout.updateElement(copy)
                                }
                            ), in: 0.04...1.0)
                        }
                    }

                    Divider()

                    // Typography
                    VStack(alignment: .leading, spacing: 10) {
                        Text("TYPOGRAPHY & ALIGNMENT")
                            .font(.caption.bold())
                            .foregroundColor(.accentColor)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text("Font Size:")
                                    .font(.caption2)
                                Spacer()
                                Text("\(Int(sel.fontSize)) pt")
                                    .font(.caption2.monospaced())
                            }
                            Slider(value: Binding(
                                get: { sel.fontSize },
                                set: {
                                    var copy = sel
                                    copy.fontSize = $0
                                    engine.stageLayout.updateElement(copy)
                                }
                            ), in: 14...96, step: 2)
                        }

                        Picker("Alignment:", selection: Binding(
                            get: { sel.textAlignment },
                            set: {
                                var copy = sel
                                copy.textAlignment = $0
                                engine.stageLayout.updateElement(copy)
                            }
                        )) {
                            Text("Left").tag(SlideTextAlignment.left)
                            Text("Center").tag(SlideTextAlignment.center)
                            Text("Right").tag(SlideTextAlignment.right)
                        }
                        .pickerStyle(.segmented)
                    }

                    Divider()

                    // Colors & Borders
                    VStack(alignment: .leading, spacing: 10) {
                        Text("COLORS & BORDER")
                            .font(.caption.bold())
                            .foregroundColor(.accentColor)

                        HStack {
                            Text("Border Hex:")
                                .font(.caption2)
                            TextField("#EAA822", text: Binding(
                                get: { sel.borderColorHex },
                                set: {
                                    var copy = sel
                                    copy.borderColorHex = $0
                                    engine.stageLayout.updateElement(copy)
                                }
                            ))
                            .textFieldStyle(.roundedBorder)
                        }

                        HStack {
                            Text("Background Hex:")
                                .font(.caption2)
                            TextField("#141414", text: Binding(
                                get: { sel.backgroundColorHex },
                                set: {
                                    var copy = sel
                                    copy.backgroundColorHex = $0
                                    engine.stageLayout.updateElement(copy)
                                }
                            ))
                            .textFieldStyle(.roundedBorder)
                        }

                        HStack {
                            Text("Font Hex:")
                                .font(.caption2)
                            TextField("#FFFFFF", text: Binding(
                                get: { sel.fontColorHex },
                                set: {
                                    var copy = sel
                                    copy.fontColorHex = $0
                                    engine.stageLayout.updateElement(copy)
                                }
                            ))
                            .textFieldStyle(.roundedBorder)
                        }
                    }

                    if sel.kind == .namedElement {
                        Divider()
                        VStack(alignment: .leading, spacing: 6) {
                            Text("NAMED ELEMENT TARGET")
                                .font(.caption.bold())
                                .foregroundColor(.accentColor)

                            HStack {
                                TextField("Target Key (e.g. lyrics)", text: Binding(
                                    get: { sel.targetKey },
                                    set: {
                                        var copy = sel
                                        copy.targetKey = $0
                                        engine.stageLayout.updateElement(copy)
                                    }
                                ))
                                .textFieldStyle(.roundedBorder)

                                Menu("Keys...") {
                                    ForEach(engine.allKnownNamedElements, id: \.self) { key in
                                        Button(key) {
                                            var copy = sel
                                            copy.targetKey = key
                                            engine.stageLayout.updateElement(copy)
                                        }
                                    }
                                }
                                .frame(width: 80)
                            }
                        }
                    }
                } else {
                    // No element selected: Show preset settings
                    VStack(alignment: .leading, spacing: 12) {
                        Text("PRESET SETTINGS")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)

                        if let activePreset = engine.activeStagePreset {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Preset Name:")
                                    .font(.caption.bold())
                                TextField("Preset Name", text: Binding(
                                    get: { activePreset.name },
                                    set: { engine.renameStagePreset(id: activePreset.id, newName: $0) }
                                ))
                                .textFieldStyle(.roundedBorder)
                            }
                        }

                        Picker("Base Layout Style:", selection: $engine.stageLayout.style) {
                            ForEach(StageLayoutStyle.allCases, id: \.self) { style in
                                Text(style.rawValue).tag(style)
                            }
                        }
                        .pickerStyle(.menu)

                        Picker("Color Theme:", selection: $engine.stageLayout.colorTheme) {
                            ForEach(StageColorTheme.allCases, id: \.self) { theme in
                                Text(theme.rawValue).tag(theme)
                            }
                        }
                        .pickerStyle(.radioGroup)

                        Divider()

                        Text("Click any widget in the canvas or layer list to modify its size, position, and styling.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(14)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func colorFromHex(_ hex: String, defaultColor: Color) -> Color {
        var cleanHex = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if cleanHex.hasPrefix("#") { cleanHex.removeFirst() }
        guard cleanHex.count == 6, let rgbValue = UInt64(cleanHex, radix: 16) else {
            return defaultColor
        }
        let r = Double((rgbValue & 0xFF0000) >> 16) / 255.0
        let g = Double((rgbValue & 0x00FF00) >> 8) / 255.0
        let b = Double(rgbValue & 0x0000FF) / 255.0
        return Color(red: r, green: g, blue: b)
    }
}

private struct CanvasGridOverlay: View {
    var body: some View {
        GeometryReader { geo in
            Path { path in
                let w = geo.size.width
                let h = geo.size.height
                // vertical grid lines at 25%, 50%, 75%
                for frac in [0.25, 0.50, 0.75] {
                    path.move(to: CGPoint(x: w * frac, y: 0))
                    path.addLine(to: CGPoint(x: w * frac, y: h))
                }
                // horizontal grid lines at 25%, 50%, 75%
                for frac in [0.25, 0.50, 0.75] {
                    path.move(to: CGPoint(x: 0, y: h * frac))
                    path.addLine(to: CGPoint(x: w, y: h * frac))
                }
            }
            .stroke(Color.white.opacity(0.08), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
    }
}
