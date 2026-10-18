import AppKit
import CoreGraphics

public struct SampleDeckBuilder {
    @MainActor
    public static func buildDemoDeck() -> [SlideItem] {
        let slideSpecs: [(title: String, subtitle: String, bgStart: NSColor, bgEnd: NSColor, note: String, namedElements: [String: String])] = [
            (
                "PowerPresenter 1.0",
                "High-Performance Native Broadcast Engine for macOS",
                NSColor(red: 0.08, green: 0.10, blue: 0.18, alpha: 1.0),
                NSColor(red: 0.02, green: 0.03, blue: 0.08, alpha: 1.0),
                "Welcome to the production demo. Test spacebar to advance, Left Arrow to reverse, and Cmd+B for blackout.",
                [
                    "title": "PowerPresenter 1.0",
                    "subtitle": "High-Performance Native Broadcast Engine for macOS",
                    "something": "Opening Cue: Standby stage lights and begin intro music",
                    "speaker": "Executive Producer",
                    "topic": "Welcome Address"
                ]
            ),
            (
                "Zero-Latency Architecture",
                "Direct in-memory CATransaction synchronization across displays (< 0.2ms)",
                NSColor(red: 0.12, green: 0.05, blue: 0.22, alpha: 1.0),
                NSColor(red: 0.04, green: 0.01, blue: 0.10, alpha: 1.0),
                "Explain the elimination of IPC serialization overhead compared to web-based Electron wrappers.",
                [
                    "title": "Zero-Latency Architecture",
                    "subtitle": "Direct in-memory CATransaction synchronization across displays (< 0.2ms)",
                    "something": "Technical Cue: Emphasize sub-millisecond blackout benchmarks",
                    "speaker": "System Architect",
                    "topic": "Core Architecture"
                ]
            ),
            (
                "Hardware Media Pipeline",
                "Apple Silicon VideoToolbox decoding directly to Metal/AVPlayerLayer",
                NSColor(red: 0.03, green: 0.15, blue: 0.15, alpha: 1.0),
                NSColor(red: 0.01, green: 0.05, blue: 0.06, alpha: 1.0),
                "Emphasize ProRes & HEVC 10-bit hardware offload with zero dropped frames on live projectors.",
                [
                    "title": "Hardware Media Pipeline",
                    "subtitle": "Apple Silicon VideoToolbox decoding directly to Metal/AVPlayerLayer",
                    "something": "Media Cue: Video roll ready on next transition",
                    "speaker": "Video Director",
                    "topic": "Hardware Acceleration"
                ]
            ),
            (
                "Production Transitions",
                "CoreAnimation Crossfade, Push Left/Right, and Cinematic Zoom",
                NSColor(red: 0.18, green: 0.08, blue: 0.04, alpha: 1.0),
                NSColor(red: 0.06, green: 0.02, blue: 0.01, alpha: 1.0),
                "Switch transition modes in the top toolbar to demo real-time hardware compositing curves.",
                [
                    "title": "Production Transitions",
                    "subtitle": "CoreAnimation Crossfade, Push Left/Right, and Cinematic Zoom",
                    "something": "Graphics Cue: Demonstration of Push Left and Zoom effects",
                    "speaker": "Stage Manager",
                    "topic": "Visual FX"
                ]
            ),
            (
                "Emergency Safety Guards",
                "Instant Blackout (Cmd+B) & Clear Media (Cmd+M) with VSync Lock",
                NSColor(red: 0.18, green: 0.02, blue: 0.05, alpha: 1.0),
                NSColor(red: 0.06, green: 0.00, blue: 0.01, alpha: 1.0),
                "Demo the blackout button. Show that the overlay layer is on the top-most zPosition with zero animation delay.",
                [
                    "title": "Emergency Safety Guards",
                    "subtitle": "Instant Blackout (Cmd+B) & Clear Media (Cmd+M) with VSync Lock",
                    "something": "Safety Cue: Reassure client about zero broadcast downtime",
                    "speaker": "Technical Director",
                    "topic": "Fail-Safe Redundancy"
                ]
            ),
            (
                "Ready for Live Production",
                "Multi-Display detection with zero UI on external projectors",
                NSColor(red: 0.05, green: 0.14, blue: 0.08, alpha: 1.0),
                NSColor(red: 0.01, green: 0.05, blue: 0.02, alpha: 1.0),
                "Conclusion slide. Open external screen or auxiliary viewer to see audience view mirror.",
                [
                    "title": "Ready for Live Production",
                    "subtitle": "Multi-Display detection with zero UI on external projectors",
                    "something": "Closing Cue: Direct audience to Q&A microphones",
                    "speaker": "Host",
                    "topic": "Summary & Q&A"
                ]
            )
        ]

        return slideSpecs.enumerated().map { index, spec in
            let image = renderSlideImage(
                index: index + 1,
                total: slideSpecs.count,
                title: spec.title,
                subtitle: spec.subtitle,
                bgStart: spec.bgStart,
                bgEnd: spec.bgEnd
            )
            let presetID: UUID?
            switch index {
            case 0: presetID = StageLayoutPreset.presetStandardID
            case 2: presetID = StageLayoutPreset.presetNamedCueID
            case 4: presetID = StageLayoutPreset.presetNotesFocusID
            default: presetID = nil
            }

            let elements: [SlideElement] = [
                SlideElement(
                    kind: .text,
                    name: "title",
                    text: spec.title,
                    normalizedRect: CGRect(x: 0.08, y: 0.22, width: 0.84, height: 0.22),
                    fontSizePt: 48,
                    isBold: true,
                    textColorHex: "FFFFFF",
                    alignment: .left,
                    zOrder: 10
                ),
                SlideElement(
                    kind: .text,
                    name: "subtitle",
                    text: spec.subtitle,
                    normalizedRect: CGRect(x: 0.08, y: 0.46, width: 0.84, height: 0.18),
                    fontSizePt: 26,
                    isBold: false,
                    textColorHex: "DCE4F2",
                    alignment: .left,
                    zOrder: 20
                ),
                SlideElement(
                    kind: .text,
                    name: "something",
                    text: spec.namedElements["something"] ?? "",
                    normalizedRect: CGRect(x: 0.08, y: 0.72, width: 0.84, height: 0.14),
                    fontSizePt: 20,
                    isBold: true,
                    textColorHex: "FFD60A",
                    alignment: .left,
                    zOrder: 30
                )
            ]

            return SlideItem(
                index: index,
                title: spec.title,
                visualRepresentation: image,
                mediaURL: nil,
                notes: spec.note,
                durationHint: 60.0,
                namedElements: spec.namedElements,
                elements: elements,
                background: SlideBackground(colorHex: "141A2E", gradientEndHex: "050814"),
                stageLayoutPresetID: presetID
            )
        }
    }

    private static func renderSlideImage(
        index: Int,
        total: Int,
        title: String,
        subtitle: String,
        bgStart: NSColor,
        bgEnd: NSColor
    ) -> CGImage? {
        let width: CGFloat = 1920
        let height: CGFloat = 1080

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: Int(width),
            height: Int(height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // 1. Draw Linear Gradient Background
        let colors = [bgStart.cgColor, bgEnd.cgColor] as CFArray
        let locations: [CGFloat] = [0.0, 1.0]
        if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations) {
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: height),
                end: CGPoint(x: width, y: 0),
                options: []
            )
        }

        // 2. Draw Decorative Accent Lines / Glow
        context.saveGState()
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.12).cgColor)
        context.setLineWidth(3)
        context.stroke(CGRect(x: 80, y: 80, width: width - 160, height: height - 160))
        
        // Corner Accent Bracket
        context.setStrokeColor(NSColor.systemCyan.withAlphaComponent(0.6).cgColor)
        context.setLineWidth(6)
        context.move(to: CGPoint(x: 80, y: height - 160))
        context.addLine(to: CGPoint(x: 80, y: height - 100))
        context.addLine(to: CGPoint(x: 140, y: height - 100))
        context.strokePath()
        context.restoreGState()

        // 3. Draw Text via NSGraphicsContext bridge
        let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext

        // Slide Index Badge
        let badgeText = "SLIDE \(index) / \(total)"
        let badgeAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 28, weight: .bold),
            .foregroundColor: NSColor.systemCyan
        ]
        badgeText.draw(at: NSPoint(x: 120, y: height - 160), withAttributes: badgeAttrs)

        // Main Title
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 76, weight: .heavy),
            .foregroundColor: NSColor.white
        ]
        let titleRect = NSRect(x: 120, y: height - 420, width: width - 240, height: 200)
        title.draw(in: titleRect, withAttributes: titleAttrs)

        // Subtitle / Body
        let subAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 36, weight: .regular),
            .foregroundColor: NSColor.white.withAlphaComponent(0.75)
        ]
        let subRect = NSRect(x: 120, y: height - 580, width: width - 240, height: 140)
        subtitle.draw(in: subRect, withAttributes: subAttrs)

        // Broadcast Brand Footnote
        let brandAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 22, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.35)
        ]
        "POWERPRESENTER ENGINE • 60 FPS BROADCAST CANVAS • APPLE SILICON NATIVE"
            .draw(at: NSPoint(x: 120, y: 120), withAttributes: brandAttrs)

        NSGraphicsContext.restoreGraphicsState()

        return context.makeImage()
    }
}
