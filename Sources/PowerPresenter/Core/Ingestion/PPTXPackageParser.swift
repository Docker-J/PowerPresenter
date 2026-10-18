import Foundation
import CoreGraphics

public struct PPTXSlideMetadata: Sendable {
    public let slideIndex: Int
    public let title: String
    public let notes: String?
    public let namedElements: [String: String]
    public let mediaFiles: [URL]
    public let videoFile: URL?
    public let elements: [SlideElement]
    public let background: SlideBackground
}

private struct GroupTransform {
    var offX: Double
    var offY: Double
    var extW: Double
    var extH: Double
    var chOffX: Double
    var chOffY: Double
    var chExtW: Double
    var chExtH: Double

    func mapRect(_ childRect: CGRect) -> CGRect {
        guard chExtW > 0, chExtH > 0, extW > 0, extH > 0 else { return childRect }
        let scaleX = extW / chExtW
        let scaleY = extH / chExtH
        let mappedX = offX + (Double(childRect.origin.x) - chOffX) * scaleX
        let mappedY = offY + (Double(childRect.origin.y) - chOffY) * scaleY
        let mappedW = Double(childRect.size.width) * scaleX
        let mappedH = Double(childRect.size.height) * scaleY
        return CGRect(x: mappedX, y: mappedY, width: mappedW, height: mappedH)
    }
}

public final class PPTXPackageParser: Sendable {
    public static let shared = PPTXPackageParser()

    private var cacheRootDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("PowerPresenter_SessionCache", isDirectory: true)
    }

    public func cleanupOldCaches() {
        try? FileManager.default.removeItem(at: cacheRootDirectory)
        try? FileManager.default.createDirectory(at: cacheRootDirectory, withIntermediateDirectories: true)
    }

    public func extractAndParse(pptxURL: URL) throws -> [Int: PPTXSlideMetadata] {
        try? FileManager.default.createDirectory(at: cacheRootDirectory, withIntermediateDirectories: true)
        let sessionDir = cacheRootDirectory.appendingPathComponent("Deck_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)

        let unzipProcess = Process()
        unzipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzipProcess.arguments = ["-q", "-o", pptxURL.path, "-d", sessionDir.path]
        unzipProcess.standardOutput = Pipe()
        unzipProcess.standardError = Pipe()
        try unzipProcess.run()
        unzipProcess.waitUntilExit()

        let pptDir = sessionDir.appendingPathComponent("ppt", isDirectory: true)
        let slidesDir = pptDir.appendingPathComponent("slides", isDirectory: true)
        let notesDir = pptDir.appendingPathComponent("notesSlides", isDirectory: true)
        let mediaDir = pptDir.appendingPathComponent("media", isDirectory: true)

        guard FileManager.default.fileExists(atPath: slidesDir.path) else {
            return [:]
        }

        let defaultThemeColors = parseThemeColors(themeURL: pptDir.appendingPathComponent("theme/theme1.xml"))
        let (slideSizeEMU, orderedSlidePaths) = parsePresentationStructure(pptDir: pptDir, slidesDir: slidesDir)

        var results: [Int: PPTXSlideMetadata] = [:]

        for (index, slideXMLURL) in orderedSlidePaths.enumerated() {
            guard let slideDoc = try? XMLDocument(contentsOf: slideXMLURL, options: []),
                  let slideRoot = slideDoc.rootElement() else { continue }
            let slideFileName = slideXMLURL.lastPathComponent

            // 1. Parse slide relationships
            let slideRelsURL = slidesDir.appendingPathComponent("_rels/\(slideFileName).rels")
            let slideRels = parseRelationships(relsURL: slideRelsURL, baseDir: slidesDir)

            // 2. Locate linked SlideLayout, SlideMaster, and Theme
            var layoutRoot: XMLElement? = nil
            var layoutRels: [String: URL] = [:]
            var masterRoot: XMLElement? = nil
            var masterRels: [String: URL] = [:]
            var themeColors = defaultThemeColors

            if let layoutURL = slideRels.values.first(where: { $0.path.contains("/slideLayouts/") && $0.pathExtension == "xml" }) {
                layoutRoot = (try? XMLDocument(contentsOf: layoutURL, options: []))?.rootElement()
                let layoutRelsURL = layoutURL.deletingLastPathComponent().appendingPathComponent("_rels/\(layoutURL.lastPathComponent).rels")
                layoutRels = parseRelationships(relsURL: layoutRelsURL, baseDir: layoutURL.deletingLastPathComponent())

                if let masterURL = layoutRels.values.first(where: { $0.path.contains("/slideMasters/") && $0.pathExtension == "xml" }) {
                    masterRoot = (try? XMLDocument(contentsOf: masterURL, options: []))?.rootElement()
                    let masterRelsURL = masterURL.deletingLastPathComponent().appendingPathComponent("_rels/\(masterURL.lastPathComponent).rels")
                    masterRels = parseRelationships(relsURL: masterRelsURL, baseDir: masterURL.deletingLastPathComponent())

                    if let themeURL = masterRels.values.first(where: { $0.path.contains("/theme/") && $0.pathExtension == "xml" }) {
                        themeColors = parseThemeColors(themeURL: themeURL)
                    }
                }
            }

            // 3. Extract Slide Background (slide -> layout -> master)
            let background = extractBackground(
                slideRoot: slideRoot,
                slideRels: slideRels,
                layoutRoot: layoutRoot,
                layoutRels: layoutRels,
                masterRoot: masterRoot,
                masterRels: masterRels,
                themeColors: themeColors
            )

            // 4. Extract Layout/Master Placeholder frames for fallback coordinates
            let placeholderFrames = extractPlaceholderFrames(
                layoutRoot: layoutRoot,
                masterRoot: masterRoot,
                slideSizeEMU: slideSizeEMU
            )

            // 5. Extract Master/Layout decorative elements (if not hidden by showMasterSp="0")
            var elements: [SlideElement] = []
            var namedElements: [String: String] = [:]
            var zOrderCounter = 0

            let showMasterSp = slideRoot.attribute(forName: "showMasterSp")?.stringValue != "0"
            if showMasterSp {
                if let mRoot = masterRoot, let cSld = childElement(named: "cSld", in: mRoot), let spTree = childElement(named: "spTree", in: cSld) {
                    parseSpTree(
                        spTree: spTree,
                        rels: masterRels,
                        slideSizeEMU: slideSizeEMU,
                        placeholderFrames: placeholderFrames,
                        themeColors: themeColors,
                        groupStack: [],
                        isMasterOrLayout: true,
                        zOrderCounter: &zOrderCounter,
                        elements: &elements,
                        namedElements: &namedElements
                    )
                }
                if let lRoot = layoutRoot, let cSld = childElement(named: "cSld", in: lRoot), let spTree = childElement(named: "spTree", in: cSld) {
                    parseSpTree(
                        spTree: spTree,
                        rels: layoutRels,
                        slideSizeEMU: slideSizeEMU,
                        placeholderFrames: placeholderFrames,
                        themeColors: themeColors,
                        groupStack: [],
                        isMasterOrLayout: true,
                        zOrderCounter: &zOrderCounter,
                        elements: &elements,
                        namedElements: &namedElements
                    )
                }
            }

            // 6. Parse Slide's own <p:spTree> in exact back-to-front document order
            if let cSld = childElement(named: "cSld", in: slideRoot),
               let spTree = childElement(named: "spTree", in: cSld) {
                parseSpTree(
                    spTree: spTree,
                    rels: slideRels,
                    slideSizeEMU: slideSizeEMU,
                    placeholderFrames: placeholderFrames,
                    themeColors: themeColors,
                    groupStack: [],
                    isMasterOrLayout: false,
                    zOrderCounter: &zOrderCounter,
                    elements: &elements,
                    namedElements: &namedElements
                )
            }

            // 7. Determine Slide Title
            var slideTitle = namedElements["title"]
                ?? namedElements["제목 1"]
                ?? namedElements.first(where: { $0.key.lowercased().contains("title") || $0.key.contains("제목") })?.value
                ?? elements.first(where: { $0.kind == .text && !$0.text.isEmpty && !$0.text.lowercased().contains("ccli license") })?.text.components(separatedBy: .newlines).first
                ?? "Slide \(index + 1)"
            slideTitle = slideTitle.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            if slideTitle.isEmpty {
                slideTitle = "Slide \(index + 1)"
            }

            // 8. Extract Presenter Notes
            var notesText: String? = nil
            if let notesURL = slideRels.values.first(where: { $0.path.contains("/notesSlides/") && $0.pathExtension == "xml" }) {
                notesText = extractNotesText(from: notesURL)
            } else {
                let fallbackNoteURL = notesDir.appendingPathComponent("notesSlide\(index + 1).xml")
                notesText = extractNotesText(from: fallbackNoteURL)
            }

            // 9. Collect Media & Video/Audio Files for this slide
            var slideImageURLs: [URL] = []
            if let bgURL = background.backgroundImageURL {
                slideImageURLs.append(bgURL)
            }
            for el in elements where el.kind == .image {
                if let imgURL = el.imageURL, !slideImageURLs.contains(imgURL) {
                    slideImageURLs.append(imgURL)
                }
            }
            for url in slideRels.values {
                let ext = url.pathExtension.lowercased()
                if ["png", "jpg", "jpeg", "gif", "tiff", "bmp", "webp"].contains(ext),
                   FileManager.default.fileExists(atPath: url.path),
                   !slideImageURLs.contains(url) {
                    slideImageURLs.append(url)
                }
            }

            // Prefer video (.mp4/.mov/.m4v) first, then audio (.mp3/.m4a/.wav/.aac)
            let videoFile = slideRels.values.first(where: {
                let ext = $0.pathExtension.lowercased()
                return ["mp4", "mov", "m4v"].contains(ext) && FileManager.default.fileExists(atPath: $0.path)
            }) ?? slideRels.values.first(where: {
                let ext = $0.pathExtension.lowercased()
                return ["mp3", "m4a", "wav", "aac"].contains(ext) && FileManager.default.fileExists(atPath: $0.path)
            })

            if slideImageURLs.isEmpty, FileManager.default.fileExists(atPath: mediaDir.path),
               let allMedia = try? FileManager.default.contentsOfDirectory(at: mediaDir, includingPropertiesForKeys: nil) {
                let imageMedia = allMedia
                    .filter { ["png", "jpg", "jpeg"].contains($0.pathExtension.lowercased()) }
                    .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
                if imageMedia.count == orderedSlidePaths.count {
                    slideImageURLs = [imageMedia[index]]
                }
            }

            results[index] = PPTXSlideMetadata(
                slideIndex: index,
                title: slideTitle,
                notes: notesText,
                namedElements: namedElements,
                mediaFiles: slideImageURLs,
                videoFile: videoFile,
                elements: elements.sorted { $0.zOrder < $1.zOrder },
                background: background
            )
        }

        return results
    }

    // MARK: - Unified Document-Order <p:spTree> Parser

    private func parseSpTree(
        spTree: XMLElement,
        rels: [String: URL],
        slideSizeEMU: CGSize,
        placeholderFrames: [String: CGRect],
        themeColors: [String: String],
        groupStack: [GroupTransform],
        isMasterOrLayout: Bool,
        zOrderCounter: inout Int,
        elements: inout [SlideElement],
        namedElements: inout [String: String]
    ) {
        guard let children = spTree.children else { return }

        for node in children {
            guard let el = node as? XMLElement, let local = el.localName else { continue }

            switch local {
            case "grpSp":
                var nextStack = groupStack
                if let grpSpPr = childElement(named: "grpSpPr", in: el),
                   let xfrm = childElement(named: "xfrm", in: grpSpPr),
                   let off = childElement(named: "off", in: xfrm),
                   let ext = childElement(named: "ext", in: xfrm),
                   let chOff = childElement(named: "chOff", in: xfrm),
                   let chExt = childElement(named: "chExt", in: xfrm),
                   let ox = Double(off.attribute(forName: "x")?.stringValue ?? ""),
                   let oy = Double(off.attribute(forName: "y")?.stringValue ?? ""),
                   let ew = Double(ext.attribute(forName: "cx")?.stringValue ?? ""),
                   let eh = Double(ext.attribute(forName: "cy")?.stringValue ?? ""),
                   let cox = Double(chOff.attribute(forName: "x")?.stringValue ?? ""),
                   let coy = Double(chOff.attribute(forName: "y")?.stringValue ?? ""),
                   let cew = Double(chExt.attribute(forName: "cx")?.stringValue ?? ""),
                   let ceh = Double(chExt.attribute(forName: "cy")?.stringValue ?? ""),
                   ew > 0, eh > 0, cew > 0, ceh > 0 {
                    nextStack.append(
                        GroupTransform(
                            offX: ox, offY: oy, extW: ew, extH: eh,
                            chOffX: cox, chOffY: coy, chExtW: cew, chExtH: ceh
                        )
                    )
                }
                parseSpTree(
                    spTree: el,
                    rels: rels,
                    slideSizeEMU: slideSizeEMU,
                    placeholderFrames: placeholderFrames,
                    themeColors: themeColors,
                    groupStack: nextStack,
                    isMasterOrLayout: isMasterOrLayout,
                    zOrderCounter: &zOrderCounter,
                    elements: &elements,
                    namedElements: &namedElements
                )

            case "pic":
                if let picElement = parsePicElement(
                    pic: el,
                    rels: rels,
                    slideSizeEMU: slideSizeEMU,
                    themeColors: themeColors,
                    groupStack: groupStack,
                    zOrder: zOrderCounter
                ) {
                    zOrderCounter += 1
                    elements.append(picElement)
                }

            case "sp":
                if !isMasterOrLayout {
                    if let spElement = parseShapeElement(
                        sp: el,
                        slideSizeEMU: slideSizeEMU,
                        placeholderFrames: placeholderFrames,
                        themeColors: themeColors,
                        groupStack: groupStack,
                        zOrder: zOrderCounter,
                        namedElements: &namedElements
                    ) {
                        zOrderCounter += 1
                        elements.append(spElement)
                    }
                } else {
                    // On master/layout, only include non-placeholder decorative shapes with fills/strokes
                    let nvSpPr = childElement(named: "nvSpPr", in: el)
                    let nvPr = nvSpPr.flatMap { childElement(named: "nvPr", in: $0) }
                    let hasPh = nvPr.flatMap { childElement(named: "ph", in: $0) } != nil
                    if !hasPh {
                        var dummyNamed: [String: String] = [:]
                        if let spElement = parseShapeElement(
                            sp: el,
                            slideSizeEMU: slideSizeEMU,
                            placeholderFrames: placeholderFrames,
                            themeColors: themeColors,
                            groupStack: groupStack,
                            zOrder: zOrderCounter,
                            namedElements: &dummyNamed
                        ), spElement.kind == .shape {
                            zOrderCounter += 1
                            elements.append(spElement)
                        }
                    }
                }

            default:
                break
            }
        }
    }

    // MARK: - Parse <p:pic>

    private func parsePicElement(
        pic: XMLElement,
        rels: [String: URL],
        slideSizeEMU: CGSize,
        themeColors: [String: String],
        groupStack: [GroupTransform],
        zOrder: Int
    ) -> SlideElement? {
        let nvPicPr = childElement(named: "nvPicPr", in: pic)
        let cNvPr = nvPicPr.flatMap { childElement(named: "cNvPr", in: $0) }
        let nvPr = nvPicPr.flatMap { childElement(named: "nvPr", in: $0) }

        // Skip speaker icon pictures attached to background audio files (<a:audioFile>)
        if let nvPr = nvPr, childElement(named: "audioFile", in: nvPr) != nil {
            return nil
        }

        let name = cNvPr?.attribute(forName: "name")?.stringValue ?? "Picture"

        guard let blipFill = childElement(named: "blipFill", in: pic),
              let blip = childElement(named: "blip", in: blipFill),
              let embedId = attributeValue(named: "embed", in: blip),
              let imageURL = rels[embedId],
              FileManager.default.fileExists(atPath: imageURL.path) else {
            return nil
        }

        // Crop (<a:srcRect l="..." t="..." r="..." b="..."/>) in 1/1000ths of a percent (100000 = 1.0)
        var cropInsets: CGRect? = nil
        if let srcRect = childElement(named: "srcRect", in: blipFill) {
            let l = (Double(srcRect.attribute(forName: "l")?.stringValue ?? "0") ?? 0) / 100_000.0
            let t = (Double(srcRect.attribute(forName: "t")?.stringValue ?? "0") ?? 0) / 100_000.0
            let r = (Double(srcRect.attribute(forName: "r")?.stringValue ?? "0") ?? 0) / 100_000.0
            let b = (Double(srcRect.attribute(forName: "b")?.stringValue ?? "0") ?? 0) / 100_000.0
            if l > 0.001 || t > 0.001 || r > 0.001 || b > 0.001 {
                cropInsets = CGRect(x: l, y: t, width: r, height: b)
            }
        }

        // Alpha opacity (<a:alphaModFix amt="..."/>)
        var imageOpacity: CGFloat = 1.0
        if let alphaNode = childElement(named: "alphaModFix", in: blip),
           let amt = Double(alphaNode.attribute(forName: "amt")?.stringValue ?? "100000") {
            imageOpacity = CGFloat(max(0.0, min(1.0, amt / 100_000.0)))
        }

        // Duotone effect (<a:duotone>)
        var duotone1: String? = nil
        var duotone2: String? = nil
        if let duotoneNode = childElement(named: "duotone", in: blip),
           let colorChildren = duotoneNode.children?.compactMap({ $0 as? XMLElement }),
           colorChildren.count >= 2 {
            duotone1 = resolveColorElement(colorChildren[0], themeColors: themeColors)
            duotone2 = resolveColorElement(colorChildren[1], themeColors: themeColors)
        }

        let spPr = childElement(named: "spPr", in: pic)
        let normRect = spPr.flatMap { parseNormalizedRect(spPr: $0, slideSizeEMU: slideSizeEMU, groupStack: groupStack) }
            ?? CGRect(x: 0, y: 0, width: 1, height: 1)

        let hasStretch = childElement(named: "stretch", in: blipFill) != nil

        return SlideElement(
            kind: .image,
            name: name,
            normalizedRect: normRect,
            imageURL: imageURL,
            imageCropInsets: cropInsets,
            imageOpacity: imageOpacity,
            duotoneColor1Hex: duotone1,
            duotoneColor2Hex: duotone2,
            stretchFill: hasStretch,
            zOrder: zOrder
        )
    }

    // MARK: - Parse <p:sp> (Shapes & Rich Text)

    private func parseShapeElement(
        sp: XMLElement,
        slideSizeEMU: CGSize,
        placeholderFrames: [String: CGRect],
        themeColors: [String: String],
        groupStack: [GroupTransform],
        zOrder: Int,
        namedElements: inout [String: String]
    ) -> SlideElement? {
        let nvSpPr = childElement(named: "nvSpPr", in: sp)
        let cNvPr = nvSpPr.flatMap { childElement(named: "cNvPr", in: $0) }
        let nvPr = nvSpPr.flatMap { childElement(named: "nvPr", in: $0) }
        let ph = nvPr.flatMap { childElement(named: "ph", in: $0) }

        let shapeName = (cNvPr?.attribute(forName: "name")?.stringValue ?? "Shape").trimmingCharacters(in: .whitespacesAndNewlines)
        let phType = ph?.attribute(forName: "type")?.stringValue
        let phIdx = ph?.attribute(forName: "idx")?.stringValue

        let spPr = childElement(named: "spPr", in: sp)
        var rect = spPr.flatMap { parseNormalizedRect(spPr: $0, slideSizeEMU: slideSizeEMU, groupStack: groupStack) }

        if rect == nil {
            if let t = phType, let inherited = placeholderFrames["type:\(t)"] {
                rect = inherited
            } else if let i = phIdx, let inherited = placeholderFrames["idx:\(i)"] {
                rect = inherited
            } else if phType == "title" || phType == "ctrTitle" || shapeName.lowercased().contains("title") || shapeName.contains("제목") {
                rect = CGRect(x: 0.06, y: 0.08, width: 0.88, height: 0.22)
            } else if phType == "subTitle" {
                rect = CGRect(x: 0.08, y: 0.32, width: 0.84, height: 0.20)
            } else {
                rect = CGRect(x: 0.06, y: 0.25, width: 0.88, height: 0.65)
            }
        }

        // Shape Fill & Stroke (direct children of <p:spPr>)
        var fillColorHex: String? = nil
        var fillGradientEndHex: String? = nil
        var strokeColorHex: String? = nil
        var strokeGradientEndHex: String? = nil
        var strokeWidthPt: CGFloat = 0

        if let spPr = spPr {
            if childElement(named: "noFill", in: spPr) == nil {
                if let solidFill = childElement(named: "solidFill", in: spPr) {
                    fillColorHex = resolveFillContainer(solidFill, themeColors: themeColors)
                } else if let gradFill = childElement(named: "gradFill", in: spPr) {
                    let (startHex, endHex) = resolveGradientContainer(gradFill, themeColors: themeColors)
                    fillColorHex = startHex
                    fillGradientEndHex = endHex
                }
            }

            if let ln = childElement(named: "ln", in: spPr),
               childElement(named: "noFill", in: ln) == nil {
                let wEMU = Double(ln.attribute(forName: "w")?.stringValue ?? "12700") ?? 12700
                if wEMU > 0 {
                    if let solidFill = childElement(named: "solidFill", in: ln) {
                        strokeColorHex = resolveFillContainer(solidFill, themeColors: themeColors)
                    } else if let gradFill = childElement(named: "gradFill", in: ln) {
                        let (startHex, endHex) = resolveGradientContainer(gradFill, themeColors: themeColors)
                        strokeColorHex = startHex
                        strokeGradientEndHex = endHex
                    }
                    if strokeColorHex != nil {
                        strokeWidthPt = max(1.0, CGFloat(wEMU / 12700.0))
                    }
                }
            }
        }

        // Parse <p:txBody>
        var paragraphs: [SlideParagraph] = []
        var verticalAnchor: SlideVerticalAnchor = .top
        var autoFitText: Bool = true

        if let txBody = childElement(named: "txBody", in: sp) {
            if let bodyPr = childElement(named: "bodyPr", in: txBody) {
                if let anchor = bodyPr.attribute(forName: "anchor")?.stringValue {
                    switch anchor {
                    case "ctr": verticalAnchor = .center
                    case "b": verticalAnchor = .bottom
                    default: verticalAnchor = .top
                    }
                }
                if childElement(named: "noAutofit", in: bodyPr) != nil {
                    autoFitText = false
                }
            }

            // Default font size & color from <a:lstStyle><a:lvl1pPr><a:defRPr>
            var lstDefaultFontSizePt: CGFloat? = nil
            var lstDefaultBold: Bool = false
            var lstDefaultColorHex: String? = nil
            var lstDefaultAlignment: SlideTextAlignment? = nil

            if let lstStyle = childElement(named: "lstStyle", in: txBody),
               let lvl1pPr = childElement(named: "lvl1pPr", in: lstStyle) {
                if let algn = lvl1pPr.attribute(forName: "algn")?.stringValue {
                    lstDefaultAlignment = mapAlignment(algn)
                }
                if let defRPr = childElement(named: "defRPr", in: lvl1pPr) {
                    if let sz = Double(defRPr.attribute(forName: "sz")?.stringValue ?? ""), sz > 0 {
                        lstDefaultFontSizePt = CGFloat(sz / 100.0)
                    }
                    if defRPr.attribute(forName: "b")?.stringValue == "1" {
                        lstDefaultBold = true
                    }
                    if let solid = childElement(named: "solidFill", in: defRPr) {
                        lstDefaultColorHex = resolveFillContainer(solid, themeColors: themeColors)
                    }
                }
            }

            let fallbackFontSize: CGFloat = lstDefaultFontSizePt
                ?? ((phType == "title" || phType == "ctrTitle") ? 44.0 : 32.0)

            let pNodes = txBody.children?.compactMap { $0 as? XMLElement }.filter { $0.localName == "p" } ?? []

            for pNode in pNodes {
                var pAlign: SlideTextAlignment = lstDefaultAlignment ?? ((phType == "ctrTitle") ? .center : .left)
                var leftMarginPt: CGFloat = 0
                var indentPt: CGFloat = 0
                var lineSpacingMultiplier: CGFloat = 1.08
                var spaceBeforePt: CGFloat = 0
                var spaceAfterPt: CGFloat = 0
                var pDefFontSizePt: CGFloat = fallbackFontSize
                var pDefBold: Bool = lstDefaultBold
                var pDefColorHex: String? = lstDefaultColorHex

                if let pPr = childElement(named: "pPr", in: pNode) {
                    if let algn = pPr.attribute(forName: "algn")?.stringValue {
                        pAlign = mapAlignment(algn)
                    }
                    if let marL = Double(pPr.attribute(forName: "marL")?.stringValue ?? ""), marL > 0 {
                        leftMarginPt = CGFloat(marL / 12700.0)
                    }
                    if let indent = Double(pPr.attribute(forName: "indent")?.stringValue ?? "") {
                        indentPt = CGFloat(indent / 12700.0)
                    }
                    if let lnSpc = childElement(named: "lnSpc", in: pPr),
                       let spcPct = childElement(named: "spcPct", in: lnSpc),
                       let pctVal = Double(spcPct.attribute(forName: "val")?.stringValue ?? ""), pctVal > 0 {
                        lineSpacingMultiplier = CGFloat(pctVal / 100_000.0)
                    }
                    if let spcBef = childElement(named: "spcBef", in: pPr),
                       let spcPts = childElement(named: "spcPts", in: spcBef),
                       let ptsVal = Double(spcPts.attribute(forName: "val")?.stringValue ?? ""), ptsVal > 0 {
                        spaceBeforePt = CGFloat(ptsVal / 100.0)
                    }
                    if let spcAft = childElement(named: "spcAft", in: pPr),
                       let spcPts = childElement(named: "spcPts", in: spcAft),
                       let ptsVal = Double(spcPts.attribute(forName: "val")?.stringValue ?? ""), ptsVal > 0 {
                        spaceAfterPt = CGFloat(ptsVal / 100.0)
                    }
                    if let defRPr = childElement(named: "defRPr", in: pPr) {
                        if let sz = Double(defRPr.attribute(forName: "sz")?.stringValue ?? ""), sz > 0 {
                            pDefFontSizePt = CGFloat(sz / 100.0)
                        }
                        if defRPr.attribute(forName: "b")?.stringValue == "1" {
                            pDefBold = true
                        }
                        if let solid = childElement(named: "solidFill", in: defRPr) {
                            pDefColorHex = resolveFillContainer(solid, themeColors: themeColors)
                        }
                    }
                }

                var runs: [SlideTextRun] = []

                for child in pNode.children?.compactMap({ $0 as? XMLElement }) ?? [] {
                    let cName = child.localName ?? ""
                    if cName == "r" || cName == "fld" {
                        let tNode = childElement(named: "t", in: child)
                        let textVal = tNode?.stringValue ?? ""
                        guard !textVal.isEmpty else { continue }

                        var runFontSize = pDefFontSizePt
                        var runBold = pDefBold
                        var runItalic = false
                        var runFontFamily: String? = nil
                        var runColorHex: String? = pDefColorHex
                        var runGradEndHex: String? = nil
                        var runBaseline: CGFloat = 0

                        if let rPr = childElement(named: "rPr", in: child) {
                            if let sz = Double(rPr.attribute(forName: "sz")?.stringValue ?? ""), sz > 0 {
                                runFontSize = CGFloat(sz / 100.0)
                            }
                            if let bAttr = rPr.attribute(forName: "b")?.stringValue {
                                runBold = (bAttr == "1" || bAttr == "true")
                            }
                            if let iAttr = rPr.attribute(forName: "i")?.stringValue {
                                runItalic = (iAttr == "1" || iAttr == "true")
                            }
                            if let baseAttr = Double(rPr.attribute(forName: "baseline")?.stringValue ?? "") {
                                runBaseline = CGFloat(baseAttr / 1000.0)
                            }

                            // IMPORTANT: Inspect ONLY direct children of <a:rPr> (skipping <a:ln> outline!)
                            if let solidFill = childElement(named: "solidFill", in: rPr) {
                                runColorHex = resolveFillContainer(solidFill, themeColors: themeColors)
                            } else if let gradFill = childElement(named: "gradFill", in: rPr) {
                                let (startHex, endHex) = resolveGradientContainer(gradFill, themeColors: themeColors)
                                runColorHex = startHex
                                runGradEndHex = endHex
                            }

                            let eaFont = childElement(named: "ea", in: rPr)?.attribute(forName: "typeface")?.stringValue
                            let latinFont = childElement(named: "latin", in: rPr)?.attribute(forName: "typeface")?.stringValue
                            runFontFamily = resolveFontFamily(ea: eaFont, latin: latinFont)
                            if let rf = runFontFamily, rf.lowercased().contains("extrabold") || rf.lowercased().contains("bold") {
                                runBold = true
                            }
                        }

                        runs.append(
                            SlideTextRun(
                                text: textVal,
                                fontSizePt: runFontSize,
                                isBold: runBold,
                                isItalic: runItalic,
                                fontFamily: runFontFamily,
                                textColorHex: runColorHex,
                                gradientEndColorHex: runGradEndHex,
                                baselinePercent: runBaseline
                            )
                        )
                    } else if cName == "br" {
                        runs.append(
                            SlideTextRun(
                                text: "\n",
                                fontSizePt: pDefFontSizePt,
                                isBold: pDefBold,
                                textColorHex: pDefColorHex
                            )
                        )
                    }
                }

                let joinedText = runs.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
                if !joinedText.isEmpty {
                    paragraphs.append(
                        SlideParagraph(
                            runs: runs,
                            alignment: pAlign,
                            leftMarginPt: leftMarginPt,
                            indentPt: indentPt,
                            lineSpacingMultiplier: lineSpacingMultiplier,
                            spaceBeforePt: spaceBeforePt,
                            spaceAfterPt: spaceAfterPt
                        )
                    )
                }
            }
        }

        let fullText = paragraphs
            .map { $0.plainText.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        if !fullText.isEmpty {
            registerNamedElement(
                shapeName: shapeName,
                phType: phType,
                phIdx: phIdx,
                fullText: fullText,
                namedElements: &namedElements
            )
        }

        guard !fullText.isEmpty || fillColorHex != nil || strokeColorHex != nil else {
            return nil
        }

        let firstRun = paragraphs.first?.runs.first
        let primaryFontSize = firstRun?.fontSizePt ?? ((phType == "title" || phType == "ctrTitle") ? 44.0 : 32.0)
        let primaryBold = firstRun?.isBold ?? false
        let primaryFontFamily = firstRun?.fontFamily
        let primaryTextColor = firstRun?.textColorHex ?? (themeColors["tx1"] ?? "000000")
        let primaryGradEnd = firstRun?.gradientEndColorHex
        let primaryAlign = paragraphs.first?.alignment ?? .left

        return SlideElement(
            kind: fullText.isEmpty ? .shape : .text,
            name: shapeName,
            text: fullText,
            paragraphs: paragraphs,
            normalizedRect: rect ?? CGRect(x: 0.06, y: 0.20, width: 0.88, height: 0.65),
            fontSizePt: primaryFontSize,
            isBold: primaryBold,
            fontFamily: primaryFontFamily,
            textColorHex: primaryTextColor,
            textGradientEndHex: primaryGradEnd,
            fillColorHex: fillColorHex,
            fillGradientEndHex: fillGradientEndHex,
            strokeColorHex: strokeColorHex,
            strokeGradientEndHex: strokeGradientEndHex,
            strokeWidthPt: strokeWidthPt,
            alignment: primaryAlign,
            verticalAnchor: verticalAnchor,
            autoFitText: autoFitText,
            zOrder: zOrder
        )
    }

    private func registerNamedElement(
        shapeName: String,
        phType: String?,
        phIdx: String?,
        fullText: String,
        namedElements: inout [String: String]
    ) {
        let isCCLI = fullText.lowercased().contains("ccli license") || fullText.lowercased().contains("streaming license")

        if isCCLI {
            namedElements["copyright"] = fullText
            if let songTitle = fullText.components(separatedBy: .newlines).first?.trimmingCharacters(in: .whitespacesAndNewlines), !songTitle.isEmpty {
                namedElements["song_title"] = songTitle
            }
        } else if phIdx == "1" || shapeName.contains("내용") || shapeName.lowercased().contains("body") {
            namedElements["lyrics"] = fullText
            namedElements["body"] = fullText
        }

        if !shapeName.isEmpty {
            if let existing = namedElements[shapeName] {
                // If an element with the same name already exists (e.g. two "내용 개체 틀 2" on worship slides),
                // keep the non-CCLI main lyrics as the primary key and store the secondary under "#2".
                if isCCLI && !existing.lowercased().contains("ccli license") {
                    namedElements["\(shapeName) (CCLI)"] = fullText
                } else {
                    namedElements["\(shapeName) #2"] = existing
                    namedElements[shapeName] = fullText
                    namedElements[shapeName.lowercased()] = fullText
                }
            } else {
                namedElements[shapeName] = fullText
                namedElements[shapeName.lowercased()] = fullText
            }
        }

        if phType == "title" || phType == "ctrTitle" || shapeName.contains("제목") {
            if namedElements["title"] == nil {
                namedElements["title"] = fullText
            }
        } else if phType == "subTitle" {
            namedElements["subtitle"] = fullText
        }
    }

    // MARK: - Background Extraction

    private func extractBackground(
        slideRoot: XMLElement,
        slideRels: [String: URL],
        layoutRoot: XMLElement?,
        layoutRels: [String: URL],
        masterRoot: XMLElement?,
        masterRels: [String: URL],
        themeColors: [String: String]
    ) -> SlideBackground {
        let sources: [(XMLElement?, [String: URL])] = [
            (slideRoot, slideRels),
            (layoutRoot, layoutRels),
            (masterRoot, masterRels)
        ]

        for (rootOpt, rels) in sources {
            guard let root = rootOpt,
                  let cSld = childElement(named: "cSld", in: root),
                  let bg = childElement(named: "bg", in: cSld),
                  let bgPr = childElement(named: "bgPr", in: bg) else {
                continue
            }

            if let blipFill = childElement(named: "blipFill", in: bgPr),
               let blip = childElement(named: "blip", in: blipFill),
               let embedId = attributeValue(named: "embed", in: blip),
               let imgURL = rels[embedId],
               FileManager.default.fileExists(atPath: imgURL.path) {
                return SlideBackground(backgroundImageURL: imgURL)
            }

            if let gradFill = childElement(named: "gradFill", in: bgPr) {
                let (startHex, endHex) = resolveGradientContainer(gradFill, themeColors: themeColors)
                if let startHex = startHex {
                    return SlideBackground(colorHex: startHex, gradientEndHex: endHex)
                }
            }

            if let solidFill = childElement(named: "solidFill", in: bgPr),
               let hex = resolveFillContainer(solidFill, themeColors: themeColors) {
                return SlideBackground(colorHex: hex)
            }
        }

        return SlideBackground(colorHex: themeColors["bg1"] ?? "FFFFFF")
    }

    // MARK: - Placeholder Frames Inheritance

    private func extractPlaceholderFrames(
        layoutRoot: XMLElement?,
        masterRoot: XMLElement?,
        slideSizeEMU: CGSize
    ) -> [String: CGRect] {
        var frames: [String: CGRect] = [:]
        for rootOpt in [masterRoot, layoutRoot] {
            guard let root = rootOpt,
                  let cSld = childElement(named: "cSld", in: root),
                  let spTree = childElement(named: "spTree", in: cSld),
                  let children = spTree.children else { continue }

            for node in children {
                guard let sp = node as? XMLElement, sp.localName == "sp",
                      let spPr = childElement(named: "spPr", in: sp),
                      let rect = parseNormalizedRect(spPr: spPr, slideSizeEMU: slideSizeEMU, groupStack: []),
                      let nvSpPr = childElement(named: "nvSpPr", in: sp),
                      let nvPr = childElement(named: "nvPr", in: nvSpPr),
                      let ph = childElement(named: "ph", in: nvPr) else {
                    continue
                }
                if let phType = ph.attribute(forName: "type")?.stringValue {
                    frames["type:\(phType)"] = rect
                }
                if let phIdx = ph.attribute(forName: "idx")?.stringValue {
                    frames["idx:\(phIdx)"] = rect
                }
            }
        }
        return frames
    }

    // MARK: - Presentation Structure & Relationships

    private func parsePresentationStructure(pptDir: URL, slidesDir: URL) -> (CGSize, [URL]) {
        var slideSize = CGSize(width: 12192000, height: 6858000)
        let presURL = pptDir.appendingPathComponent("presentation.xml")
        let presRelsURL = pptDir.appendingPathComponent("_rels/presentation.xml.rels")
        let presRels = parseRelationships(relsURL: presRelsURL, baseDir: pptDir)

        var orderedURLs: [URL] = []

        if let presDoc = try? XMLDocument(contentsOf: presURL, options: []),
           let root = presDoc.rootElement() {
            if let sldSz = childElement(named: "sldSz", in: root),
               let cx = Double(sldSz.attribute(forName: "cx")?.stringValue ?? ""),
               let cy = Double(sldSz.attribute(forName: "cy")?.stringValue ?? ""),
               cx > 0, cy > 0 {
                slideSize = CGSize(width: cx, height: cy)
            }

            if let sldIdLst = childElement(named: "sldIdLst", in: root),
               let children = sldIdLst.children?.compactMap({ $0 as? XMLElement }) {
                for sldId in children where sldId.localName == "sldId" {
                    if let rId = attributeValue(named: "id", in: sldId),
                       let targetURL = presRels[rId],
                       FileManager.default.fileExists(atPath: targetURL.path) {
                        orderedURLs.append(targetURL)
                    }
                }
            }
        }

        if orderedURLs.isEmpty, let slideFiles = try? FileManager.default.contentsOfDirectory(atPath: slidesDir.path) {
            let sortedNames = slideFiles
                .filter { $0.hasPrefix("slide") && $0.hasSuffix(".xml") }
                .sorted { a, b in
                    let numA = Int(a.replacingOccurrences(of: "slide", with: "").replacingOccurrences(of: ".xml", with: "")) ?? 0
                    let numB = Int(b.replacingOccurrences(of: "slide", with: "").replacingOccurrences(of: ".xml", with: "")) ?? 0
                    return numA < numB
                }
            orderedURLs = sortedNames.map { slidesDir.appendingPathComponent($0) }
        }

        return (slideSize, orderedURLs)
    }

    private func parseRelationships(relsURL: URL, baseDir: URL) -> [String: URL] {
        guard FileManager.default.fileExists(atPath: relsURL.path),
              let doc = try? XMLDocument(contentsOf: relsURL, options: []),
              let root = doc.rootElement(),
              let children = root.children?.compactMap({ $0 as? XMLElement }) else {
            return [:]
        }

        var map: [String: URL] = [:]
        for rel in children where rel.localName == "Relationship" {
            guard let rId = rel.attribute(forName: "Id")?.stringValue,
                  let rawTarget = rel.attribute(forName: "Target")?.stringValue else { continue }
            if rawTarget == "NULL" || rawTarget.hasPrefix("http://") || rawTarget.hasPrefix("https://") || rawTarget.hasPrefix("mailto:") {
                continue
            }
            let resolvedURL: URL
            if rawTarget.hasPrefix("/") {
                let rootDir = baseDir.deletingLastPathComponent().deletingLastPathComponent()
                resolvedURL = rootDir.appendingPathComponent(String(rawTarget.dropFirst())).standardizedFileURL
            } else {
                resolvedURL = baseDir.appendingPathComponent(rawTarget).standardizedFileURL
            }
            map[rId] = resolvedURL
        }
        return map
    }

    // MARK: - Theme Colors & OpenXML Color Modifiers

    private func parseThemeColors(themeURL: URL) -> [String: String] {
        var colors: [String: String] = [
            "dk1": "000000",
            "lt1": "FFFFFF",
            "dk2": "44546A",
            "lt2": "E7E6E6",
            "accent1": "4472C4",
            "accent2": "ED7D31",
            "accent3": "A5A5A5",
            "accent4": "FFC000",
            "accent5": "5B9BD5",
            "accent6": "70AD47",
            "tx1": "000000",
            "bg1": "FFFFFF",
            "tx2": "44546A",
            "bg2": "E7E6E6"
        ]

        guard FileManager.default.fileExists(atPath: themeURL.path),
              let doc = try? XMLDocument(contentsOf: themeURL, options: []),
              let root = doc.rootElement(),
              let themeElements = childElement(named: "themeElements", in: root),
              let clrScheme = childElement(named: "clrScheme", in: themeElements),
              let schemeNodes = clrScheme.children?.compactMap({ $0 as? XMLElement }) else {
            return colors
        }

        for node in schemeNodes {
            guard let key = node.localName,
                  let colorChild = node.children?.compactMap({ $0 as? XMLElement }).first else { continue }
            if let val = colorChild.attribute(forName: "val")?.stringValue, val.count == 6 {
                colors[key] = val.uppercased()
            } else if let lastClr = colorChild.attribute(forName: "lastClr")?.stringValue, lastClr.count == 6 {
                colors[key] = lastClr.uppercased()
            }
        }

        colors["tx1"] = colors["dk1"]
        colors["bg1"] = colors["lt1"]
        colors["tx2"] = colors["dk2"]
        colors["bg2"] = colors["lt2"]
        return colors
    }

    private func resolveFillContainer(_ container: XMLElement, themeColors: [String: String]) -> String? {
        guard let colorChild = container.children?.compactMap({ $0 as? XMLElement }).first else { return nil }
        return resolveColorElement(colorChild, themeColors: themeColors)
    }

    private func resolveGradientContainer(_ gradFill: XMLElement, themeColors: [String: String]) -> (String?, String?) {
        guard let gsLst = childElement(named: "gsLst", in: gradFill),
              let stops = gsLst.children?.compactMap({ $0 as? XMLElement }).filter({ $0.localName == "gs" }),
              !stops.isEmpty else {
            return (nil, nil)
        }
        let resolved = stops.compactMap { resolveFillContainer($0, themeColors: themeColors) }
        return (resolved.first, resolved.count > 1 ? resolved.last : nil)
    }

    private func resolveColorElement(_ colorNode: XMLElement, themeColors: [String: String]) -> String? {
        guard let local = colorNode.localName else { return nil }
        var baseHex: String? = nil

        switch local {
        case "srgbClr":
            baseHex = colorNode.attribute(forName: "val")?.stringValue?.uppercased()
        case "schemeClr":
            if let scheme = colorNode.attribute(forName: "val")?.stringValue {
                baseHex = themeColors[scheme] ?? "000000"
            }
        case "sysClr":
            if let lastClr = colorNode.attribute(forName: "lastClr")?.stringValue, lastClr.count == 6 {
                baseHex = lastClr.uppercased()
            } else if let val = colorNode.attribute(forName: "val")?.stringValue {
                baseHex = val.lowercased().contains("windowtext") ? "000000" : "FFFFFF"
            }
        case "prstClr":
            if let prst = colorNode.attribute(forName: "val")?.stringValue?.lowercased() {
                switch prst {
                case "black": baseHex = "000000"
                case "white": baseHex = "FFFFFF"
                case "red": baseHex = "FF0000"
                case "green": baseHex = "00FF00"
                case "blue": baseHex = "0000FF"
                case "yellow": baseHex = "FFFF00"
                case "gray", "grey": baseHex = "808080"
                default: baseHex = "000000"
                }
            }
        default:
            break
        }

        guard let hex = baseHex else { return nil }
        return applyColorModifiers(baseHex: hex, colorNode: colorNode)
    }

    private func applyColorModifiers(baseHex: String, colorNode: XMLElement) -> String {
        guard let modifiers = colorNode.children?.compactMap({ $0 as? XMLElement }), !modifiers.isEmpty else {
            return baseHex
        }

        let cleaned = baseHex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6, let rgbVal = UInt64(cleaned, radix: 16) else { return baseHex }

        var r = Double((rgbVal & 0xFF0000) >> 16) / 255.0
        var g = Double((rgbVal & 0x00FF00) >> 8) / 255.0
        var b = Double(rgbVal & 0x0000FF) / 255.0

        var (h, s, l) = rgbToHSL(r: r, g: g, b: b)
        var didModifyHSL = false

        for mod in modifiers {
            guard let name = mod.localName,
                  let rawVal = Double(mod.attribute(forName: "val")?.stringValue ?? "") else { continue }
            let factor = rawVal / 100_000.0

            switch name {
            case "lumMod":
                l *= factor
                didModifyHSL = true
            case "lumOff":
                l += factor
                didModifyHSL = true
            case "satMod":
                s = min(1.0, max(0.0, s * factor))
                didModifyHSL = true
            case "tint":
                if didModifyHSL {
                    (r, g, b) = hslToRGB(h: h, s: s, l: min(1.0, max(0.0, l)))
                    didModifyHSL = false
                }
                r = 1.0 - (1.0 - r) * factor
                g = 1.0 - (1.0 - g) * factor
                b = 1.0 - (1.0 - b) * factor
                (h, s, l) = rgbToHSL(r: r, g: g, b: b)
            case "shade":
                if didModifyHSL {
                    (r, g, b) = hslToRGB(h: h, s: s, l: min(1.0, max(0.0, l)))
                    didModifyHSL = false
                }
                r *= factor
                g *= factor
                b *= factor
                (h, s, l) = rgbToHSL(r: r, g: g, b: b)
            default:
                break
            }
        }

        if didModifyHSL {
            (r, g, b) = hslToRGB(h: h, s: s, l: min(1.0, max(0.0, l)))
        }

        let ri = Int(round(min(1.0, max(0.0, r)) * 255.0))
        let gi = Int(round(min(1.0, max(0.0, g)) * 255.0))
        let bi = Int(round(min(1.0, max(0.0, b)) * 255.0))
        return String(format: "%02X%02X%02X", ri, gi, bi)
    }

    private func rgbToHSL(r: Double, g: Double, b: Double) -> (Double, Double, Double) {
        let maxC = max(r, g, b)
        let minC = min(r, g, b)
        let l = (maxC + minC) / 2.0

        guard maxC != minC else { return (0, 0, l) }
        let d = maxC - minC
        let s = l > 0.5 ? d / (2.0 - maxC - minC) : d / (maxC + minC)
        var h: Double = 0
        if maxC == r {
            h = (g - b) / d + (g < b ? 6.0 : 0.0)
        } else if maxC == g {
            h = (b - r) / d + 2.0
        } else {
            h = (r - g) / d + 4.0
        }
        h /= 6.0
        return (h, s, l)
    }

    private func hslToRGB(h: Double, s: Double, l: Double) -> (Double, Double, Double) {
        guard s > 0 else { return (l, l, l) }
        func hue2rgb(_ p: Double, _ q: Double, _ tIn: Double) -> Double {
            var t = tIn
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1.0 / 6.0 { return p + (q - p) * 6.0 * t }
            if t < 1.0 / 2.0 { return q }
            if t < 2.0 / 3.0 { return p + (q - p) * (2.0 / 3.0 - t) * 6.0 }
            return p
        }
        let q = l < 0.5 ? l * (1.0 + s) : l + s - l * s
        let p = 2.0 * l - q
        return (
            hue2rgb(p, q, h + 1.0 / 3.0),
            hue2rgb(p, q, h),
            hue2rgb(p, q, h - 1.0 / 3.0)
        )
    }

    // MARK: - Geometry & Font Helpers

    private func parseNormalizedRect(spPr: XMLElement, slideSizeEMU: CGSize, groupStack: [GroupTransform]) -> CGRect? {
        guard let xfrm = childElement(named: "xfrm", in: spPr),
              let off = childElement(named: "off", in: xfrm),
              let ext = childElement(named: "ext", in: xfrm),
              let x = Double(off.attribute(forName: "x")?.stringValue ?? ""),
              let y = Double(off.attribute(forName: "y")?.stringValue ?? ""),
              let cx = Double(ext.attribute(forName: "cx")?.stringValue ?? ""),
              let cy = Double(ext.attribute(forName: "cy")?.stringValue ?? ""),
              cx > 0, cy > 0,
              slideSizeEMU.width > 0, slideSizeEMU.height > 0 else {
            return nil
        }

        var emuRect = CGRect(x: x, y: y, width: cx, height: cy)
        for tf in groupStack.reversed() {
            emuRect = tf.mapRect(emuRect)
        }

        return CGRect(
            x: emuRect.origin.x / slideSizeEMU.width,
            y: emuRect.origin.y / slideSizeEMU.height,
            width: emuRect.size.width / slideSizeEMU.width,
            height: emuRect.size.height / slideSizeEMU.height
        )
    }

    private func mapAlignment(_ algn: String) -> SlideTextAlignment {
        switch algn {
        case "ctr": return .center
        case "r": return .right
        case "just", "dist": return .justified
        default: return .left
        }
    }

    private func resolveFontFamily(ea: String?, latin: String?) -> String? {
        for candidate in [ea, latin] {
            guard let font = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !font.isEmpty else { continue }
            if font.hasPrefix("+mj") {
                return "NanumMyeongjo"
            } else if font.hasPrefix("+mn") {
                return "NanumBarunGothic"
            }
            return font
        }
        return nil
    }

    private func extractNotesText(from url: URL) -> String? {
        guard FileManager.default.fileExists(atPath: url.path),
              let doc = try? XMLDocument(contentsOf: url, options: []),
              let root = doc.rootElement(),
              let cSld = childElement(named: "cSld", in: root),
              let spTree = childElement(named: "spTree", in: cSld),
              let shapes = spTree.children?.compactMap({ $0 as? XMLElement }).filter({ $0.localName == "sp" }) else {
            return nil
        }

        var lines: [String] = []
        for sp in shapes {
            // Skip slide number placeholder in notes
            if let nvSpPr = childElement(named: "nvSpPr", in: sp),
               let nvPr = childElement(named: "nvPr", in: nvSpPr),
               let ph = childElement(named: "ph", in: nvPr),
               let phType = ph.attribute(forName: "type")?.stringValue,
               phType == "sldNum" || phType == "SlideImage" || phType == "sldImg" {
                continue
            }
            guard let txBody = childElement(named: "txBody", in: sp),
                  let pNodes = txBody.children?.compactMap({ $0 as? XMLElement }).filter({ $0.localName == "p" }) else {
                continue
            }
            for p in pNodes {
                var pText = ""
                for child in p.children?.compactMap({ $0 as? XMLElement }) ?? [] {
                    if child.localName == "r" || child.localName == "fld" {
                        pText += childElement(named: "t", in: child)?.stringValue ?? ""
                    } else if child.localName == "br" {
                        pText += "\n"
                    }
                }
                let trimmed = pText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    lines.append(trimmed)
                }
            }
        }
        let result = lines.joined(separator: "\n")
        return result.isEmpty ? nil : result
    }

    // MARK: - XML DOM Convenience

    private func childElement(named localName: String, in parent: XMLElement) -> XMLElement? {
        return parent.children?.first(where: { ($0 as? XMLElement)?.localName == localName }) as? XMLElement
    }

    private func attributeValue(named localName: String, in element: XMLElement) -> String? {
        if let direct = element.attribute(forName: localName)?.stringValue {
            return direct
        }
        return element.attributes?.first(where: { $0.localName == localName })?.stringValue
    }
}
