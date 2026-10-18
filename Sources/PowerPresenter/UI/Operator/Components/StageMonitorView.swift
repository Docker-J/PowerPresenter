import SwiftUI
import AVKit

public struct StageMonitorView: View {
    let title: String
    let subtitle: String?
    let slide: SlideItem?
    let borderColor: Color
    let badgeText: String?
    let badgeColor: Color
    let isBlackedOut: Bool

    @ObservedObject private var engine = PresentationEngine.shared

    public init(
        title: String,
        subtitle: String? = nil,
        slide: SlideItem?,
        borderColor: Color,
        badgeText: String? = nil,
        badgeColor: Color = .red,
        isBlackedOut: Bool = false
    ) {
        self.title = title
        self.subtitle = subtitle
        self.slide = slide
        self.borderColor = borderColor
        self.badgeText = badgeText
        self.badgeColor = badgeColor
        self.isBlackedOut = isBlackedOut
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                
                Spacer()

                if let slide = slide, slide.hasMedia {
                    HStack(spacing: 4) {
                        Image(systemName: slide.isVideoMedia ? "video.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 8))
                        Text(slide.isVideoMedia ? "VIDEO" : "AUDIO")
                            .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.purple.opacity(0.85))
                    .foregroundColor(.white)
                    .cornerRadius(4)
                }

                if let badge = badgeText {
                    Text(badge)
                        .font(.system(size: 10, weight: .heavy, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(badgeColor.opacity(0.2))
                        .foregroundColor(badgeColor)
                        .cornerRadius(4)
                }
            }

            LiveSlideVisualView(
                slide: slide,
                isCurrent: true,
                isBlackedOut: isBlackedOut,
                showMediaBadge: false
            )
            .aspectRatio(16/9, contentMode: .fit)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(borderColor, lineWidth: 2)
            )

            // Media Transport Bar for Video/Audio Slides
            if let slide = slide, slide.hasMedia && engine.activePlayer != nil {
                HStack(spacing: 8) {
                    Button(action: {
                        engine.toggleMediaPlayback()
                    }) {
                        Image(systemName: engine.isMediaPlaying ? "pause.fill" : "play.fill")
                            .font(.caption.bold())
                            .foregroundColor(.primary)
                    }
                    .buttonStyle(.plain)

                    Slider(
                        value: Binding(
                            get: { engine.mediaCurrentTime },
                            set: { engine.seekMedia(to: $0) }
                        ),
                        in: 0...max(1.0, engine.mediaDuration)
                    )
                    .controlSize(.mini)

                    Text(formattedMediaTime(current: engine.mediaCurrentTime, total: engine.mediaDuration))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 4)
                .padding(.top, 2)
            }

            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func formattedMediaTime(current: Double, total: Double) -> String {
        let curMin = Int(current) / 60
        let curSec = Int(current) % 60
        let totMin = Int(total) / 60
        let totSec = Int(total) % 60
        return String(format: "%02d:%02d / %02d:%02d", curMin, curSec, totMin, totSec)
    }
}
