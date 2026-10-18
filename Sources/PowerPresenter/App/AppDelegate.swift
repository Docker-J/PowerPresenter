import AppKit

public final class AppDelegate: NSObject, NSApplicationDelegate {
    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)

        // Clean up any stale PPTX session caches from previous runs
        PPTXPackageParser.shared.cleanupOldCaches()

        // Initialize screens & demo deck on launch
        _ = ScreenCoordinator.shared

        // Global Presentation Navigation Keys (Right/Left Arrow, Down/Up Arrow, Space)
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Check if user is currently typing in a text field or text view
            if let firstResponder = NSApp.keyWindow?.firstResponder {
                if firstResponder is NSText || firstResponder is NSTextView || firstResponder is NSTextField {
                    return event
                }
            }

            // Check if any modal sheet (like SlideEditor, MIDI Settings, etc.) is open
            if NSApp.keyWindow?.sheetParent != nil || NSApp.keyWindow?.attachedSheet != nil {
                return event
            }

            switch event.keyCode {
            case 124, 125: // Right Arrow, Down Arrow -> Next Slide
                Task { @MainActor in
                    PresentationEngine.shared.next()
                }
                return nil

            case 123, 126: // Left Arrow, Up Arrow -> Previous Slide
                Task { @MainActor in
                    PresentationEngine.shared.previous()
                }
                return nil

            case 49: // Spacebar -> Next Slide
                Task { @MainActor in
                    PresentationEngine.shared.next()
                }
                return nil

            default:
                return event
            }
        }

        // If launched with a file path or test flag, load it directly
        let args = CommandLine.arguments
        if args.contains("--test-dump"), let fileIdx = args.firstIndex(of: "--test-dump"), fileIdx + 1 < args.count {
            let path = args[fileIdx + 1]
            let url = URL(fileURLWithPath: path)
            Task { @MainActor in
                do {
                    let result = try await DeckLoader.shared.loadDeck(from: url)
                    print("✅ DECK DUMP SUCCESS")
                    print("Deck Title: \(result.title)")
                    print("Total Slides: \(result.slides.count)")
                    for slide in result.slides {
                        if slide.hasMedia {
                            print("🎬 Media Slide #\(slide.index + 1): \(slide.mediaURL?.lastPathComponent ?? "nil"), isVideo: \(slide.isVideoMedia), isAudio: \(slide.isAudioMedia)")
                        }
                    }
                    let testIndices = [1, 4, 8, 9, 23]
                    for idx in testIndices where idx < result.slides.count {
                        let s = result.slides[idx]
                        print("--- Slide #\(idx + 1) [\(s.title)] ---")
                        print("Stage Text: \(s.primaryStageText.replacingOccurrences(of: "\n", with: " / "))")
                        if let sec = s.secondaryStageText {
                            print("Secondary: \(sec.replacingOccurrences(of: "\n", with: " / "))")
                        }
                    }
                    exit(0)
                } catch {
                    print("❌ Error loading deck: \(error)")
                    exit(1)
                }
            }
            return
        }

        if args.count > 1 && !args[1].hasPrefix("-") {
            let url = URL(fileURLWithPath: args[1])
            if FileManager.default.fileExists(atPath: url.path) {
                Task { @MainActor in
                    if let result = try? await DeckLoader.shared.loadDeck(from: url) {
                        PresentationEngine.shared.loadDeck(title: result.title, slides: result.slides)
                    }
                }
                return
            }
        }

        let demoSlides = SampleDeckBuilder.buildDemoDeck()
        PresentationEngine.shared.loadDeck(title: "PowerPresenter Demo Deck", slides: demoSlides)
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
