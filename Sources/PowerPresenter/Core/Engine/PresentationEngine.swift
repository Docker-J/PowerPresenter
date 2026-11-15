import Foundation
import Combine
import CoreGraphics
import AVFoundation

@MainActor
public final class PresentationEngine: ObservableObject {
    public static let shared = PresentationEngine()

    @Published public private(set) var deckTitle: String = "Untitled Deck"
    @Published public private(set) var slides: [SlideItem] = []
    @Published public private(set) var currentSlideIndex: Int = 0
    @Published public private(set) var isBlackoutActive: Bool = false
    @Published public private(set) var isMediaCleared: Bool = false
    @Published public var defaultTransition: TransitionType = .crossfade(duration: 0.35)
    @Published public var isLoadingDeck: Bool = false

    // Media Playback State
    @Published public private(set) var activePlayer: AVPlayer?
    @Published public private(set) var isMediaPlaying: Bool = false
    @Published public private(set) var mediaCurrentTime: Double = 0.0
    @Published public private(set) var mediaDuration: Double = 0.0
    private var timeObserverToken: Any?

    // Stage Display / Confidence Monitor State & Presets
    @Published public var stageAlertMessage: String = ""
    @Published public var stagePresets: [StageLayoutPreset] = StageLayoutPreset.defaultPresets
    @Published public var activeStagePresetID: UUID = StageLayoutPreset.presetLyricsID
    @Published public var stageLayout: StageLayoutConfig = StageLayoutPreset.defaultPresets[0].config {
        didSet {
            syncActivePresetWithCurrentLayout()
        }
    }

    @Published public private(set) var timerElapsedSeconds: Int = 0
    @Published public private(set) var isTimerRunning: Bool = false
    private var timerCancellable: AnyCancellable?
    private var isUpdatingPresetInternally = false

    private let presetsStorageKey = "PowerPresenter.StageLayoutPresets.v4"

    // Direct synchronous delegate for audience display
    public weak var audienceRenderer: AudienceRenderDelegate?

    public var currentSlide: SlideItem? {
        guard slides.indices.contains(currentSlideIndex) else { return nil }
        return slides[currentSlideIndex]
    }

    public var nextSlide: SlideItem? {
        let nextIdx = currentSlideIndex + 1
        guard slides.indices.contains(nextIdx) else { return nil }
        return slides[nextIdx]
    }

    public var activeStagePreset: StageLayoutPreset? {
        stagePresets.first(where: { $0.id == activeStagePresetID })
    }

    // Returns all distinct text box / element names found across the current presentation deck
    public var allKnownNamedElements: [String] {
        var names = Set<String>(["something", "title", "subtitle", "speaker", "lyrics"])
        for slide in slides {
            for key in slide.namedElements.keys {
                let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    names.insert(trimmed)
                }
            }
            for elem in slide.elements where elem.kind == .text {
                let trimmed = elem.name.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    names.insert(trimmed)
                }
            }
        }
        return Array(names).sorted()
    }

    public init() {
        loadSavedPresets()
    }

    // MARK: - Deck Loading & Navigation

    public func loadDeck(title: String, slides: [SlideItem]) {
        self.deckTitle = title
        self.slides = slides
        self.currentSlideIndex = 0
        self.isBlackoutActive = false
        self.isMediaCleared = false

        // Trigger slide 0's Stage Layout Preset Cue if assigned
        if let firstSlide = slides.first, let presetID = firstSlide.stageLayoutPresetID {
            applyStagePreset(id: presetID)
        }

        configureMediaForActiveSlide()
        audienceRenderer?.engineDidReloadDeck()
    }

    public func navigateTo(index: Int, transition: TransitionType? = nil) {
        guard slides.indices.contains(index) else { return }

        let targetSlide = slides[index]

        // Automatically switch Stage Layout Preset if this slide has a Stage Layout Cue assigned
        if let presetID = targetSlide.stageLayoutPresetID {
            applyStagePreset(id: presetID)
        } else if let secID = targetSlide.serviceSectionID,
                  let sec = ServiceFlowManager.shared.section(for: secID),
                  let defaultPresetID = sec.defaultStagePresetID,
                  activeStagePresetID != defaultPresetID {
            // Safety fallback: if jumping directly into the middle of a section, ensure section's default stage layout is active
            applyStagePreset(id: defaultPresetID)
        }

        // Automatically fire MIDI Cue if this slide has a MIDI Cue assigned
        if let midiCue = targetSlide.midiCue {
            MIDIManager.shared.send(cue: midiCue)
        }

        guard index != currentSlideIndex else { return }

        let effectiveTransition = transition ?? defaultTransition
        let fromSlide = currentSlide

        self.currentSlideIndex = index

        // Setup media for the target slide
        configureMediaForActiveSlide()

        // Immediate synchronous layer update (<0.1ms dispatch)
        audienceRenderer?.performTransition(
            from: fromSlide,
            to: targetSlide,
            type: effectiveTransition
        )
    }

    public func next() {
        if currentSlideIndex < slides.count - 1 {
            navigateTo(index: currentSlideIndex + 1)
        }
    }

    public func previous() {
        if currentSlideIndex > 0 {
            navigateTo(index: currentSlideIndex - 1)
        }
    }

    // MARK: - Video & Audio Media Controls

    private func configureMediaForActiveSlide() {
        cleanupCurrentMedia()

        guard let slide = currentSlide, let mediaURL = slide.mediaURL else {
            return
        }

        let asset = AVURLAsset(url: mediaURL)
        let playerItem = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: playerItem)
        player.isMuted = isMediaCleared
        AudioOutputManager.shared.configurePlayer(player)

        self.activePlayer = player
        self.mediaDuration = 0.0
        self.mediaCurrentTime = 0.0

        // Async load duration
        Task { [weak self] in
            if let duration = try? await asset.load(.duration) {
                let seconds = CMTimeGetSeconds(duration)
                if seconds.isFinite && !seconds.isNaN {
                    self?.mediaDuration = seconds
                }
            }
        }

        // Periodic time observer for real-time scrubber and transport timer
        let interval = CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            let secs = CMTimeGetSeconds(time)
            if secs.isFinite && !secs.isNaN {
                Task { @MainActor [weak self] in
                    self?.mediaCurrentTime = secs
                }
            }
        }

        // Start playback automatically on slide entry
        player.play()
        self.isMediaPlaying = true
    }

    private func cleanupCurrentMedia() {
        if let token = timeObserverToken, let player = activePlayer {
            player.removeTimeObserver(token)
            timeObserverToken = nil
        }
        activePlayer?.pause()
        activePlayer?.replaceCurrentItem(with: nil)
        activePlayer = nil
        isMediaPlaying = false
        mediaCurrentTime = 0.0
        mediaDuration = 0.0
    }

    public func toggleMediaPlayback() {
        guard let player = activePlayer else { return }
        if isMediaPlaying {
            player.pause()
            isMediaPlaying = false
        } else {
            player.play()
            isMediaPlaying = true
        }
    }

    public func playMedia() {
        guard let player = activePlayer else { return }
        player.play()
        isMediaPlaying = true
    }

    public func pauseMedia() {
        guard let player = activePlayer else { return }
        player.pause()
        isMediaPlaying = false
    }

    public func seekMedia(to seconds: Double) {
        guard let player = activePlayer else { return }
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        mediaCurrentTime = seconds
    }

    // MARK: - Stage Layout Preset Management & Per-Slide Cue Assignment

    public func preset(for id: UUID?) -> StageLayoutPreset? {
        guard let id = id else { return nil }
        return stagePresets.first(where: { $0.id == id })
    }

    public func applyStagePreset(id: UUID) {
        guard let found = stagePresets.first(where: { $0.id == id }) else { return }
        guard activeStagePresetID != found.id else { return }
        isUpdatingPresetInternally = true
        activeStagePresetID = found.id
        stageLayout = found.config
        isUpdatingPresetInternally = false
    }

    public func assignStagePreset(_ presetID: UUID?, toSlideAt index: Int) {
        guard slides.indices.contains(index) else { return }
        slides[index].stageLayoutPresetID = presetID

        // If assigning to the currently active live slide, immediately activate that preset on Stage
        if index == currentSlideIndex, let presetID = presetID {
            applyStagePreset(id: presetID)
        }
    }

    public func assignMIDICue(_ cue: MIDICue?, toSlideAt index: Int) {
        guard slides.indices.contains(index) else { return }
        slides[index].midiCue = cue
    }

    /// Assigns a Service Section (e.g. 찬양, 말씀, 광고) to a set of slides.
    /// Following the Section-Head rule:
    /// - Head slide (first in range) gets the section's defaultStagePresetID and triggerMIDICue.
    /// - All slides in range get the section's ID, name, and color badge for visual clarity.
    /// - Non-head slides have duplicate stage and midi cues cleared to prevent redundant triggers.
    public func assignServiceSection(_ section: ServiceSection?, toSlideIndices indices: Set<Int>) {
        guard !indices.isEmpty else { return }
        let sorted = indices.filter { slides.indices.contains($0) }.sorted()
        guard !sorted.isEmpty else { return }

        let headIndex = sorted[0]

        // 1. Assign cues to Head Slide
        if let sec = section {
            slides[headIndex].stageLayoutPresetID = sec.defaultStagePresetID
            slides[headIndex].midiCue = sec.triggerMIDICue
        } else {
            slides[headIndex].stageLayoutPresetID = nil
            slides[headIndex].midiCue = nil
        }

        // 2. Assign section metadata to ALL slides in this range
        for idx in sorted {
            slides[idx].serviceSectionID = section?.id
            slides[idx].serviceSectionName = section?.name
            slides[idx].serviceSectionColorHex = section?.colorHex

            if idx != headIndex && section != nil {
                slides[idx].stageLayoutPresetID = nil
                slides[idx].midiCue = nil
            }
        }

        // If the currently live slide is within this newly assigned section, apply preset
        if sorted.contains(currentSlideIndex), let presetID = section?.defaultStagePresetID {
            applyStagePreset(id: presetID)
        }
    }

    public func assignStagePreset(_ presetID: UUID?, toSlideIndices indices: Set<Int>) {
        guard !indices.isEmpty else { return }
        for idx in indices where slides.indices.contains(idx) {
            slides[idx].stageLayoutPresetID = presetID
        }
        if indices.contains(currentSlideIndex), let presetID = presetID {
            applyStagePreset(id: presetID)
        }
    }

    public func assignMIDICue(_ cue: MIDICue?, toSlideIndices indices: Set<Int>, headOnly: Bool = true) {
        guard !indices.isEmpty else { return }
        let sorted = indices.filter { slides.indices.contains($0) }.sorted()
        if headOnly, let head = sorted.first {
            slides[head].midiCue = cue
        } else {
            for idx in sorted {
                slides[idx].midiCue = cue
            }
        }
    }

    @discardableResult
    public func createStagePreset(name: String, basedOn config: StageLayoutConfig? = nil) -> StageLayoutPreset {
        let newPreset = StageLayoutPreset(
            name: name,
            iconName: "sparkles.rectangle.stack.fill",
            config: config ?? stageLayout
        )
        stagePresets.append(newPreset)
        savePresets()
        applyStagePreset(id: newPreset.id)
        return newPreset
    }

    public func renameStagePreset(id: UUID, newName: String) {
        guard let idx = stagePresets.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        stagePresets[idx].name = trimmed
        savePresets()
    }

    public func deleteStagePreset(id: UUID) {
        guard stagePresets.count > 1 else { return }
        stagePresets.removeAll(where: { $0.id == id })
        // Clear any slide references to deleted preset
        for i in slides.indices where slides[i].stageLayoutPresetID == id {
            slides[i].stageLayoutPresetID = nil
        }
        if activeStagePresetID == id, let first = stagePresets.first {
            applyStagePreset(id: first.id)
        }
        savePresets()
    }

    public func resetPresetsToDefault() {
        stagePresets = StageLayoutPreset.defaultPresets
        savePresets()
        if let first = stagePresets.first {
            applyStagePreset(id: first.id)
        }
    }

    private func syncActivePresetWithCurrentLayout() {
        guard !isUpdatingPresetInternally else { return }
        if let idx = stagePresets.firstIndex(where: { $0.id == activeStagePresetID }) {
            stagePresets[idx].config = stageLayout
            savePresets()
        }
    }

    private func loadSavedPresets() {
        if let data = UserDefaults.standard.data(forKey: presetsStorageKey),
           let decoded = try? JSONDecoder().decode([StageLayoutPreset].self, from: data),
           !decoded.isEmpty {
            self.stagePresets = decoded
            if let first = decoded.first {
                isUpdatingPresetInternally = true
                self.activeStagePresetID = first.id
                self.stageLayout = first.config
                isUpdatingPresetInternally = false
            }
        }
    }

    private func savePresets() {
        if let encoded = try? JSONEncoder().encode(stagePresets) {
            UserDefaults.standard.set(encoded, forKey: presetsStorageKey)
        }
    }

    // MARK: - Live Slide Editing

    public func updateSlide(
        at index: Int,
        title: String,
        notes: String?,
        namedElements: [String: String],
        elements: [SlideElement],
        stageLayoutPresetID: UUID?,
        midiCue: MIDICue? = nil,
        reRenderVisual: Bool = true
    ) {
        guard slides.indices.contains(index) else { return }

        var updated = slides[index]
        updated.title = title
        updated.notes = notes
        updated.namedElements = namedElements
        updated.elements = elements
        updated.stageLayoutPresetID = stageLayoutPresetID
        updated.midiCue = midiCue

        if reRenderVisual {
            if let rendered = NativeSlideRenderer.shared.renderSlide(
                index: index,
                total: slides.count,
                title: title,
                elements: elements,
                background: updated.background,
                namedElements: namedElements,
                fallbackMediaURL: nil,
                baseImage: updated.visualRepresentation
            ) {
                updated.visualRepresentation = rendered
            }
        }

        slides[index] = updated

        if index == currentSlideIndex {
            if let presetID = stageLayoutPresetID {
                applyStagePreset(id: presetID)
            }
            audienceRenderer?.engineDidReloadDeck()
        }
    }

    // MARK: - Emergency Control

    public func toggleBlackout() {
        setBlackout(!isBlackoutActive)
    }

    public func setBlackout(_ active: Bool) {
        isBlackoutActive = active
        if active {
            activePlayer?.pause()
        } else if isMediaPlaying {
            activePlayer?.play()
        }
        audienceRenderer?.setBlackout(active)
    }

    public func clearMedia() {
        isMediaCleared.toggle()
        activePlayer?.isMuted = isMediaCleared
        audienceRenderer?.setMediaMuted(isMediaCleared)
    }

    // MARK: - Stage Timer Management

    public func startTimer() {
        guard !isTimerRunning else { return }
        isTimerRunning = true
        timerCancellable = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self, self.isTimerRunning else { return }
                self.timerElapsedSeconds += 1
            }
    }

    public func pauseTimer() {
        isTimerRunning = false
        timerCancellable?.cancel()
        timerCancellable = nil
    }

    public func resetTimer() {
        pauseTimer()
        timerElapsedSeconds = 0
    }

    public var formattedTimer: String {
        let minutes = timerElapsedSeconds / 60
        let seconds = timerElapsedSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
