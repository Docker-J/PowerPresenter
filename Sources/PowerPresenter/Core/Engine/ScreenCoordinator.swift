import AppKit
import SwiftUI

public enum MonitorRole: String, CaseIterable, Identifiable, Sendable {
    case none = "Disabled (Operator)"
    case audience = "Audience Output"
    case stage = "Stage Display"

    public var id: String { rawValue }
}

public struct DisplayDescriptor: Identifiable {
    public let id: Int
    public let displayID: CGDirectDisplayID
    public let name: String
    public let resolution: String
    public let isBuiltIn: Bool
    public var role: MonitorRole
}

@MainActor
public final class ScreenCoordinator: ObservableObject {
    public static let shared = ScreenCoordinator()

    @Published public private(set) var connectedScreens: [NSScreen] = []
    @Published public private(set) var screenAssignments: [Int: MonitorRole] = [:]
    @Published public var isAudienceWindowVisible: Bool = false
    @Published public var isStageWindowVisible: Bool = false

    // Multi-display window storage
    // Multiple physical screens can simultaneously serve as Audience Outputs or Stage Displays
    private var audienceWindows: [Int: (window: NSWindow, view: AudiencePresentationView)] = [:]
    private var stageWindows: [Int: NSWindow] = [:]

    // Auxiliary / floating rehearsal windows on the primary display
    private var auxiliaryAudienceWindow: (window: NSWindow, view: AudiencePresentationView)?
    private var auxiliaryStageWindow: NSWindow?

    public var audienceScreenCount: Int {
        screenAssignments.values.filter { $0 == .audience }.count
    }

    public var stageScreenCount: Int {
        screenAssignments.values.filter { $0 == .stage }.count
    }

    private init() {
        // Register ScreenCoordinator as the primary composite Audience renderer
        PresentationEngine.shared.audienceRenderer = self

        refreshScreens(initialLaunch: true)

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshScreens(initialLaunch: false)
            }
        }

        // Safety Escape key handler: pressing ESC closes active fullscreen outputs so operator is never locked out
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // ESC key
                if let self = self, (self.isAudienceWindowVisible || self.isStageWindowVisible) {
                    // Only intercept ESC if no modal sheet is open
                    if NSApp.keyWindow?.sheetParent == nil {
                        self.disarmAllOutputs()
                        return nil
                    }
                }
            }
            return event
        }
    }

    public var displays: [DisplayDescriptor] {
        return connectedScreens.enumerated().map { index, screen in
            let width = Int(screen.frame.width)
            let height = Int(screen.frame.height)
            let name = screen.localizedName.isEmpty ? "Display \(index + 1)" : screen.localizedName
            let assigned = screenAssignments[index] ?? .none
            let screenNumber = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? UInt32(index)
            let isBuiltIn = CGDisplayIsBuiltin(screenNumber) != 0 || index == 0

            return DisplayDescriptor(
                id: index,
                displayID: screenNumber,
                name: name,
                resolution: "\(width) × \(height)",
                isBuiltIn: isBuiltIn,
                role: assigned
            )
        }
    }

    public func refreshScreens(initialLaunch: Bool = false) {
        self.connectedScreens = NSScreen.screens

        if screenAssignments.isEmpty {
            if connectedScreens.count == 1 {
                screenAssignments[0] = MonitorRole.none
            } else if connectedScreens.count == 2 {
                screenAssignments[0] = MonitorRole.none
                screenAssignments[1] = .audience
                if !initialLaunch {
                    attachAudienceToScreen(connectedScreens[1], screenIndex: 1)
                }
            } else if connectedScreens.count >= 3 {
                screenAssignments[0] = MonitorRole.none
                screenAssignments[1] = .audience
                screenAssignments[2] = .stage
                if !initialLaunch {
                    attachAudienceToScreen(connectedScreens[1], screenIndex: 1)
                    attachStageToScreen(connectedScreens[2], screenIndex: 2)
                }
            }
        } else {
            // Remove disconnected screen assignments and destroy their detached windows
            let disconnectedIndices = screenAssignments.keys.filter { $0 >= connectedScreens.count }
            for idx in disconnectedIndices {
                detachAudienceFromScreen(screenIndex: idx)
                detachStageFromScreen(screenIndex: idx)
                screenAssignments.removeValue(forKey: idx)
            }

            // Sync layout for currently active screens
            for (index, role) in screenAssignments {
                if index < connectedScreens.count {
                    if (role == .audience && isAudienceWindowVisible) || (role == .stage && isStageWindowVisible) {
                        applyRole(role, forScreenIndex: index)
                    }
                }
            }
        }
    }

    /// Assigns a role to a connected screen.
    /// Supports multi-screen clustering: multiple screens can be assigned to .audience or .stage simultaneously!
    public func assignRole(_ role: MonitorRole, forScreenIndex index: Int) {
        guard index < connectedScreens.count else { return }
        screenAssignments[index] = role
        applyRole(role, forScreenIndex: index)
    }

    private func applyRole(_ role: MonitorRole, forScreenIndex index: Int) {
        let screen = connectedScreens[index]
        switch role {
        case .none:
            detachAudienceFromScreen(screenIndex: index)
            detachStageFromScreen(screenIndex: index)

        case .audience:
            detachStageFromScreen(screenIndex: index)
            if isAudienceWindowVisible {
                attachAudienceToScreen(screen, screenIndex: index)
            }

        case .stage:
            detachAudienceFromScreen(screenIndex: index)
            if isStageWindowVisible {
                attachStageToScreen(screen, screenIndex: index)
            }
        }
    }

    public func disarmAllOutputs() {
        for (_, entry) in audienceWindows {
            entry.window.orderOut(nil)
        }
        auxiliaryAudienceWindow?.window.orderOut(nil)
        isAudienceWindowVisible = false

        for (_, win) in stageWindows {
            win.orderOut(nil)
        }
        auxiliaryStageWindow?.orderOut(nil)
        isStageWindowVisible = false
    }

    // MARK: - Audience Output (Multi-Display Broadcast)

    public func toggleAudienceWindow() {
        if isAudienceWindowVisible {
            for (_, entry) in audienceWindows {
                entry.window.orderOut(nil)
            }
            auxiliaryAudienceWindow?.window.orderOut(nil)
            isAudienceWindowVisible = false
            return
        }

        let audienceIndices = screenAssignments.filter { $0.value == .audience && $0.key < connectedScreens.count }.map(\.key)
        if !audienceIndices.isEmpty {
            for idx in audienceIndices {
                attachAudienceToScreen(connectedScreens[idx], screenIndex: idx)
            }
            isAudienceWindowVisible = true
        } else if connectedScreens.count > 1 {
            assignRole(.audience, forScreenIndex: 1)
            attachAudienceToScreen(connectedScreens[1], screenIndex: 1)
            isAudienceWindowVisible = true
        } else if let first = connectedScreens.first {
            setupAuxiliaryAudienceWindow(on: first)
        }
    }

    private func attachAudienceToScreen(_ screen: NSScreen, screenIndex: Int) {
        let window: NSWindow
        let view: AudiencePresentationView

        if let existing = audienceWindows[screenIndex] {
            window = existing.window
            view = existing.view
            window.styleMask = [.borderless]
            window.setFrame(screen.frame, display: true)
            configureBroadcastWindow(window, on: screen)
        } else {
            window = NSWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.isReleasedWhenClosed = false
            configureBroadcastWindow(window, on: screen)
            view = AudiencePresentationView(frame: NSRect(origin: .zero, size: screen.frame.size))
            window.contentView = view
            audienceWindows[screenIndex] = (window, view)
        }

        view.engineDidReloadDeck()
        window.orderFront(nil)
        isAudienceWindowVisible = true
    }

    private func detachAudienceFromScreen(screenIndex: Int) {
        if let existing = audienceWindows.removeValue(forKey: screenIndex) {
            existing.window.orderOut(nil)
        }
        if audienceWindows.isEmpty && auxiliaryAudienceWindow == nil {
            isAudienceWindowVisible = false
        }
    }

    public func setupAuxiliaryAudienceWindow(on screen: NSScreen) {
        if let existing = auxiliaryAudienceWindow {
            existing.window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
            existing.window.title = "Audience Display (Live Output)"
            existing.window.level = .floating
            existing.window.makeKeyAndOrderFront(nil)
            existing.view.engineDidReloadDeck()
            isAudienceWindowVisible = true
            return
        }

        let defaultWidth: CGFloat = 800
        let defaultHeight: CGFloat = 450
        let screenRect = screen.visibleFrame
        let windowRect = NSRect(
            x: screenRect.maxX - defaultWidth - 40,
            y: screenRect.minY + 40,
            width: defaultWidth,
            height: defaultHeight
        )

        let window = NSWindow(
            contentRect: windowRect,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.title = "Audience Display (Live Output)"
        window.isReleasedWhenClosed = false
        window.backgroundColor = .black
        window.level = .floating

        let view = AudiencePresentationView(frame: NSRect(origin: .zero, size: windowRect.size))
        window.contentView = view
        self.auxiliaryAudienceWindow = (window, view)

        window.makeKeyAndOrderFront(nil)
        isAudienceWindowVisible = true
    }

    // MARK: - Stage View Output (Multi-Display Confidence Monitor)

    public func toggleStageWindow() {
        if isStageWindowVisible {
            for (_, win) in stageWindows {
                win.orderOut(nil)
            }
            auxiliaryStageWindow?.orderOut(nil)
            isStageWindowVisible = false
            return
        }

        let stageIndices = screenAssignments.filter { $0.value == .stage && $0.key < connectedScreens.count }.map(\.key)
        if !stageIndices.isEmpty {
            for idx in stageIndices {
                attachStageToScreen(connectedScreens[idx], screenIndex: idx)
            }
            isStageWindowVisible = true
        } else if connectedScreens.count > 2 {
            assignRole(.stage, forScreenIndex: 2)
            attachStageToScreen(connectedScreens[2], screenIndex: 2)
            isStageWindowVisible = true
        } else if let first = connectedScreens.first {
            setupAuxiliaryStageWindow(on: first)
        }
    }

    private func attachStageToScreen(_ screen: NSScreen, screenIndex: Int) {
        let window: NSWindow
        if let existing = stageWindows[screenIndex] {
            window = existing
            window.styleMask = [.borderless]
            window.setFrame(screen.frame, display: true)
            configureBroadcastWindow(window, on: screen)
        } else {
            window = NSWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.isReleasedWhenClosed = false
            configureBroadcastWindow(window, on: screen)
            let hosting = NSHostingView(rootView: StageDisplayView())
            window.contentView = hosting
            stageWindows[screenIndex] = window
        }

        window.orderFront(nil)
        isStageWindowVisible = true
    }

    private func detachStageFromScreen(screenIndex: Int) {
        if let win = stageWindows.removeValue(forKey: screenIndex) {
            win.orderOut(nil)
        }
        if stageWindows.isEmpty && auxiliaryStageWindow == nil {
            isStageWindowVisible = false
        }
    }

    public func setupAuxiliaryStageWindow(on screen: NSScreen) {
        if let win = auxiliaryStageWindow {
            win.styleMask = [.titled, .closable, .resizable, .miniaturizable]
            win.title = "Stage Display (Confidence Monitor)"
            win.level = .normal
            win.makeKeyAndOrderFront(nil)
            isStageWindowVisible = true
            return
        }

        let defaultWidth: CGFloat = 900
        let defaultHeight: CGFloat = 540
        let screenRect = screen.visibleFrame
        let windowRect = NSRect(
            x: screenRect.minX + 60,
            y: screenRect.minY + 60,
            width: defaultWidth,
            height: defaultHeight
        )

        let window = NSWindow(
            contentRect: windowRect,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.title = "Stage Display (Confidence Monitor)"
        window.isReleasedWhenClosed = false
        window.backgroundColor = .black

        let hosting = NSHostingView(rootView: StageDisplayView())
        window.contentView = hosting
        self.auxiliaryStageWindow = window

        window.makeKeyAndOrderFront(nil)
        isStageWindowVisible = true
    }

    private func configureBroadcastWindow(_ window: NSWindow, on screen: NSScreen) {
        window.level = .screenSaver
        window.isOpaque = true
        window.hasShadow = false
        window.backgroundColor = .black
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }
}

// MARK: - AudienceRenderDelegate Composite Multi-Casting
extension ScreenCoordinator: AudienceRenderDelegate {
    public func performTransition(from: SlideItem?, to: SlideItem, type: TransitionType) {
        for (_, entry) in audienceWindows {
            entry.view.performTransition(from: from, to: to, type: type)
        }
        auxiliaryAudienceWindow?.view.performTransition(from: from, to: to, type: type)
    }

    public func setBlackout(_ isBlackedOut: Bool) {
        for (_, entry) in audienceWindows {
            entry.view.setBlackout(isBlackedOut)
        }
        auxiliaryAudienceWindow?.view.setBlackout(isBlackedOut)
    }

    public func setMediaMuted(_ isMuted: Bool) {
        for (_, entry) in audienceWindows {
            entry.view.setMediaMuted(isMuted)
        }
        auxiliaryAudienceWindow?.view.setMediaMuted(isMuted)
    }

    public func engineDidReloadDeck() {
        for (_, entry) in audienceWindows {
            entry.view.engineDidReloadDeck()
        }
        auxiliaryAudienceWindow?.view.engineDidReloadDeck()
    }
}
