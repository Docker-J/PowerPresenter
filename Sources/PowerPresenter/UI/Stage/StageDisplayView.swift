import SwiftUI
import Combine

public struct StageDisplayView: View {
    @ObservedObject var engine: PresentationEngine
    @State private var currentTimeString: String = ""
    private let clockTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    public init(engine: PresentationEngine = .shared) {
        self.engine = engine
    }

    private var themeColor: Color {
        engine.stageLayout.colorTheme.accentColor
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let elements = engine.stageLayout.elements.isEmpty
                    ? StageLayoutConfig.defaultElements(for: engine.stageLayout.style, colorTheme: engine.stageLayout.colorTheme)
                    : engine.stageLayout.elements

                ForEach(elements) { element in
                    if element.isVisible {
                        stageElementView(element, width: w, height: h)
                            .frame(
                                width: max(16, element.rect.width * w),
                                height: max(16, element.rect.height * h)
                            )
                            .position(
                                x: (element.rect.x + element.rect.width / 2.0) * w,
                                y: (element.rect.y + element.rect.height / 2.0) * h
                            )
                    }
                }
            }
            .padding(4)
        }
        .onAppear {
            updateClock()
        }
        .onReceive(clockTimer) { _ in
            updateClock()
        }
    }

    // MARK: - Freeform Element View Renderer

    @ViewBuilder
    private func stageElementView(_ element: StageElement, width: CGFloat, height: CGFloat) -> some View {
        let bgColor = colorFromHex(element.backgroundColorHex, defaultColor: Color(white: 0.08))
        let borderColor = colorFromHex(element.borderColorHex, defaultColor: themeColor)
        let fontColor = colorFromHex(element.fontColorHex, defaultColor: .white)
        let scale = max(0.25, min(1.4, width / 960.0)) // scale font proportionally with screen width
        let scaledFontSize = max(7.0, element.fontSize * scale)
        let cornerRad = max(2.0, 8.0 * scale)
        let borderWidth = max(0.5, element.borderWidth * scale)
        let padH = max(3.0, 10.0 * scale)
        let padV = max(2.0, 6.0 * scale)

        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: cornerRad)
                .fill(bgColor)

            let hAlign: HorizontalAlignment = (element.textAlignment == .left) ? .leading : ((element.textAlignment == .right) ? .trailing : .center)
            let textMultAlign: TextAlignment = (element.textAlignment == .left) ? .leading : ((element.textAlignment == .right) ? .trailing : .center)

            VStack(alignment: hAlign, spacing: max(1, 4 * scale)) {
                // Widget Top Label Header (except for pure text widgets if desired)
                if !element.label.isEmpty {
                    HStack {
                        if element.textAlignment == .right { Spacer() }
                        Text(element.label.uppercased())
                            .font(.system(size: max(6, 11 * scale), weight: .heavy, design: .monospaced))
                            .foregroundColor(borderColor.opacity(0.9))
                        if element.textAlignment == .left { Spacer() }
                    }
                    .padding(.horizontal, padH)
                    .padding(.top, padV)
                }

                // Widget Body Content
                Group {
                    switch element.kind {
                    case .clock:
                        Text(currentTimeString)
                            .font(.system(size: scaledFontSize, weight: .black, design: .monospaced))
                            .foregroundColor(fontColor)

                    case .timer:
                        Text(engine.formattedTimer)
                            .font(.system(size: scaledFontSize, weight: .black, design: .monospaced))
                            .foregroundColor(engine.isTimerRunning ? Color.green : Color.orange)

                    case .slideCounter:
                        Text("\(engine.currentSlideIndex + 1)/\(max(1, engine.slides.count))")
                            .font(.system(size: scaledFontSize, weight: .bold, design: .monospaced))
                            .foregroundColor(fontColor)

                    case .currentSlideText:
                        let text = engine.currentSlide?.primaryStageText ?? ""
                        if engine.isBlackoutActive {
                            Text("BLACKOUT")
                                .font(.system(size: scaledFontSize * 0.9, weight: .black))
                                .foregroundColor(.red)
                        } else if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("(No Text on Slide)")
                                .font(.system(size: max(14, scaledFontSize * 0.5), weight: .medium))
                                .foregroundColor(.gray)
                        } else {
                            Text(text)
                                .font(.system(size: scaledFontSize, weight: .heavy))
                                .foregroundColor(fontColor)
                                .multilineTextAlignment(textMultAlign)
                                .lineSpacing(6 * scale)
                                .minimumScaleFactor(0.35)
                        }

                    case .nextSlideText:
                        let nextText = engine.nextSlide?.primaryStageText ?? (engine.nextSlide != nil ? engine.nextSlide?.title ?? "" : "End of Presentation")
                        Text(nextText.isEmpty ? "End of Presentation" : nextText)
                            .font(.system(size: scaledFontSize, weight: .semibold))
                            .foregroundColor(fontColor)
                            .multilineTextAlignment(textMultAlign)
                            .lineSpacing(4 * scale)
                            .minimumScaleFactor(0.4)

                    case .currentSlideVisual:
                        LiveSlideVisualView(
                            slide: engine.currentSlide,
                            isCurrent: true,
                            isBlackedOut: engine.isBlackoutActive,
                            showMediaBadge: true
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .cornerRadius(4)

                    case .nextSlideVisual:
                        LiveSlideVisualView(
                            slide: engine.nextSlide,
                            isCurrent: false,
                            isBlackedOut: false,
                            showMediaBadge: false
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .cornerRadius(4)

                    case .namedElement:
                        let val = engine.currentSlide?.extractedValue(for: element.targetKey)
                            ?? "(No '\(element.targetKey)' on this slide)"
                        Text(val)
                            .font(.system(size: scaledFontSize, weight: .bold))
                            .foregroundColor(fontColor)
                            .multilineTextAlignment(textMultAlign)
                            .minimumScaleFactor(0.4)

                    case .presenterNotes:
                        ScrollView {
                            Text(engine.currentSlide?.notes ?? "No presenter notes for this slide.")
                                .font(.system(size: scaledFontSize, weight: .medium))
                                .foregroundColor(fontColor.opacity(0.9))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(6)
                        }

                    case .stageAlert:
                        let alert = engine.stageAlertMessage.isEmpty ? "STAGE READY" : engine.stageAlertMessage
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text(alert.uppercased())
                                .font(.system(size: scaledFontSize, weight: .black))
                        }
                        .foregroundColor(engine.stageAlertMessage.isEmpty ? fontColor.opacity(0.4) : .yellow)

                    case .customLabel:
                        Text(element.label)
                            .font(.system(size: scaledFontSize, weight: .bold))
                            .foregroundColor(fontColor)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, padH)
                .padding(.bottom, padV)
            }

            // Outline Border
            RoundedRectangle(cornerRadius: cornerRad)
                .stroke(borderColor, lineWidth: borderWidth)
        }
    }

    private func colorFromHex(_ hex: String, defaultColor: Color) -> Color {
        var cleanHex = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if cleanHex.hasPrefix("#") { cleanHex.removeFirst() }
        guard cleanHex.count == 6, let rgbValue = UInt64(cleanHex, radix: 16) else {
            return defaultColor
        }
        let r = Double((rgbValue & 0xFF0000) >> 16) / 255.0
        let g = Double((rgbValue & 0x00FF00) >> 8) / 255.0
        let b = Double(rgbValue & 0x0000FF) / 255.0
        return Color(red: r, green: g, blue: b)
    }

    private func updateClock() {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm:ss a"
        currentTimeString = formatter.string(from: Date())
    }
}
