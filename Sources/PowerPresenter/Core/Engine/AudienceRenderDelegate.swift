import Foundation

@MainActor
public protocol AudienceRenderDelegate: AnyObject {
    func performTransition(from: SlideItem?, to: SlideItem, type: TransitionType)
    func setBlackout(_ active: Bool)
    func setMediaMuted(_ muted: Bool)
    func engineDidReloadDeck()
}
