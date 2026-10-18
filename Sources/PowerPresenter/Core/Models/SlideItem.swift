import Foundation
import CoreGraphics

public enum TransitionType: Hashable, Sendable {
    case cut
    case crossfade(duration: TimeInterval)
    case push(direction: PushDirection, duration: TimeInterval)
    case zoom(scale: CGFloat, duration: TimeInterval)
    
    public var displayName: String {
        switch self {
        case .cut:
            return "Cut (Direct)"
        case .crossfade(let duration):
            return "Crossfade (\(String(format: "%.1f", duration))s)"
        case .push(let direction, let duration):
            return "Push \(direction.rawValue.capitalized) (\(String(format: "%.1f", duration))s)"
        case .zoom(_, let duration):
            return "Zoom In (\(String(format: "%.1f", duration))s)"
        }
    }
}

public enum PushDirection: String, Hashable, Sendable {
    case left
    case right
    case up
    case down
}

public enum SlideElementKind: String, Codable, Sendable {
    case text
    case image
    case shape
}

public enum SlideTextAlignment: String, Codable, Sendable {
    case left
    case center
    case right
    case justified
}

public enum SlideVerticalAnchor: String, Codable, Sendable {
    case top
    case center
    case bottom
}

public struct SlideTextRun: Sendable, Equatable, Codable {
    public var text: String
    public var fontSizePt: CGFloat
    public var isBold: Bool
    public var isItalic: Bool
    public var fontFamily: String?
    public var textColorHex: String?
    public var gradientEndColorHex: String?
    /// OpenXML baseline percentage (e.g. 30.0 for superscript, -25.0 for subscript)
    public var baselinePercent: CGFloat

    public init(
        text: String,
        fontSizePt: CGFloat = 32,
        isBold: Bool = false,
        isItalic: Bool = false,
        fontFamily: String? = nil,
        textColorHex: String? = nil,
        gradientEndColorHex: String? = nil,
        baselinePercent: CGFloat = 0
    ) {
        self.text = text
        self.fontSizePt = fontSizePt
        self.isBold = isBold
        self.isItalic = isItalic
        self.fontFamily = fontFamily
        self.textColorHex = textColorHex
        self.gradientEndColorHex = gradientEndColorHex
        self.baselinePercent = baselinePercent
    }
}

public struct SlideParagraph: Sendable, Equatable, Codable {
    public var runs: [SlideTextRun]
    public var alignment: SlideTextAlignment
    public var leftMarginPt: CGFloat
    public var indentPt: CGFloat
    public var lineSpacingMultiplier: CGFloat
    public var spaceBeforePt: CGFloat
    public var spaceAfterPt: CGFloat

    public init(
        runs: [SlideTextRun] = [],
        alignment: SlideTextAlignment = .left,
        leftMarginPt: CGFloat = 0,
        indentPt: CGFloat = 0,
        lineSpacingMultiplier: CGFloat = 1.1,
        spaceBeforePt: CGFloat = 0,
        spaceAfterPt: CGFloat = 0
    ) {
        self.runs = runs
        self.alignment = alignment
        self.leftMarginPt = leftMarginPt
        self.indentPt = indentPt
        self.lineSpacingMultiplier = lineSpacingMultiplier
        self.spaceBeforePt = spaceBeforePt
        self.spaceAfterPt = spaceAfterPt
    }

    public var plainText: String {
        runs.map(\.text).joined()
    }
}

public struct SlideElement: Identifiable, Sendable, Equatable {
    public var id: UUID
    public var kind: SlideElementKind
    public var name: String
    public var text: String
    public var paragraphs: [SlideParagraph]
    /// Normalized coordinates (0.0 ... 1.0) relative to slide canvas (top-left origin)
    public var normalizedRect: CGRect
    public var fontSizePt: CGFloat
    public var isBold: Bool
    public var fontFamily: String?
    public var textColorHex: String?
    public var textGradientEndHex: String?
    public var fillColorHex: String?
    public var fillGradientEndHex: String?
    public var strokeColorHex: String?
    public var strokeGradientEndHex: String?
    public var strokeWidthPt: CGFloat
    public var alignment: SlideTextAlignment
    public var verticalAnchor: SlideVerticalAnchor
    public var autoFitText: Bool
    public var imageURL: URL?
    /// Normalized crop fractions (left, top, right, bottom in 0.0...1.0) from OpenXML <a:srcRect>
    public var imageCropInsets: CGRect?
    public var imageOpacity: CGFloat
    public var duotoneColor1Hex: String?
    public var duotoneColor2Hex: String?
    public var stretchFill: Bool
    public var zOrder: Int

    public init(
        id: UUID = UUID(),
        kind: SlideElementKind,
        name: String,
        text: String = "",
        paragraphs: [SlideParagraph] = [],
        normalizedRect: CGRect = CGRect(x: 0.08, y: 0.15, width: 0.84, height: 0.7),
        fontSizePt: CGFloat = 36,
        isBold: Bool = false,
        fontFamily: String? = nil,
        textColorHex: String? = nil,
        textGradientEndHex: String? = nil,
        fillColorHex: String? = nil,
        fillGradientEndHex: String? = nil,
        strokeColorHex: String? = nil,
        strokeGradientEndHex: String? = nil,
        strokeWidthPt: CGFloat = 0,
        alignment: SlideTextAlignment = .left,
        verticalAnchor: SlideVerticalAnchor = .top,
        autoFitText: Bool = true,
        imageURL: URL? = nil,
        imageCropInsets: CGRect? = nil,
        imageOpacity: CGFloat = 1.0,
        duotoneColor1Hex: String? = nil,
        duotoneColor2Hex: String? = nil,
        stretchFill: Bool = true,
        zOrder: Int = 0
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.text = text
        self.paragraphs = paragraphs
        self.normalizedRect = normalizedRect
        self.fontSizePt = fontSizePt
        self.isBold = isBold
        self.fontFamily = fontFamily
        self.textColorHex = textColorHex
        self.textGradientEndHex = textGradientEndHex
        self.fillColorHex = fillColorHex
        self.fillGradientEndHex = fillGradientEndHex
        self.strokeColorHex = strokeColorHex
        self.strokeGradientEndHex = strokeGradientEndHex
        self.strokeWidthPt = strokeWidthPt
        self.alignment = alignment
        self.verticalAnchor = verticalAnchor
        self.autoFitText = autoFitText
        self.imageURL = imageURL
        self.imageCropInsets = imageCropInsets
        self.imageOpacity = imageOpacity
        self.duotoneColor1Hex = duotoneColor1Hex
        self.duotoneColor2Hex = duotoneColor2Hex
        self.stretchFill = stretchFill
        self.zOrder = zOrder
    }
}

public struct SlideBackground: Sendable, Equatable {
    public var colorHex: String?
    public var gradientEndHex: String?
    public var backgroundImageURL: URL?

    public init(
        colorHex: String? = nil,
        gradientEndHex: String? = nil,
        backgroundImageURL: URL? = nil
    ) {
        self.colorHex = colorHex
        self.gradientEndHex = gradientEndHex
        self.backgroundImageURL = backgroundImageURL
    }
}

public struct SlideItem: Identifiable, Sendable {
    public let id: UUID
    public var index: Int
    public var title: String
    public var visualRepresentation: CGImage?
    public var mediaURL: URL?
    public var notes: String?
    public var durationHint: TimeInterval?
    /// Key: text box / shape name (e.g. "something", "title", "speaker", "lyrics"), Value: text
    public var namedElements: [String: String]
    /// Structured elements parsed from OpenXML (used for native rendering, Stage text extraction & live editing)
    public var elements: [SlideElement]
    public var background: SlideBackground
    /// Optional Stage Layout Preset Cue assigned to this slide (auto-switches Stage View when triggered)
    public var stageLayoutPresetID: UUID?
    /// Optional MIDI Cue triggered when this slide goes Live (sends Note/CC/PC to external lighting/audio/video gear)
    public var midiCue: MIDICue?
    /// Optional Service Section this slide belongs to (e.g. 찬양, 말씀, 광고)
    public var serviceSectionID: UUID?
    public var serviceSectionName: String?
    public var serviceSectionColorHex: String?

    public init(
        id: UUID = UUID(),
        index: Int,
        title: String,
        visualRepresentation: CGImage?,
        mediaURL: URL? = nil,
        notes: String? = nil,
        durationHint: TimeInterval? = nil,
        namedElements: [String: String] = [:],
        elements: [SlideElement] = [],
        background: SlideBackground = SlideBackground(),
        stageLayoutPresetID: UUID? = nil,
        midiCue: MIDICue? = nil,
        serviceSectionID: UUID? = nil,
        serviceSectionName: String? = nil,
        serviceSectionColorHex: String? = nil
    ) {
        self.id = id
        self.index = index
        self.title = title
        self.visualRepresentation = visualRepresentation
        self.mediaURL = mediaURL
        self.notes = notes
        self.durationHint = durationHint
        self.namedElements = namedElements
        self.elements = elements
        self.background = background
        self.stageLayoutPresetID = stageLayoutPresetID
        self.midiCue = midiCue
        self.serviceSectionID = serviceSectionID
        self.serviceSectionName = serviceSectionName
        self.serviceSectionColorHex = serviceSectionColorHex
    }

    public var hasMedia: Bool {
        mediaURL != nil
    }

    public var isVideoMedia: Bool {
        guard let ext = mediaURL?.pathExtension.lowercased() else { return false }
        return ["mp4", "mov", "m4v"].contains(ext)
    }

    public var isAudioMedia: Bool {
        guard let ext = mediaURL?.pathExtension.lowercased() else { return false }
        return ["mp3", "m4a", "wav", "aac"].contains(ext)
    }

    /// Primary body / worship lyrics text extracted from structured slide elements for Stage Display (Text-Only mode).
    /// Automatically filters out CCLI license footers so worship lyrics and sermon points appear clean on Stage.
    public var primaryStageText: String {
        if let explicitLyrics = namedElements["lyrics"], !explicitLyrics.isEmpty {
            return explicitLyrics
        }
        let textElements = elements.filter { $0.kind == .text && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !textElements.isEmpty else {
            return title
        }

        // Filter out CCLI / copyright boxes when there is another body text box
        let nonCopyrightElements = textElements.filter { el in
            let lower = el.text.lowercased()
            return !lower.contains("ccli license") && !lower.contains("streaming license")
        }

        let candidates = nonCopyrightElements.isEmpty ? textElements : nonCopyrightElements

        // Prefer main body / content placeholders ("내용 개체 틀", "TextBox 581", "TextBox 15") or lower-half lyrics
        if let bodyMatch = candidates.first(where: { el in
            let n = el.name.lowercased()
            return n.contains("내용") || n.contains("body") || n.contains("content") || n.contains("581") || n.contains("15")
        }) {
            return bodyMatch.text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Otherwise combine non-copyright text elements in visual top-to-bottom order
        let sorted = candidates.sorted { $0.normalizedRect.minY < $1.normalizedRect.minY }
        let combined = sorted.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return combined.isEmpty ? title : combined.joined(separator: "\n")
    }

    /// Secondary header / song title / scripture reference for Stage Display
    public var secondaryStageText: String? {
        let textElements = elements.filter { $0.kind == .text && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        // Check if there is a CCLI / Song title block
        if let copyrightEl = textElements.first(where: { $0.text.lowercased().contains("ccli") || $0.text.lowercased().contains("©") }) {
            let firstLine = copyrightEl.text.components(separatedBy: .newlines).first?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let firstLine = firstLine, !firstLine.isEmpty {
                return firstLine
            }
        }
        // Or check for a title element distinct from primaryStageText
        if let titleEl = textElements.first(where: { $0.name.lowercased().contains("제목") || $0.name.lowercased().contains("title") }) {
            let t = titleEl.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty && t != primaryStageText {
                return t.replacingOccurrences(of: "\n", with: " · ")
            }
        }
        return nil
    }

    /// Case-insensitive & whitespace-tolerant lookup for a named element on this slide
    public func extractedValue(for key: String) -> String? {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lower = trimmed.lowercased()
        if ["lyrics", "가사", "본문", "body", "text", "all", "슬라이드 텍스트"].contains(lower) {
            let p = primaryStageText
            return p.isEmpty ? nil : p
        }

        if let exact = namedElements[trimmed], !exact.isEmpty {
            return exact
        }
        if let lowerMatch = namedElements[lower], !lowerMatch.isEmpty {
            return lowerMatch
        }
        for (k, v) in namedElements where k.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == lower && !v.isEmpty {
            return v
        }
        // Also check structured elements (preferring non-CCLI element if multiple share the same name like "내용 개체 틀 2")
        let matchingElements = elements.filter {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == lower && !$0.text.isEmpty
        }
        if let nonCCLI = matchingElements.first(where: { !$0.text.lowercased().contains("ccli license") }) {
            return nonCCLI.text
        }
        if let firstElem = matchingElements.first {
            return firstElem.text
        }
        return nil
    }
}
