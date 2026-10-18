import AppKit
import PDFKit
import QuickLookThumbnailing

@MainActor
public final class DeckLoader {
    public static let shared = DeckLoader()

    public func loadDeck(from url: URL, preferNativeRenderer: Bool = false) async throws -> (title: String, slides: [SlideItem]) {
        let ext = url.pathExtension.lowercased()
        let filename = url.deletingPathExtension().lastPathComponent

        if ext == "pdf" {
            let slides = try loadPDFDeck(from: url)
            return (filename, slides)
        } else if ext == "pptx" || ext == "ppt" {
            let slides = try await loadPowerPointDeck(from: url, preferNativeRenderer: preferNativeRenderer)
            return (filename, slides)
        } else {
            let slides = try await loadNativeOrFallbackDeck(from: url)
            return (filename, slides)
        }
    }

    // MARK: - Hybrid OpenXML + PowerPoint Ingestion Pipeline

    private func loadPowerPointDeck(from url: URL, preferNativeRenderer: Bool) async throws -> [SlideItem] {
        // Step 1: Parse PPTX OpenXML structure (extracts all text boxes, runs, colors, embedded video/audio, and images)
        let metadataMap = (try? PPTXPackageParser.shared.extractAndParse(pptxURL: url)) ?? [:]

        // Step 2: If PowerPoint is installed and not forced to native-only, render 100% faithful original backgrounds & layouts
        if !preferNativeRenderer && isPowerPointInstalled() {
            let uniqueID = UUID().uuidString.prefix(8)
            let asciiSourcePPTX = URL(fileURLWithPath: "/tmp/pp_src_\(uniqueID).pptx")
            let tempPDF = URL(fileURLWithPath: "/tmp/pp_out_\(uniqueID).pdf")
            let tempPNGFolder = URL(fileURLWithPath: "/tmp/pp_img_\(uniqueID)")

            defer {
                try? FileManager.default.removeItem(at: asciiSourcePPTX)
                try? FileManager.default.removeItem(at: tempPDF)
                try? FileManager.default.removeItem(at: tempPNGFolder)
            }

            try? FileManager.default.copyItem(at: url, to: asciiSourcePPTX)
            let targetSource = FileManager.default.fileExists(atPath: asciiSourcePPTX.path) ? asciiSourcePPTX : url

            await ensurePowerPointRunning()

            // Method A: Export to multi-page PDF via background osascript with timeout
            let didExportPDF = await Task.detached(priority: .userInitiated) {
                Self.runPowerPointPDFExport(pptxPath: targetSource.path, pdfPath: tempPDF.path)
            }.value

            if didExportPDF, let document = PDFDocument(url: tempPDF), document.pageCount > 0 {
                var slides: [SlideItem] = []
                let pageCount = document.pageCount

                for i in 0..<pageCount {
                    guard let page = document.page(at: i) else { continue }
                    let pageRect = page.bounds(for: .mediaBox)
                    let scale: CGFloat = 2.0
                    let targetSize = CGSize(width: pageRect.width * scale, height: pageRect.height * scale)
                    let pdfImage = page.thumbnail(of: targetSize, for: .mediaBox)
                        .cgImage(forProposedRect: nil, context: nil, hints: nil)

                    let meta = metadataMap[i]
                    let slideTitle = meta?.title ?? "Slide \(i + 1)"
                    let notes = meta?.notes
                    let namedElements = meta?.namedElements ?? [:]
                    let elements = meta?.elements ?? []
                    var background = meta?.background ?? SlideBackground()
                    if background.backgroundImageURL == nil, let firstMedia = meta?.mediaFiles.first {
                        let ext = firstMedia.pathExtension.lowercased()
                        if ["png", "jpg", "jpeg", "webp", "tiff", "bmp"].contains(ext) {
                            background.backgroundImageURL = firstMedia
                        }
                    }

                    let finalImage = pdfImage ?? NativeSlideRenderer.shared.renderSlide(
                        index: i,
                        total: pageCount,
                        title: slideTitle,
                        elements: elements,
                        background: background,
                        namedElements: namedElements,
                        fallbackMediaURL: meta?.mediaFiles.first
                    )

                    slides.append(
                        SlideItem(
                            index: i,
                            title: slideTitle,
                            visualRepresentation: finalImage,
                            mediaURL: meta?.videoFile,
                            notes: notes,
                            namedElements: namedElements,
                            elements: elements,
                            background: background
                        )
                    )
                }

                if slides.count > 1 || (slides.count == 1 && metadataMap.count <= 1) {
                    return slides
                }
            }

            // Method B: Export to PNG slide folder via background osascript
            let didExportPNG = await Task.detached(priority: .userInitiated) {
                Self.runPowerPointPNGExport(pptxPath: targetSource.path, folderPath: tempPNGFolder.path)
            }.value

            if didExportPNG, let imageSlides = loadSlidesFromPNGFolder(folderURL: tempPNGFolder, metadataMap: metadataMap) {
                if imageSlides.count > 1 || (imageSlides.count == 1 && metadataMap.count <= 1) {
                    return imageSlides
                }
            }
        }

        // Step 3: Native OpenXML Renderer for ALL slides (1..N) with full backgrounds, embedded images, and styled text
        return try await loadNativeOrFallbackDeck(from: url, metadataMap: metadataMap)
    }

    private func isPowerPointInstalled() -> Bool {
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.microsoft.Powerpoint") != nil
    }

    private func ensurePowerPointRunning() async {
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.microsoft.Powerpoint")
        if runningApps.isEmpty {
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.microsoft.Powerpoint") {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = false
                config.hides = true
                _ = try? await NSWorkspace.shared.openApplication(at: appURL, configuration: config)
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    nonisolated private static func runPowerPointPDFExport(pptxPath: String, pdfPath: String) -> Bool {
        let script = """
        tell application "Microsoft PowerPoint"
            try
                set pptxHFS to (POSIX file "\(pptxPath)") as string
                set pdfHFS to (POSIX file "\(pdfPath)") as string
                
                open (POSIX file "\(pptxPath)")
                
                repeat 35 times
                    try
                        if (exists active presentation) then
                            if (count of slides of active presentation) > 0 then exit repeat
                        end if
                    end try
                    delay 0.2
                end repeat
                delay 0.3
                
                save active presentation in pdfHFS as save as PDF
                
                try
                    close active presentation saving no
                end try
                return true
            on error
                try
                    close active presentation saving no
                end try
                return false
            end try
        end tell
        """
        _ = runOsascriptWithTimeout(script: script, timeoutSeconds: 12.0)
        return FileManager.default.fileExists(atPath: pdfPath)
    }

    nonisolated private static func runPowerPointPNGExport(pptxPath: String, folderPath: String) -> Bool {
        try? FileManager.default.createDirectory(atPath: folderPath, withIntermediateDirectories: true)
        let script = """
        tell application "Microsoft PowerPoint"
            try
                set pptxHFS to (POSIX file "\(pptxPath)") as string
                set folderHFS to (POSIX file "\(folderPath)") as string
                
                open (POSIX file "\(pptxPath)")
                
                repeat 35 times
                    try
                        if (exists active presentation) then
                            if (count of slides of active presentation) > 0 then exit repeat
                        end if
                    end try
                    delay 0.2
                end repeat
                delay 0.3
                
                save active presentation in folderHFS as save as PNG
                
                try
                    close active presentation saving no
                end try
                return true
            on error
                try
                    close active presentation saving no
                end try
                return false
            end try
        end tell
        """
        _ = runOsascriptWithTimeout(script: script, timeoutSeconds: 12.0)
        if let files = try? FileManager.default.contentsOfDirectory(atPath: folderPath),
           files.contains(where: { $0.lowercased().hasSuffix(".png") || $0.lowercased().hasSuffix(".jpg") }) {
            return true
        }
        return false
    }

    nonisolated private static func runOsascriptWithTimeout(script: String, timeoutSeconds: TimeInterval) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return false
        }

        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }

        if process.isRunning {
            process.terminate()
            return false
        }
        return process.terminationStatus == 0
    }

    private func loadSlidesFromPNGFolder(folderURL: URL, metadataMap: [Int: PPTXSlideMetadata]) -> [SlideItem]? {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: folderURL.path) else { return nil }
        let imageFiles = files
            .filter { $0.lowercased().hasSuffix(".png") || $0.lowercased().hasSuffix(".jpg") || $0.lowercased().hasSuffix(".jpeg") }
            .sorted { a, b in
                a.localizedStandardCompare(b) == .orderedAscending
            }

        guard !imageFiles.isEmpty else { return nil }

        var slides: [SlideItem] = []
        for (index, file) in imageFiles.enumerated() {
            let fileURL = folderURL.appendingPathComponent(file)
            guard let nsImage = NSImage(contentsOf: fileURL),
                  let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                continue
            }

            let meta = metadataMap[index]
            let slideTitle = meta?.title ?? "Slide \(index + 1)"
            let notes = meta?.notes
            let namedElements = meta?.namedElements ?? [:]
            let elements = meta?.elements ?? []
            var background = meta?.background ?? SlideBackground()
            if background.backgroundImageURL == nil, let firstMedia = meta?.mediaFiles.first {
                let ext = firstMedia.pathExtension.lowercased()
                if ["png", "jpg", "jpeg", "webp", "tiff", "bmp"].contains(ext) {
                    background.backgroundImageURL = firstMedia
                }
            }

            slides.append(
                SlideItem(
                    index: index,
                    title: slideTitle,
                    visualRepresentation: cgImage,
                    mediaURL: meta?.videoFile,
                    notes: notes,
                    namedElements: namedElements,
                    elements: elements,
                    background: background
                )
            )
        }

        return slides.isEmpty ? nil : slides
    }

    // MARK: - PDF Import

    private func loadPDFDeck(from url: URL) throws -> [SlideItem] {
        guard let document = PDFDocument(url: url) else {
            throw NSError(domain: "DeckLoader", code: 404, userInfo: [NSLocalizedDescriptionKey: "Failed to open PDF document."])
        }

        var slides: [SlideItem] = []
        let pageCount = document.pageCount

        for i in 0..<pageCount {
            guard let page = document.page(at: i) else { continue }
            let pageRect = page.bounds(for: .mediaBox)
            let scale: CGFloat = 2.0
            let targetSize = CGSize(width: pageRect.width * scale, height: pageRect.height * scale)
            let image = page.thumbnail(of: targetSize, for: .mediaBox)
                .cgImage(forProposedRect: nil, context: nil, hints: nil)

            let extractedPageText = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let firstLine = extractedPageText.components(separatedBy: .newlines).first ?? "Slide \(i + 1)"
            let title = firstLine.isEmpty ? "Slide \(i + 1)" : firstLine

            slides.append(
                SlideItem(
                    index: i,
                    title: title,
                    visualRepresentation: image,
                    mediaURL: nil,
                    notes: extractedPageText.isEmpty ? "Imported from PDF: Page \(i + 1)" : extractedPageText,
                    namedElements: [
                        "title": title,
                        "something": extractedPageText.isEmpty ? title : extractedPageText,
                        "page": "\(i + 1)"
                    ]
                )
            )
        }

        return slides
    }

    // MARK: - Native OpenXML & Fallback Deck Builder

    private func loadNativeOrFallbackDeck(from url: URL, metadataMap: [Int: PPTXSlideMetadata] = [:]) async throws -> [SlideItem] {
        if metadataMap.isEmpty {
            let generator = QLThumbnailGenerator.shared
            let request = QLThumbnailGenerator.Request(
                fileAt: url,
                size: CGSize(width: 1920, height: 1080),
                scale: 1.0,
                representationTypes: .thumbnail
            )
            let thumbnail = try? await generator.generateBestRepresentation(for: request)
            return [
                SlideItem(
                    index: 0,
                    title: url.deletingPathExtension().lastPathComponent,
                    visualRepresentation: thumbnail?.cgImage,
                    mediaURL: nil,
                    notes: "Imported Presentation",
                    namedElements: [:]
                )
            ]
        }

        let totalSlides = metadataMap.count
        var slides: [SlideItem] = []

        for i in 0..<totalSlides {
            let meta = metadataMap[i]
            let rawTitle = meta?.title ?? ""
            let title = rawTitle.isEmpty ? "Slide \(i + 1)" : rawTitle
            let notes = meta?.notes
            let namedElements = meta?.namedElements ?? [:]
            let elements = meta?.elements ?? []
            var background = meta?.background ?? SlideBackground()
            if background.backgroundImageURL == nil, let firstMedia = meta?.mediaFiles.first {
                let ext = firstMedia.pathExtension.lowercased()
                if ["png", "jpg", "jpeg", "webp", "tiff", "bmp"].contains(ext) {
                    background.backgroundImageURL = firstMedia
                }
            }

            // Render every slide natively using extracted OpenXML background, pictures, shapes, and text
            let renderedImage = NativeSlideRenderer.shared.renderSlide(
                index: i,
                total: totalSlides,
                title: title,
                elements: elements,
                background: background,
                namedElements: namedElements,
                fallbackMediaURL: meta?.mediaFiles.first
            )

            slides.append(
                SlideItem(
                    index: i,
                    title: title,
                    visualRepresentation: renderedImage,
                    mediaURL: meta?.videoFile,
                    notes: notes,
                    namedElements: namedElements,
                    elements: elements,
                    background: background
                )
            )
        }

        return slides
    }
}
