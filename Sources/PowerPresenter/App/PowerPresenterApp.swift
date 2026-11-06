import SwiftUI

@main
struct PowerPresenterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject var engine = PresentationEngine.shared
    @ObservedObject var updater = AppUpdateManager.shared
    @ObservedObject var audioManager = AudioOutputManager.shared
    @AppStorage("operatorThumbnailSize") private var thumbnailSize: Double = 210.0

    var body: some Scene {
        WindowGroup("PowerPresenter Operator Dashboard") {
            OperatorDashboardView()
                .onAppear {
                    if updater.autoCheckOnLaunch {
                        updater.checkForUpdates(manual: false)
                    }
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1100, height: 720)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates...") {
                    updater.checkForUpdates(manual: true)
                }
                Divider()
            }

            CommandMenu("View") {
                Button("Zoom In Slide Previews") {
                    thumbnailSize = min(400, thumbnailSize + 25)
                }
                .keyboardShortcut("=", modifiers: [.command])

                Button("Zoom Out Slide Previews") {
                    thumbnailSize = max(110, thumbnailSize - 25)
                }
                .keyboardShortcut("-", modifiers: [.command])

                Button("Actual Size (Default)") {
                    thumbnailSize = 210
                }
                .keyboardShortcut("0", modifiers: [.command])
            }

            CommandMenu("Presentation") {
                Button("Next Slide") {
                    engine.next()
                }
                .keyboardShortcut(.rightArrow, modifiers: [])

                Button("Next Slide (Space)") {
                    engine.next()
                }
                .keyboardShortcut(.space, modifiers: [])

                Button("Previous Slide") {
                    engine.previous()
                }
                .keyboardShortcut(.leftArrow, modifiers: [])

                Divider()

                Button("Toggle Emergency Blackout") {
                    engine.toggleBlackout()
                }
                .keyboardShortcut("b", modifiers: [.command])

                Button("Clear / Mute Media") {
                    engine.clearMedia()
                }
                .keyboardShortcut("m", modifiers: [.command])

                Divider()

                Button("Toggle Audience Display Window") {
                    ScreenCoordinator.shared.toggleAudienceWindow()
                }
                .keyboardShortcut("d", modifiers: [.command])

                Button("Toggle Stage View Window") {
                    ScreenCoordinator.shared.toggleStageWindow()
                }
                .keyboardShortcut("s", modifiers: [.command])
            }

            CommandMenu("Audio") {
                Button("macOS System Default") {
                    AudioOutputManager.shared.selectSystemDefault()
                }

                Divider()

                ForEach(AudioOutputManager.shared.availableDevices) { device in
                    Button {
                        AudioOutputManager.shared.selectDevice(uid: device.id)
                    } label: {
                        if AudioOutputManager.shared.selectedDeviceUID == device.id {
                            Text("✓ \(device.name)")
                        } else {
                            Text("   \(device.name)")
                        }
                    }
                }

                Divider()

                Button("Play Test Sound Chime") {
                    AudioOutputManager.shared.playTestSound()
                }
                .keyboardShortcut("t", modifiers: [.command, .option])
            }
        }
    }
}
