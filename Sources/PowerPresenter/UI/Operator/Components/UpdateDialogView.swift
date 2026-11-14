import SwiftUI

public struct UpdateDialogView: View {
    @ObservedObject var updater = AppUpdateManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showSettings: Bool = false

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .font(.system(size: 42))
                    .foregroundColor(.accentColor)
                    .symbolEffect(.pulse, isActive: updater.isDownloading)

                VStack(alignment: .leading, spacing: 4) {
                    if updater.isUpdateAvailable, let release = updater.latestRelease {
                        Text("새로운 업데이트가 출시되었습니다!")
                            .font(.headline)
                            .fontWeight(.bold)

                        HStack(spacing: 6) {
                            Text("현재: v\(updater.currentVersion)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Image(systemName: "arrow.right")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text("최신: v\(release.versionDisplay)")
                                .font(.caption.bold())
                                .foregroundColor(.accentColor)
                        }
                    } else if updater.isChecking {
                        Text("업데이트 확인 중...")
                            .font(.headline)
                        Text("GitHub에서 최신 릴리즈 정보를 조회하고 있습니다.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else if updater.isUpToDateAlertShown {
                        Text("현재 최신 버전을 사용 중입니다.")
                            .font(.headline)
                            .fontWeight(.bold)
                        Text("현재 설치된 버전 (v\(updater.currentVersion))이 최신 상태입니다.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else if let err = updater.errorMessage {
                        Text("업데이트 확인 실패")
                            .font(.headline)
                            .foregroundColor(.red)
                        Text(err)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Button {
                    withAnimation {
                        showSettings.toggle()
                    }
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("GitHub 저장소 설정")
            }
            .padding(20)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Advanced settings toggle
            if showSettings {
                VStack(alignment: .leading, spacing: 8) {
                    Text("GitHub 저장소 설정 (Owner/Repo)")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                    HStack {
                        TextField("예: Docker-J/PowerPresenter", text: $updater.gitHubRepo)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))

                        Button("저장소에서 확인") {
                            updater.checkForUpdates(manual: true)
                        }
                        .font(.caption)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.accentColor.opacity(0.06))
                Divider()
            }

            // Body: Release notes or Status
            VStack(alignment: .leading, spacing: 12) {
                if updater.isUpdateAvailable, let release = updater.latestRelease {
                    Text("릴리즈 정보 (\(release.name ?? release.tagName))")
                        .font(.subheadline.bold())

                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            if let body = release.body, !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(body)
                                    .font(.system(size: 12))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                Text("별도의 릴리즈 노트가 제공되지 않았습니다.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(10)
                    }
                    .frame(height: 180)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                    )
                }

                // Download Progress
                if updater.isDownloading {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: updater.downloadProgress)
                            .progressViewStyle(.linear)

                        HStack {
                            Text(updater.updateStatusMessage)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(20)

            Divider()

            // Actions Footer
            HStack {
                Toggle("앱 시작 시 자동으로 업데이트 확인", isOn: $updater.autoCheckOnLaunch)
                    .font(.caption)
                    .toggleStyle(.checkbox)

                Spacer()

                if updater.isDownloading {
                    Button("다운로드 취소") {
                        updater.cancelDownload()
                    }
                    .keyboardShortcut(.cancelAction)
                } else if updater.isUpdateAvailable, let release = updater.latestRelease {
                    Button("나중에") {
                        updater.showUpdateDialog = false
                    }
                    .keyboardShortcut(.cancelAction)

                    Button("지금 업데이트 & 재시작") {
                        updater.downloadAndInstall(release: release)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button("확인") {
                        updater.showUpdateDialog = false
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 520)
    }
}
