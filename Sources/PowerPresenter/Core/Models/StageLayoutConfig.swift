import Foundation
import CoreGraphics
import SwiftUI

public enum StageColorTheme: String, Codable, CaseIterable, Sendable {
    case amber = "High-Contrast Amber"
    case cyan = "Cyber Cyan"
    case monochrome = "Classic White"
    case emerald = "Stage Emerald"

    public var accentColor: Color {
        switch self {
        case .amber: return .yellow
        case .cyan: return .cyan
        case .monochrome: return .white
        case .emerald: return .green
        }
    }
}

public enum StageLayoutStyle: String, Codable, CaseIterable, Sendable {
    case standard = "Standard Balanced"
    case worshipLyricsFocus = "Worship Lyrics (Text Only)"
    case namedCueFocus = "Named Element Focus (Large Cue)"
    case notesFocus = "Speaker Notes Focus"
    case dualSlidesLarge = "Dual Slides Large (16:9 Split)"
    case custom = "Custom Freeform"
}

public enum StageElementKind: String, Codable, CaseIterable, Sendable {
    case currentSlideText = "Current Slide Text / Lyrics"
    case nextSlideText = "Next Slide Text Preview"
    case currentSlideVisual = "Current Slide Visual Screen"
    case nextSlideVisual = "Next Slide Visual Screen"
    case clock = "Real-Time Clock"
    case timer = "Presentation Timer"
    case slideCounter = "Slide Counter"
    case presenterNotes = "Presenter Notes"
    case stageAlert = "Stage Alert Banner"
    case namedElement = "Named Element Box (e.g. lyrics, title)"
    case customLabel = "Custom Static Label"

    public var defaultLabel: String {
        switch self {
        case .currentSlideText: return "CURRENT SLIDE TEXT"
        case .nextSlideText: return "NEXT SLIDE TEXT"
        case .currentSlideVisual: return "CURRENT SLIDE"
        case .nextSlideVisual: return "NEXT SLIDE"
        case .clock: return "CLOCK"
        case .timer: return "TIMER"
        case .slideCounter: return "SLIDE"
        case .presenterNotes: return "PRESENTER NOTES"
        case .stageAlert: return "STAGE ALERT"
        case .namedElement: return "NAMED ELEMENT"
        case .customLabel: return "LABEL"
        }
    }
}

public struct StageNormalizedRect: Codable, Sendable, Equatable {
    public var x: CGFloat // 0.0 ~ 1.0 (left origin)
    public var y: CGFloat // 0.0 ~ 1.0 (top origin)
    public var width: CGFloat // 0.0 ~ 1.0
    public var height: CGFloat // 0.0 ~ 1.0

    public init(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        self.x = max(0.0, min(0.95, x))
        self.y = max(0.0, min(0.95, y))
        self.width = max(0.04, min(1.0 - self.x, width))
        self.height = max(0.04, min(1.0 - self.y, height))
    }
}

public struct StageElement: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var kind: StageElementKind
    public var rect: StageNormalizedRect
    public var label: String
    public var fontSize: CGFloat
    public var fontColorHex: String
    public var backgroundColorHex: String
    public var borderColorHex: String
    public var borderWidth: CGFloat
    public var textAlignment: SlideTextAlignment
    public var targetKey: String
    public var isVisible: Bool

    public init(
        id: UUID = UUID(),
        kind: StageElementKind,
        rect: StageNormalizedRect,
        label: String? = nil,
        fontSize: CGFloat = 32.0,
        fontColorHex: String = "#FFFFFF",
        backgroundColorHex: String = "#1A1A1A",
        borderColorHex: String = "#EAA822",
        borderWidth: CGFloat = 1.5,
        textAlignment: SlideTextAlignment = .center,
        targetKey: String = "lyrics",
        isVisible: Bool = true
    ) {
        self.id = id
        self.kind = kind
        self.rect = rect
        self.label = label ?? kind.defaultLabel
        self.fontSize = fontSize
        self.fontColorHex = fontColorHex
        self.backgroundColorHex = backgroundColorHex
        self.borderColorHex = borderColorHex
        self.borderWidth = borderWidth
        self.textAlignment = textAlignment
        self.targetKey = targetKey
        self.isVisible = isVisible
    }
}

public struct StageLayoutConfig: Codable, Sendable, Equatable {
    public var style: StageLayoutStyle = .standard
    public var showSlideTextOnly: Bool = false
    public var textOnlyFontSize: CGFloat = 40.0
    public var showClock: Bool = true
    public var showTimer: Bool = true
    public var showSlideCounter: Bool = true
    public var showCurrentSlidePreview: Bool = true
    public var showNextSlidePreview: Bool = true
    public var showPresenterNotes: Bool = true
    public var notesFontSize: CGFloat = 24.0

    // Primary Specific Named Element Extraction (e.g. text box named "lyrics")
    public var showNamedElementBox: Bool = false
    public var targetNamedElement: String = "lyrics"
    public var customLabel: String = "STAGE CUE"
    public var namedElementFontSize: CGFloat = 30.0

    // Optional Secondary Named Element Extraction (e.g. "speaker", "subtitle", "lyrics")
    public var showSecondaryNamedElementBox: Bool = false
    public var secondaryTargetNamedElement: String = "subtitle"
    public var secondaryCustomLabel: String = "SUB CUE"

    public var showStageAlert: Bool = true
    public var colorTheme: StageColorTheme = .amber
    public var elements: [StageElement] = []

    public init(
        style: StageLayoutStyle = .standard,
        showSlideTextOnly: Bool = false,
        textOnlyFontSize: CGFloat = 40.0,
        showClock: Bool = true,
        showTimer: Bool = true,
        showSlideCounter: Bool = true,
        showCurrentSlidePreview: Bool = true,
        showNextSlidePreview: Bool = true,
        showPresenterNotes: Bool = true,
        notesFontSize: CGFloat = 24.0,
        showNamedElementBox: Bool = false,
        targetNamedElement: String = "lyrics",
        customLabel: String = "STAGE CUE",
        namedElementFontSize: CGFloat = 30.0,
        showSecondaryNamedElementBox: Bool = false,
        secondaryTargetNamedElement: String = "subtitle",
        secondaryCustomLabel: String = "SUB CUE",
        showStageAlert: Bool = true,
        colorTheme: StageColorTheme = .amber,
        elements: [StageElement] = []
    ) {
        self.style = style
        self.showSlideTextOnly = showSlideTextOnly
        self.textOnlyFontSize = textOnlyFontSize
        self.showClock = showClock
        self.showTimer = showTimer
        self.showSlideCounter = showSlideCounter
        self.showCurrentSlidePreview = showCurrentSlidePreview
        self.showNextSlidePreview = showNextSlidePreview
        self.showPresenterNotes = showPresenterNotes
        self.notesFontSize = notesFontSize
        self.showNamedElementBox = showNamedElementBox
        self.targetNamedElement = targetNamedElement
        self.customLabel = customLabel
        self.namedElementFontSize = namedElementFontSize
        self.showSecondaryNamedElementBox = showSecondaryNamedElementBox
        self.secondaryTargetNamedElement = secondaryTargetNamedElement
        self.secondaryCustomLabel = secondaryCustomLabel
        self.showStageAlert = showStageAlert
        self.colorTheme = colorTheme
        self.elements = elements.isEmpty ? Self.defaultElements(for: style, colorTheme: colorTheme) : elements
    }

    public mutating func addElement(kind: StageElementKind) {
        let accentHex = colorTheme == .amber ? "#EAA822" : (colorTheme == .cyan ? "#00E5FF" : (colorTheme == .emerald ? "#00E676" : "#FFFFFF"))
        let newElem = StageElement(
            kind: kind,
            rect: StageNormalizedRect(x: 0.1, y: 0.1, width: 0.4, height: 0.3),
            label: kind.defaultLabel,
            fontSize: kind == .currentSlideText ? 42.0 : (kind == .clock || kind == .timer ? 28.0 : 20.0),
            fontColorHex: "#FFFFFF",
            backgroundColorHex: "#141414",
            borderColorHex: accentHex,
            borderWidth: 1.5,
            textAlignment: .center
        )
        elements.append(newElem)
    }

    public mutating func removeElement(id: UUID) {
        elements.removeAll(where: { $0.id == id })
    }

    public mutating func updateElement(_ element: StageElement) {
        if let idx = elements.firstIndex(where: { $0.id == element.id }) {
            elements[idx] = element
        }
    }

    public static func defaultElements(for style: StageLayoutStyle, colorTheme: StageColorTheme = .amber) -> [StageElement] {
        let accentHex = colorTheme == .amber ? "#EAA822" : (colorTheme == .cyan ? "#00E5FF" : (colorTheme == .emerald ? "#00E676" : "#FFFFFF"))

        switch style {
        case .worshipLyricsFocus:
            return [
                StageElement(
                    kind: .clock,
                    rect: StageNormalizedRect(x: 0.02, y: 0.02, width: 0.22, height: 0.09),
                    label: "CLOCK",
                    fontSize: 26,
                    fontColorHex: "#FFFFFF",
                    backgroundColorHex: "#0D0D0D",
                    borderColorHex: "#333333",
                    borderWidth: 1.0,
                    textAlignment: .left
                ),
                StageElement(
                    kind: .timer,
                    rect: StageNormalizedRect(x: 0.60, y: 0.02, width: 0.20, height: 0.09),
                    label: "TIMER",
                    fontSize: 26,
                    fontColorHex: "#00E676",
                    backgroundColorHex: "#0D0D0D",
                    borderColorHex: "#333333",
                    borderWidth: 1.0,
                    textAlignment: .right
                ),
                StageElement(
                    kind: .slideCounter,
                    rect: StageNormalizedRect(x: 0.82, y: 0.02, width: 0.16, height: 0.09),
                    label: "SLIDE",
                    fontSize: 26,
                    fontColorHex: "#00E5FF",
                    backgroundColorHex: "#0D0D0D",
                    borderColorHex: "#333333",
                    borderWidth: 1.0,
                    textAlignment: .right
                ),
                StageElement(
                    kind: .currentSlideText,
                    rect: StageNormalizedRect(x: 0.02, y: 0.13, width: 0.96, height: 0.66),
                    label: "CURRENT LYRICS",
                    fontSize: 48,
                    fontColorHex: "#FFFFFF",
                    backgroundColorHex: "#0A0A0A",
                    borderColorHex: accentHex,
                    borderWidth: 2.0,
                    textAlignment: .center
                ),
                StageElement(
                    kind: .nextSlideText,
                    rect: StageNormalizedRect(x: 0.02, y: 0.81, width: 0.96, height: 0.17),
                    label: "NEXT",
                    fontSize: 28,
                    fontColorHex: "#00E5FF",
                    backgroundColorHex: "#0A1218",
                    borderColorHex: "#00E5FF",
                    borderWidth: 1.5,
                    textAlignment: .left
                )
            ]

        case .standard:
            return [
                StageElement(
                    kind: .clock,
                    rect: StageNormalizedRect(x: 0.02, y: 0.02, width: 0.24, height: 0.09),
                    label: "CLOCK",
                    fontSize: 24,
                    textAlignment: .left
                ),
                StageElement(
                    kind: .timer,
                    rect: StageNormalizedRect(x: 0.60, y: 0.02, width: 0.20, height: 0.09),
                    label: "TIMER",
                    fontSize: 24,
                    textAlignment: .right
                ),
                StageElement(
                    kind: .slideCounter,
                    rect: StageNormalizedRect(x: 0.82, y: 0.02, width: 0.16, height: 0.09),
                    label: "SLIDE",
                    fontSize: 24,
                    textAlignment: .right
                ),
                StageElement(
                    kind: .currentSlideVisual,
                    rect: StageNormalizedRect(x: 0.02, y: 0.13, width: 0.47, height: 0.48),
                    label: "CURRENT SLIDE",
                    borderColorHex: "#FF453A",
                    borderWidth: 2.0
                ),
                StageElement(
                    kind: .nextSlideVisual,
                    rect: StageNormalizedRect(x: 0.51, y: 0.13, width: 0.47, height: 0.48),
                    label: "UPCOMING SLIDE",
                    borderColorHex: "#00E5FF",
                    borderWidth: 1.5
                ),
                StageElement(
                    kind: .presenterNotes,
                    rect: StageNormalizedRect(x: 0.02, y: 0.63, width: 0.96, height: 0.35),
                    label: "PRESENTER NOTES",
                    fontSize: 22,
                    borderColorHex: accentHex,
                    textAlignment: .left
                )
            ]

        case .namedCueFocus:
            return [
                StageElement(
                    kind: .clock,
                    rect: StageNormalizedRect(x: 0.02, y: 0.02, width: 0.24, height: 0.09),
                    label: "CLOCK",
                    fontSize: 24,
                    textAlignment: .left
                ),
                StageElement(
                    kind: .slideCounter,
                    rect: StageNormalizedRect(x: 0.82, y: 0.02, width: 0.16, height: 0.09),
                    label: "SLIDE",
                    fontSize: 24,
                    textAlignment: .right
                ),
                StageElement(
                    kind: .namedElement,
                    rect: StageNormalizedRect(x: 0.02, y: 0.13, width: 0.96, height: 0.52),
                    label: "LYRICS / CUE",
                    fontSize: 44,
                    borderColorHex: "#00E5FF",
                    borderWidth: 2.0,
                    textAlignment: .center,
                    targetKey: "lyrics"
                ),
                StageElement(
                    kind: .currentSlideVisual,
                    rect: StageNormalizedRect(x: 0.02, y: 0.67, width: 0.47, height: 0.31),
                    label: "CURRENT SLIDE",
                    borderColorHex: "#FF453A"
                ),
                StageElement(
                    kind: .nextSlideVisual,
                    rect: StageNormalizedRect(x: 0.51, y: 0.67, width: 0.47, height: 0.31),
                    label: "NEXT SLIDE",
                    borderColorHex: "#00E5FF"
                )
            ]

        case .notesFocus:
            return [
                StageElement(
                    kind: .clock,
                    rect: StageNormalizedRect(x: 0.02, y: 0.02, width: 0.24, height: 0.09),
                    label: "CLOCK",
                    fontSize: 24,
                    textAlignment: .left
                ),
                StageElement(
                    kind: .timer,
                    rect: StageNormalizedRect(x: 0.74, y: 0.02, width: 0.24, height: 0.09),
                    label: "TIMER",
                    fontSize: 24,
                    textAlignment: .right
                ),
                StageElement(
                    kind: .currentSlideVisual,
                    rect: StageNormalizedRect(x: 0.02, y: 0.13, width: 0.36, height: 0.40),
                    label: "CURRENT SLIDE",
                    borderColorHex: "#FF453A"
                ),
                StageElement(
                    kind: .nextSlideVisual,
                    rect: StageNormalizedRect(x: 0.02, y: 0.55, width: 0.36, height: 0.40),
                    label: "NEXT SLIDE",
                    borderColorHex: "#00E5FF"
                ),
                StageElement(
                    kind: .presenterNotes,
                    rect: StageNormalizedRect(x: 0.40, y: 0.13, width: 0.58, height: 0.82),
                    label: "SPEAKER NOTES",
                    fontSize: 28,
                    borderColorHex: "#00E676",
                    borderWidth: 2.0,
                    textAlignment: .left
                )
            ]

        case .dualSlidesLarge:
            return [
                StageElement(
                    kind: .clock,
                    rect: StageNormalizedRect(x: 0.02, y: 0.02, width: 0.24, height: 0.08),
                    label: "CLOCK",
                    fontSize: 24,
                    textAlignment: .left
                ),
                StageElement(
                    kind: .slideCounter,
                    rect: StageNormalizedRect(x: 0.82, y: 0.02, width: 0.16, height: 0.08),
                    label: "SLIDE",
                    fontSize: 24,
                    textAlignment: .right
                ),
                StageElement(
                    kind: .currentSlideVisual,
                    rect: StageNormalizedRect(x: 0.02, y: 0.12, width: 0.47, height: 0.84),
                    label: "CURRENT SLIDE (LIVE)",
                    borderColorHex: "#FF453A",
                    borderWidth: 2.5
                ),
                StageElement(
                    kind: .nextSlideVisual,
                    rect: StageNormalizedRect(x: 0.51, y: 0.12, width: 0.47, height: 0.84),
                    label: "UPCOMING SLIDE",
                    borderColorHex: "#00E5FF",
                    borderWidth: 2.0
                )
            ]

        case .custom:
            return [
                StageElement(
                    kind: .currentSlideText,
                    rect: StageNormalizedRect(x: 0.05, y: 0.1, width: 0.90, height: 0.70),
                    label: "SLIDE TEXT",
                    fontSize: 40,
                    borderColorHex: accentHex,
                    textAlignment: .center
                ),
                StageElement(
                    kind: .clock,
                    rect: StageNormalizedRect(x: 0.05, y: 0.83, width: 0.25, height: 0.12),
                    label: "CLOCK",
                    fontSize: 24,
                    textAlignment: .left
                ),
                StageElement(
                    kind: .timer,
                    rect: StageNormalizedRect(x: 0.70, y: 0.83, width: 0.25, height: 0.12),
                    label: "TIMER",
                    fontSize: 24,
                    textAlignment: .right
                )
            ]
        }
    }
}

public struct StageLayoutPreset: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var name: String
    public var iconName: String
    public var config: StageLayoutConfig

    public init(
        id: UUID = UUID(),
        name: String,
        iconName: String = "rectangle.3.group.fill",
        config: StageLayoutConfig
    ) {
        self.id = id
        self.name = name
        self.iconName = iconName
        self.config = config
    }

    public static let presetStandardID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    public static let presetLyricsID = UUID(uuidString: "10000000-0000-0000-0000-000000000005")!
    public static let presetNamedCueID = UUID(uuidString: "10000000-0000-0000-0000-000000000002")!
    public static let presetNotesFocusID = UUID(uuidString: "10000000-0000-0000-0000-000000000003")!
    public static let presetDualSlidesID = UUID(uuidString: "10000000-0000-0000-0000-000000000004")!

    public static let defaultPresets: [StageLayoutPreset] = [
        StageLayoutPreset(
            id: presetLyricsID,
            name: "Worship Lyrics (Text Only)",
            iconName: "music.note.list",
            config: StageLayoutConfig(
                style: .worshipLyricsFocus,
                showSlideTextOnly: true,
                textOnlyFontSize: 44.0,
                showClock: true,
                showTimer: true,
                showSlideCounter: true,
                showCurrentSlidePreview: true,
                showNextSlidePreview: true,
                showPresenterNotes: false,
                notesFontSize: 22.0,
                showNamedElementBox: false,
                colorTheme: .amber
            )
        ),
        StageLayoutPreset(
            id: presetStandardID,
            name: "Standard Stage",
            iconName: "rectangle.3.group.fill",
            config: StageLayoutConfig(
                style: .standard,
                showSlideTextOnly: false,
                showClock: true,
                showTimer: true,
                showSlideCounter: true,
                showCurrentSlidePreview: true,
                showNextSlidePreview: true,
                showPresenterNotes: true,
                notesFontSize: 22.0,
                showNamedElementBox: false,
                targetNamedElement: "lyrics",
                customLabel: "STAGE CUE",
                namedElementFontSize: 28.0,
                colorTheme: .amber
            )
        ),
        StageLayoutPreset(
            id: presetNamedCueID,
            name: "Named Cue Focus",
            iconName: "text.bubble.fill",
            config: StageLayoutConfig(
                style: .namedCueFocus,
                showClock: true,
                showTimer: true,
                showSlideCounter: true,
                showCurrentSlidePreview: true,
                showNextSlidePreview: true,
                showPresenterNotes: false,
                notesFontSize: 22.0,
                showNamedElementBox: true,
                targetNamedElement: "lyrics",
                customLabel: "LYRICS / CUE",
                namedElementFontSize: 42.0,
                showSecondaryNamedElementBox: true,
                secondaryTargetNamedElement: "title",
                secondaryCustomLabel: "SECTION",
                colorTheme: .cyan
            )
        ),
        StageLayoutPreset(
            id: presetNotesFocusID,
            name: "Speaker Notes Focus",
            iconName: "doc.text.fill",
            config: StageLayoutConfig(
                style: .notesFocus,
                showClock: true,
                showTimer: true,
                showSlideCounter: true,
                showCurrentSlidePreview: true,
                showNextSlidePreview: false,
                showPresenterNotes: true,
                notesFontSize: 32.0,
                showNamedElementBox: true,
                targetNamedElement: "title",
                customLabel: "SERMON TOPIC",
                namedElementFontSize: 26.0,
                colorTheme: .emerald
            )
        ),
        StageLayoutPreset(
            id: presetDualSlidesID,
            name: "Dual Slides Large",
            iconName: "rectangle.split.2x1.fill",
            config: StageLayoutConfig(
                style: .dualSlidesLarge,
                showClock: true,
                showTimer: true,
                showSlideCounter: true,
                showCurrentSlidePreview: true,
                showNextSlidePreview: true,
                showPresenterNotes: false,
                showNamedElementBox: false,
                colorTheme: .monochrome
            )
        )
    ]
}
