import AppKit
import QuartzCore
import AVFoundation

public final class AudiencePresentationView: NSView, AudienceRenderDelegate {
    private let rootLayer = CALayer()
    private let slotALayer = CALayer()
    private let slotBLayer = CALayer()
    private let blackoutLayer = CALayer()

    // Video/Audio Layer
    private var playerLayer: AVPlayerLayer?

    private var isSlotAActive = true

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupLayers()
        engineDidReloadDeck()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayers()
        engineDidReloadDeck()
    }

    private func setupLayers() {
        self.wantsLayer = true
        self.layer = rootLayer
        rootLayer.backgroundColor = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        rootLayer.masksToBounds = true

        // Configure presentation buffer layers
        [slotALayer, slotBLayer].forEach { layer in
            layer.frame = bounds
            layer.contentsGravity = .resizeAspect
            // Disable default implicit layer actions for deterministic manual timing
            layer.actions = [
                "opacity": NSNull(),
                "transform": NSNull(),
                "contents": NSNull(),
                "position": NSNull(),
                "bounds": NSNull()
            ]
            rootLayer.addSublayer(layer)
        }
        slotALayer.opacity = 1.0
        slotBLayer.opacity = 0.0

        // Top-most Blackout Overlay
        blackoutLayer.frame = bounds
        blackoutLayer.backgroundColor = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        blackoutLayer.opacity = 0.0
        blackoutLayer.zPosition = 9999
        blackoutLayer.actions = [
            "opacity": NSNull(),
            "position": NSNull(),
            "bounds": NSNull()
        ]
        rootLayer.addSublayer(blackoutLayer)
    }

    public override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        slotALayer.frame = bounds
        slotBLayer.frame = bounds
        blackoutLayer.frame = bounds
        playerLayer?.frame = bounds
        CATransaction.commit()
    }

    // MARK: - AudienceRenderDelegate Protocol

    public func performTransition(from: SlideItem?, to: SlideItem, type: TransitionType) {
        let incomingLayer = isSlotAActive ? slotBLayer : slotALayer
        let outgoingLayer = isSlotAActive ? slotALayer : slotBLayer

        // Load new slide content into incoming layer
        incomingLayer.contents = to.visualRepresentation

        // Setup or clean up video playback
        if to.mediaURL != nil {
            setupMedia(hostLayer: incomingLayer)
        } else {
            teardownMedia()
        }

        CATransaction.begin()
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))

        switch type {
        case .cut:
            CATransaction.setDisableActions(true)
            incomingLayer.opacity = 1.0
            incomingLayer.transform = CATransform3DIdentity
            outgoingLayer.opacity = 0.0
            outgoingLayer.transform = CATransform3DIdentity

        case .crossfade(let duration):
            CATransaction.setAnimationDuration(duration)
            
            let fadeIn = CABasicAnimation(keyPath: "opacity")
            fadeIn.fromValue = 0.0
            fadeIn.toValue = 1.0
            fadeIn.duration = duration
            incomingLayer.add(fadeIn, forKey: "crossFadeIn")
            incomingLayer.opacity = 1.0

            let fadeOut = CABasicAnimation(keyPath: "opacity")
            fadeOut.fromValue = 1.0
            fadeOut.toValue = 0.0
            fadeOut.duration = duration
            outgoingLayer.add(fadeOut, forKey: "crossFadeOut")
            outgoingLayer.opacity = 0.0

        case .push(let direction, let duration):
            CATransaction.setAnimationDuration(duration)
            let width = bounds.width
            let height = bounds.height

            var translationX: CGFloat = 0
            var translationY: CGFloat = 0

            switch direction {
            case .left: translationX = width
            case .right: translationX = -width
            case .up: translationY = -height
            case .down: translationY = height
            }

            let slideIn = CABasicAnimation(keyPath: "transform")
            slideIn.fromValue = CATransform3DMakeTranslation(translationX, translationY, 0)
            slideIn.toValue = CATransform3DIdentity
            slideIn.duration = duration
            incomingLayer.add(slideIn, forKey: "pushIn")
            incomingLayer.opacity = 1.0

            let slideOut = CABasicAnimation(keyPath: "transform")
            slideOut.fromValue = CATransform3DIdentity
            slideOut.toValue = CATransform3DMakeTranslation(-translationX, -translationY, 0)
            slideOut.duration = duration
            outgoingLayer.add(slideOut, forKey: "pushOut")
            outgoingLayer.opacity = 0.0

        case .zoom(let scale, let duration):
            CATransaction.setAnimationDuration(duration)
            incomingLayer.opacity = 1.0

            let zoomAnim = CABasicAnimation(keyPath: "transform.scale")
            zoomAnim.fromValue = scale
            zoomAnim.toValue = 1.0
            zoomAnim.duration = duration
            incomingLayer.add(zoomAnim, forKey: "zoom")

            let fadeOut = CABasicAnimation(keyPath: "opacity")
            fadeOut.fromValue = 1.0
            fadeOut.toValue = 0.0
            fadeOut.duration = duration
            outgoingLayer.add(fadeOut, forKey: "zoomFadeOut")
            outgoingLayer.opacity = 0.0
        }

        CATransaction.commit()
        isSlotAActive.toggle()
    }

    public func setBlackout(_ active: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true) // Instant cut, 0 animation delay
        blackoutLayer.opacity = active ? 1.0 : 0.0
        CATransaction.commit()
    }

    public func setMediaMuted(_ muted: Bool) {
        // Engine handles activePlayer muting directly
    }

    public func engineDidReloadDeck() {
        guard let firstSlide = PresentationEngine.shared.currentSlide else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        slotALayer.contents = firstSlide.visualRepresentation
        slotALayer.opacity = 1.0
        slotBLayer.opacity = 0.0
        isSlotAActive = true
        if firstSlide.mediaURL != nil {
            setupMedia(hostLayer: slotALayer)
        } else {
            teardownMedia()
        }
        CATransaction.commit()
    }

    private func setupMedia(hostLayer: CALayer) {
        teardownMedia()
        guard let player = PresentationEngine.shared.activePlayer else { return }
        let pLayer = AVPlayerLayer(player: player)
        pLayer.frame = bounds
        pLayer.videoGravity = .resizeAspect
        hostLayer.addSublayer(pLayer)
        self.playerLayer = pLayer
    }

    private func teardownMedia() {
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
    }
}
