import SwiftUI
import AVFoundation
import AppKit

public struct LivePlayerLayerView: NSViewRepresentable {
    public let player: AVPlayer?
    public var videoGravity: AVLayerVideoGravity

    public init(player: AVPlayer?, videoGravity: AVLayerVideoGravity = .resizeAspect) {
        self.player = player
        self.videoGravity = videoGravity
    }

    public func makeNSView(context: Context) -> PlayerLayerNSView {
        let view = PlayerLayerNSView()
        view.configure(player: player, videoGravity: videoGravity)
        return view
    }

    public func updateNSView(_ nsView: PlayerLayerNSView, context: Context) {
        nsView.configure(player: player, videoGravity: videoGravity)
    }

    public static func dismantleNSView(_ nsView: PlayerLayerNSView, coordinator: ()) {
        nsView.configure(player: nil, videoGravity: .resizeAspect)
    }
}

public final class PlayerLayerNSView: NSView {
    private var playerLayer: AVPlayerLayer?

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.wantsLayer = true
        self.layer = CALayer()
        self.layer?.backgroundColor = NSColor.black.cgColor
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.wantsLayer = true
        self.layer = CALayer()
        self.layer?.backgroundColor = NSColor.black.cgColor
    }

    public func configure(player: AVPlayer?, videoGravity: AVLayerVideoGravity) {
        if playerLayer?.player !== player {
            playerLayer?.player = nil
            playerLayer?.removeFromSuperlayer()
            playerLayer = nil

            if let player = player {
                let layer = AVPlayerLayer(player: player)
                layer.videoGravity = videoGravity
                layer.frame = bounds
                layer.actions = [
                    "bounds": NSNull(),
                    "position": NSNull(),
                    "contents": NSNull()
                ]
                self.layer?.addSublayer(layer)
                self.playerLayer = layer
            }
        } else if let playerLayer = playerLayer {
            playerLayer.videoGravity = videoGravity
        }
    }

    public override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer?.frame = bounds
        CATransaction.commit()
    }
}

public struct LiveSlideVisualView: View {
    let slide: SlideItem?
    let isCurrent: Bool
    let isBlackedOut: Bool
    let showMediaBadge: Bool
    @ObservedObject var engine = PresentationEngine.shared

    public init(
        slide: SlideItem?,
        isCurrent: Bool = true,
        isBlackedOut: Bool = false,
        showMediaBadge: Bool = true
    ) {
        self.slide = slide
        self.isCurrent = isCurrent
        self.isBlackedOut = isBlackedOut
        self.showMediaBadge = showMediaBadge
    }

    public var body: some View {
        ZStack {
            Color.black

            if isBlackedOut {
                VStack(spacing: 6) {
                    Image(systemName: "eye.slash.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.red)
                    Text("BLACKOUT")
                        .font(.system(size: 13, weight: .black, design: .monospaced))
                        .foregroundColor(.red)
                }
            } else if isCurrent, let slide = slide, slide.isVideoMedia, let player = engine.activePlayer {
                // Live Playing Video on Stage / Confidence Monitor / Operator View
                ZStack(alignment: .bottomTrailing) {
                    LivePlayerLayerView(player: player)

                    if showMediaBadge {
                        LiveMediaStatusBadge(isAudio: false)
                            .padding(6)
                    }
                }
            } else if isCurrent, let slide = slide, slide.isAudioMedia, let _ = engine.activePlayer {
                // Live Audio Playing
                ZStack {
                    if let img = slide.visualRepresentation {
                        Image(decorative: img, scale: 1.0)
                            .resizable()
                            .aspectRatio(16/9, contentMode: .fit)
                    }
                    if showMediaBadge {
                        LiveMediaStatusBadge(isAudio: true)
                    }
                }
            } else if let slide = slide, let img = slide.visualRepresentation {
                Image(decorative: img, scale: 1.0)
                    .resizable()
                    .aspectRatio(16/9, contentMode: .fit)
            } else {
                VStack(spacing: 4) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.title3)
                        .foregroundColor(.gray)
                    Text(isCurrent ? "No Slide" : "End of Presentation")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
            }
        }
        .aspectRatio(16/9, contentMode: .fit)
    }
}

private struct LiveMediaStatusBadge: View {
    let isAudio: Bool
    @ObservedObject private var mediaState = PresentationEngine.shared.mediaState

    var body: some View {
        HStack(spacing: 5) {
            if isAudio {
                Image(systemName: "waveform")
                    .font(.system(size: 10))
                Text(mediaState.isPlaying ? "AUDIO PLAYING" : "AUDIO PAUSED")
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
            } else {
                Circle()
                    .fill(mediaState.isPlaying ? Color.green : Color.orange)
                    .frame(width: 6, height: 6)
                Text(mediaState.isPlaying ? "LIVE VIDEO" : "PAUSED")
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .foregroundColor(.white)
            }

            if mediaState.duration > 0 {
                let remaining = max(0, mediaState.duration - mediaState.currentTime)
                Text("• \(formattedTime(remaining)) left")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(isAudio ? 1.0 : 0.85))
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(isAudio ? Color.blue.opacity(0.85) : Color.black.opacity(0.75))
        .foregroundColor(.white)
        .cornerRadius(4)
    }

    private func formattedTime(_ seconds: Double) -> String {
        let s = max(0, Int(seconds))
        let m = s / 60
        let remS = s % 60
        return String(format: "%d:%02d", m, remS)
    }
}
