import SwiftUI

public struct EmergencyControlsBar: View {
    @ObservedObject var engine: PresentationEngine
    @ObservedObject var screens: ScreenCoordinator

    public init(engine: PresentationEngine, screens: ScreenCoordinator) {
        self.engine = engine
        self.screens = screens
    }

    public var body: some View {
        VStack(spacing: 10) {
            // Transport row (Previous / Next)
            HStack(spacing: 12) {
                Button(action: { engine.previous() }) {
                    Label("PREV", systemImage: "backward.fill")
                        .font(.system(size: 13, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.leftArrow, modifiers: [])
                .disabled(engine.currentSlideIndex <= 0)

                Button(action: { engine.next() }) {
                    Label("NEXT", systemImage: "forward.fill")
                        .font(.system(size: 13, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
                .keyboardShortcut(.rightArrow, modifiers: [])
                .disabled(engine.currentSlideIndex >= engine.slides.count - 1)
            }

            // Emergency Cut Row (Blackout & Media Mute)
            HStack(spacing: 12) {
                Button(action: { engine.toggleBlackout() }) {
                    HStack {
                        Image(systemName: engine.isBlackoutActive ? "eye.fill" : "eye.slash.fill")
                        Text(engine.isBlackoutActive ? "RESTORE OUTPUT" : "BLACKOUT")
                            .fontWeight(.heavy)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(engine.isBlackoutActive ? .green : .red)
                .keyboardShortcut("b", modifiers: [.command])

                Button(action: { engine.clearMedia() }) {
                    HStack {
                        Image(systemName: engine.isMediaCleared ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        Text(engine.isMediaCleared ? "UNMUTE MEDIA" : "CLEAR MEDIA")
                            .fontWeight(.bold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .tint(engine.isMediaCleared ? .orange : .secondary)
                .keyboardShortcut("m", modifiers: [.command])
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
        .cornerRadius(8)
    }
}
