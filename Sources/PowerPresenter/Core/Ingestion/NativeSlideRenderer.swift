import AppKit
import CoreGraphics
import CoreImage

public final class NativeSlideRenderer: Sendable {
    public static let shared = NativeSlideRenderer()

    public let canvasWidth: CGFloat = 1920
    public let canvasHeight: CGFloat = 1080

    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    public init() {}

    public func renderSlide(
        index: Int,
        total: Int,
        title: String,
        elements: [SlideElement],
        background: SlideBackground,
        namedElements: [String: String],
        fallbackMediaURL: URL? = nil,
        baseImage: CGImage? = nil
    ) -> CGImage? {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(canvasWidth),
            pixelsHigh: Int(canvasHeight),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }

        guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
            return nil
        }
        NSGraphicsContext.current = context
        let cg = context.cgContext

        let fullRect = NSRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight)

        // 1. Render Slide Background
        var hasImageBackdrop = false
        var isDarkBackground = false

        if let base = baseImage {
            let baseNs = NSImage(cgImage: base, size: NSSize(width: canvasWidth, height: canvasHeight))
            baseNs.draw(in: fullRect, from: .zero, operation: .copy, fraction: 1.0)
            hasImageBackdrop = true
        } else if let bgImgURL = background.backgroundImageURL,
           let nsImg = NSImage(contentsOf: bgImgURL) {
            nsImg.draw(in: fullRect, from: .zero, operation: .sourceOver, fraction: 1.0)
            hasImageBackdrop = true
        } else if let startHex = background.colorHex,
                  let endHex = background.gradientEndHex,
                  let startColor = NSColor(hex: startHex),
                  let endColor = NSColor(hex: endHex) {
            if let gradient = NSGradient(starting: startColor, ending: endColor) {
                gradient.draw(in: fullRect, angle: -90)
            }
            isDarkBackground = startColor.isDarkColor
        } else if let solidHex = background.colorHex,
                  let solidColor = NSColor(hex: solidHex) {
            solidColor.setFill()
            fullRect.fill()
            isDarkBackground = solidColor.isDarkColor
        } else {
            NSColor.white.setFill()
            fullRect.fill()
            isDarkBackground = false
        }

        // Check if we have any image elements; if not, check fallbackMediaURL
        let imageElements = elements.filter { $0.kind == .image }
        if !hasImageBackdrop && imageElements.isEmpty,
           let mediaURL = fallbackMediaURL,
           let nsImg = NSImage(contentsOf: mediaURL) {
            nsImg.draw(in: fullRect, from: .zero, operation: .sourceOver, fraction: 1.0)
            hasImageBackdrop = true
        }

        // 2. Render Elements in exact back-to-front zOrder
        let sortedElements = elements.sorted { $0.zOrder < $1.zOrder }

        if !sortedElements.isEmpty {
            for element in sortedElements {
                let targetRect = convertNormalizedRect(element.normalizedRect)

                switch element.kind {
                case .image:
                    // When baseImage is provided (PowerPoint export), all pictures and master graphics
                    // are already present with 100% visual fidelity. Do not redraw them over baseImage!
                    if baseImage == nil {
                        drawImageElement(element, in: targetRect, cg: cg)
                        if element.normalizedRect.width > 0.7 && element.normalizedRect.height > 0.7 {
                            hasImageBackdrop = true
                        }
                    }

                case .shape:
                    // When baseImage is provided, all vector shapes are already present.
                    if baseImage == nil {
                        drawShapeBox(element, in: targetRect, cg: cg)
                    }

                case .text:
                    if baseImage != nil {
                        // Clear the old text underneath on baseImage before drawing new text
                        clearTextBoxBackground(
                            for: element,
                            in: targetRect,
                            background: background,
                            baseImage: baseImage,
                            cg: cg
                        )
                    } else {
                        drawShapeBox(element, in: targetRect, cg: cg)
                    }

                    guard !element.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        continue
                    }

                    drawRichTextElement(
                        element,
                        in: targetRect,
                        isDarkBackground: isDarkBackground
                    )
                }
            }
        } else if !hasImageBackdrop {
            let mainRect = NSRect(x: 120, y: 240, width: canvasWidth - 240, height: canvasHeight - 480)
            let fallbackEl = SlideElement(
                kind: .text,
                name: "Title",
                text: title,
                fontSizePt: 44,
                isBold: true,
                textColorHex: isDarkBackground ? "FFFFFF" : "111111",
                alignment: .center,
                verticalAnchor: .center
            )
            drawRichTextElement(fallbackEl, in: mainRect, isDarkBackground: isDarkBackground)
        }

        return rep.cgImage
    }

    // MARK: - Image Element Rendering (with Crop, Duotone & Opacity)

    private func drawImageElement(_ element: SlideElement, in targetRect: NSRect, cg: CGContext) {
        guard let imgURL = element.imageURL,
              let nsImg = NSImage(contentsOf: imgURL),
              var cgImg = nsImg.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return
        }

        // 1. Apply OpenXML <a:srcRect> cropping if specified
        if let crop = element.imageCropInsets {
            let w = CGFloat(cgImg.width)
            let h = CGFloat(cgImg.height)
            let cropX = max(0, min(w - 1, crop.origin.x * w))
            let cropY = max(0, min(h - 1, crop.origin.y * h))
            let cropW = max(1, (1.0 - crop.origin.x - crop.size.width) * w)
            let cropH = max(1, (1.0 - crop.origin.y - crop.size.height) * h)
            let cropRect = CGRect(x: cropX, y: cropY, width: cropW, height: cropH)
            if let cropped = cgImg.cropping(to: cropRect) {
                cgImg = cropped
            }
        }

        // 2. Apply OpenXML <a:duotone> filter if specified
        if let hex1 = element.duotoneColor1Hex,
           let hex2 = element.duotoneColor2Hex,
           let c1 = NSColor(hex: hex1),
           let c2 = NSColor(hex: hex2),
           let filtered = applyDuotone(to: cgImg, color1: c1, color2: c2) {
            cgImg = filtered
        }

        // 3. Draw with opacity & proportional aspect ratio
        var drawRect = targetRect
        if !element.stretchFill && cgImg.width > 0 && cgImg.height > 0 {
            let imgAspect = CGFloat(cgImg.width) / CGFloat(cgImg.height)
            let rectAspect = targetRect.width / max(1, targetRect.height)
            if imgAspect > rectAspect {
                let fitH = targetRect.width / imgAspect
                drawRect = NSRect(
                    x: targetRect.origin.x,
                    y: targetRect.origin.y + (targetRect.height - fitH) * 0.5,
                    width: targetRect.width,
                    height: fitH
                )
            } else {
                let fitW = targetRect.height * imgAspect
                drawRect = NSRect(
                    x: targetRect.origin.x + (targetRect.width - fitW) * 0.5,
                    y: targetRect.origin.y,
                    width: fitW,
                    height: targetRect.height
                )
            }
        }

        cg.saveGState()
        cg.setAlpha(max(0.0, min(1.0, element.imageOpacity)))
        cg.interpolationQuality = .high
        cg.draw(cgImg, in: drawRect)
        cg.restoreGState()
    }

    private func applyDuotone(to cgImage: CGImage, color1: NSColor, color2: NSColor) -> CGImage? {
        let ciImage = CIImage(cgImage: cgImage)
        guard let filter = CIFilter(name: "CIFalseColor") else { return nil }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(CIColor(color: color1), forKey: "inputColor0")
        filter.setValue(CIColor(color: color2), forKey: "inputColor1")
        guard let output = filter.outputImage else { return nil }
        return ciContext.createCGImage(output, from: ciImage.extent)
    }

    // MARK: - Shape Box (Fill + Border Stroke)

    private func drawShapeBox(_ element: SlideElement, in targetRect: NSRect, cg: CGContext) {
        cg.saveGState()
        defer { cg.restoreGState() }

        let path = NSBezierPath(rect: targetRect)

        // Fill
        if let fillStartHex = element.fillColorHex,
           let startColor = NSColor(hex: fillStartHex) {
            if let fillEndHex = element.fillGradientEndHex,
               let endColor = NSColor(hex: fillEndHex),
               let gradient = NSGradient(starting: startColor, ending: endColor) {
                gradient.draw(in: path, angle: -90)
            } else {
                startColor.setFill()
                path.fill()
            }
        }

        // Border / Stroke (<a:ln>)
        if element.strokeWidthPt > 0,
           let strokeHex = element.strokeColorHex,
           let strokeColor = NSColor(hex: strokeHex) {
            let pixelStrokeWidth = max(1.5, element.strokeWidthPt * 2.0)
            let insetRect = targetRect.insetBy(dx: pixelStrokeWidth * 0.5, dy: pixelStrokeWidth * 0.5)
            if let strokeEndHex = element.strokeGradientEndHex,
               let strokeEndColor = NSColor(hex: strokeEndHex),
               let grad = NSGradient(starting: strokeColor, ending: strokeEndColor) {
                // Draw gradient border frame using clip path
                let outerPath = NSBezierPath(rect: targetRect)
                let innerPath = NSBezierPath(rect: targetRect.insetBy(dx: pixelStrokeWidth, dy: pixelStrokeWidth))
                outerPath.append(innerPath.reversed)
                outerPath.windingRule = .evenOdd
                grad.draw(in: outerPath, angle: -45)
            } else {
                let borderPath = NSBezierPath(rect: insetRect)
                borderPath.lineWidth = pixelStrokeWidth
                strokeColor.setStroke()
                borderPath.stroke()
            }
        }
    }

    // MARK: - Smart Text Box Background Clearing (Preserves Original Base Image & Master Layout)

    private func clearTextBoxBackground(
        for element: SlideElement,
        in targetRect: NSRect,
        background: SlideBackground,
        baseImage: CGImage?,
        cg: CGContext
    ) {
        cg.saveGState()
        defer { cg.restoreGState() }

        // Expand clearing rect slightly to eliminate any anti-aliased font halos
        let clearRect = targetRect.insetBy(dx: -3, dy: -2)

        // 1. If element has an explicit shape fill, draw it
        if let fillStartHex = element.fillColorHex,
           let startColor = NSColor(hex: fillStartHex) {
            let path = NSBezierPath(rect: clearRect)
            if let fillEndHex = element.fillGradientEndHex,
               let endColor = NSColor(hex: fillEndHex),
               let gradient = NSGradient(starting: startColor, ending: endColor) {
                gradient.draw(in: path, angle: -90)
            } else {
                startColor.setFill()
                path.fill()
            }
            return
        }

        // 2. If background has a background image, draw the matching slice
        if let bgImgURL = background.backgroundImageURL,
           let bgImg = NSImage(contentsOf: bgImgURL),
           let cgBg = bgImg.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let norm = element.normalizedRect
            let srcW = CGFloat(cgBg.width)
            let srcH = CGFloat(cgBg.height)
            let srcX = max(0, min(srcW - 1, norm.origin.x * srcW))
            let srcY = max(0, min(srcH - 1, norm.origin.y * srcH))
            let srcWidth = max(1, min(srcW - srcX, norm.size.width * srcW))
            let srcHeight = max(1, min(srcH - srcY, norm.size.height * srcH))
            let cropRect = CGRect(x: srcX, y: srcY, width: srcWidth, height: srcHeight)
            if let slice = cgBg.cropping(to: cropRect) {
                let sliceNs = NSImage(cgImage: slice, size: clearRect.size)
                sliceNs.draw(in: clearRect, from: .zero, operation: .copy, fraction: 1.0)
                return
            }
        }

        // 3. If background has a gradient
        if let startHex = background.colorHex,
           let endHex = background.gradientEndHex,
           let startColor = NSColor(hex: startHex),
           let endColor = NSColor(hex: endHex),
           let gradient = NSGradient(starting: startColor, ending: endColor) {
            let fullRect = NSRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight)
            let path = NSBezierPath(rect: clearRect)
            path.addClip()
            gradient.draw(in: fullRect, angle: -90)
            return
        }

        // 4. If background has a solid color
        if let solidHex = background.colorHex,
           let solidColor = NSColor(hex: solidHex) {
            solidColor.setFill()
            clearRect.fill()
            return
        }

        // 5. Default fallback based on dark/light text color
        let isDark = element.textColorHex.flatMap({ NSColor(hex: $0)?.isDarkColor }) == false
        let fallbackColor = isDark ? NSColor(white: 0.08, alpha: 1.0) : NSColor.white
        fallbackColor.setFill()
        clearRect.fill()
    }

    // MARK: - Rich Multi-Run Text Rendering

    private func drawRichTextElement(
        _ element: SlideElement,
        in rect: NSRect,
        isDarkBackground: Bool
    ) {
        // Horizontal padding (PowerPoint default lIns/rIns is 0.1" = 7.2pt = 14.4px)
        let insetRect = rect.insetBy(dx: min(14, rect.width * 0.02), dy: min(6, rect.height * 0.02))
        let targetWidth = max(40, insetRect.width)
        let targetHeight = max(20, insetRect.height)

        var scaleFactor: CGFloat = 1.0
        var attrString = buildAttributedString(for: element, scale: scaleFactor, isDarkBackground: isDarkBackground)

        if element.autoFitText {
            while scaleFactor > 0.45 {
                let bounds = attrString.boundingRect(
                    with: NSSize(width: targetWidth, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading]
                )
                if bounds.height <= targetHeight * 1.06 {
                    break
                }
                scaleFactor -= 0.06
                attrString = buildAttributedString(for: element, scale: scaleFactor, isDarkBackground: isDarkBackground)
            }
        }

        let finalBounds = attrString.boundingRect(
            with: NSSize(width: targetWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )

        let textHeight = max(finalBounds.height + 2, 20)
        let drawY: CGFloat
        switch element.verticalAnchor {
        case .center:
            if textHeight < targetHeight {
                drawY = insetRect.origin.y + (targetHeight - textHeight) * 0.5
            } else {
                drawY = insetRect.origin.y
            }
        case .bottom:
            drawY = insetRect.origin.y
        case .top:
            if textHeight < targetHeight {
                drawY = insetRect.maxY - textHeight
            } else {
                drawY = insetRect.origin.y
            }
        }

        let drawRect = NSRect(
            x: insetRect.origin.x,
            y: drawY,
            width: targetWidth,
            height: textHeight
        )

        attrString.draw(with: drawRect, options: [.usesLineFragmentOrigin, .usesFontLeading])
    }

    private func buildAttributedString(
        for element: SlideElement,
        scale: CGFloat,
        isDarkBackground: Bool
    ) -> NSAttributedString {
        // PowerPoint 16:9 widescreen is 960x540 pt -> 1920x1080 px is exactly 2.0 px/pt
        let ptToPx: CGFloat = 1.92 * scale
        let result = NSMutableAttributedString()

        if !element.paragraphs.isEmpty {
            for (pIdx, paragraph) in element.paragraphs.enumerated() {
                let pStyle = NSMutableParagraphStyle()
                switch paragraph.alignment {
                case .left: pStyle.alignment = .left
                case .center: pStyle.alignment = .center
                case .right: pStyle.alignment = .right
                case .justified: pStyle.alignment = .justified
                }
                pStyle.lineBreakMode = .byWordWrapping
                pStyle.headIndent = paragraph.leftMarginPt * ptToPx
                pStyle.firstLineHeadIndent = max(0, (paragraph.leftMarginPt + paragraph.indentPt) * ptToPx)
                pStyle.lineHeightMultiple = max(0.85, min(1.6, paragraph.lineSpacingMultiplier))
                pStyle.paragraphSpacingBefore = paragraph.spaceBeforePt * ptToPx
                pStyle.paragraphSpacing = max(2.0, paragraph.spaceAfterPt * ptToPx)

                for run in paragraph.runs {
                    let baseFontSize = max(14.0, run.fontSizePt * ptToPx)
                    let actualFontSize = run.baselinePercent != 0 ? baseFontSize * 0.65 : baseFontSize
                    let font = resolveFont(
                        family: run.fontFamily ?? element.fontFamily,
                        size: actualFontSize,
                        isBold: run.isBold,
                        isItalic: run.isItalic
                    )

                    let color = resolveRunColor(
                        hex: run.textColorHex ?? element.textColorHex,
                        gradEndHex: run.gradientEndColorHex ?? element.textGradientEndHex,
                        isDarkBackground: isDarkBackground
                    )

                    var attrs: [NSAttributedString.Key: Any] = [
                        .font: font,
                        .foregroundColor: color,
                        .paragraphStyle: pStyle
                    ]

                    if run.baselinePercent != 0 {
                        attrs[.baselineOffset] = baseFontSize * (run.baselinePercent / 100.0)
                    }

                    result.append(NSAttributedString(string: run.text, attributes: attrs))
                }

                if pIdx < element.paragraphs.count - 1 {
                    result.append(NSAttributedString(string: "\n"))
                }
            }
        } else {
            let pStyle = NSMutableParagraphStyle()
            switch element.alignment {
            case .left: pStyle.alignment = .left
            case .center: pStyle.alignment = .center
            case .right: pStyle.alignment = .right
            case .justified: pStyle.alignment = .justified
            }
            pStyle.lineBreakMode = .byWordWrapping
            pStyle.lineHeightMultiple = 1.08

            let fontSize = max(16.0, element.fontSizePt * ptToPx)
            let font = resolveFont(
                family: element.fontFamily,
                size: fontSize,
                isBold: element.isBold,
                isItalic: false
            )
            let color = resolveRunColor(
                hex: element.textColorHex,
                gradEndHex: element.textGradientEndHex,
                isDarkBackground: isDarkBackground
            )

            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: pStyle
            ]
            result.append(NSAttributedString(string: element.text, attributes: attrs))
        }

        return result
    }

    private func resolveRunColor(hex: String?, gradEndHex: String?, isDarkBackground: Bool) -> NSColor {
        if let startHex = hex, let startColor = NSColor(hex: startHex) {
            if let endHex = gradEndHex, let endColor = NSColor(hex: endHex) {
                return startColor.blended(withFraction: 0.45, of: endColor) ?? startColor
            }
            return startColor
        }
        return isDarkBackground ? .white : NSColor(white: 0.12, alpha: 1.0)
    }

    private func resolveFont(family: String?, size: CGFloat, isBold: Bool, isItalic: Bool) -> NSFont {
        let weight: NSFont.Weight = isBold ? .bold : .regular

        if let rawFamily = family?.trimmingCharacters(in: .whitespacesAndNewlines), !rawFamily.isEmpty {
            let lower = rawFamily.lowercased()
            var candidates: [String] = [rawFamily]

            if lower.contains("나눔바른고딕") || lower.contains("nanumbarungothic") {
                candidates = isBold
                    ? ["NanumBarunGothicBold", "NanumBarunGothic", "AppleSDGothicNeo-Bold"]
                    : ["NanumBarunGothic", "AppleSDGothicNeo-Regular"]
            } else if lower.contains("나눔명조") || lower.contains("nanummyeongjo") || lower.contains("명조") {
                candidates = isBold
                    ? ["NanumMyeongjoExtraBold", "NanumMyeongjoBold", "NanumMyeongjo", "AppleMyungjo"]
                    : ["NanumMyeongjo", "AppleMyungjo"]
            } else if lower.contains("나눔고딕") || lower.contains("nanumgothic") {
                candidates = isBold
                    ? ["NanumGothicExtraBold", "NanumGothicBold", "NanumGothic", "AppleSDGothicNeo-Bold"]
                    : ["NanumGothic", "AppleSDGothicNeo-Regular"]
            } else if lower.contains("맑은 고딕") || lower.contains("malgun") {
                candidates = isBold
                    ? ["MalgunGothicBold", "Malgun Gothic Bold", "Malgun Gothic", "AppleSDGothicNeo-Bold"]
                    : ["MalgunGothic", "Malgun Gothic", "AppleSDGothicNeo-Regular"]
            }

            for name in candidates {
                if let f = NSFont(name: name, size: size) {
                    if isBold {
                        let bolded = NSFontManager.shared.convert(f, toHaveTrait: .boldFontMask)
                        return bolded
                    }
                    return f
                }
            }
        }

        return NSFont.systemFont(ofSize: size, weight: weight)
    }

    private func convertNormalizedRect(_ norm: CGRect) -> NSRect {
        let w = norm.size.width * canvasWidth
        let h = norm.size.height * canvasHeight
        let x = norm.origin.x * canvasWidth
        let y = canvasHeight - (norm.origin.y * canvasHeight) - h
        return NSRect(x: x, y: y, width: w, height: h)
    }
}

public extension NSColor {
    convenience init?(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6, let intVal = UInt64(cleaned, radix: 16) else {
            return nil
        }
        let r = CGFloat((intVal & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((intVal & 0x00FF00) >> 8) / 255.0
        let b = CGFloat(intVal & 0x0000FF) / 255.0
        self.init(srgbRed: r, green: g, blue: b, alpha: 1.0)
    }

    var isDarkColor: Bool {
        guard let rgb = usingColorSpace(.sRGB) else { return true }
        let luminance = 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
        return luminance < 0.45
    }
}
