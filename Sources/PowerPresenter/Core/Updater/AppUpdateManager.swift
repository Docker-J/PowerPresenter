import Foundation
import SwiftUI
import AppKit

public struct GitHubReleaseAsset: Codable, Identifiable {
    public var id: Int
    public var name: String
    public var size: Int
    public var browserDownloadUrl: String

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case size
        case browserDownloadUrl = "browser_download_url"
    }
}

public struct GitHubRelease: Codable, Identifiable {
    public var id: Int
    public var tagName: String
    public var name: String?
    public var body: String?
    public var publishedAt: String?
    public var htmlUrl: String
    public var assets: [GitHubReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case id
        case tagName = "tag_name"
        case name
        case body
        case publishedAt = "published_at"
        case htmlUrl = "html_url"
        case assets
    }

    public var versionDisplay: String {
        return tagName.hasPrefix("v") || tagName.hasPrefix("V") ? String(tagName.dropFirst()) : tagName
    }
}

@MainActor
public final class AppUpdateManager: NSObject, ObservableObject {
    public static let shared = AppUpdateManager()

    // Default GitHub repository: can be overridden via UserDefaults
    @AppStorage("customGitHubRepo") public var gitHubRepo: String = "Docker-J/PowerPresenter"
    @AppStorage("autoCheckUpdatesOnLaunch") public var autoCheckOnLaunch: Bool = true

    @Published public var isChecking: Bool = false
    @Published public var isUpdateAvailable: Bool = false
    @Published public var latestRelease: GitHubRelease? = nil
    @Published public var isDownloading: Bool = false
    @Published public var downloadProgress: Double = 0.0
    @Published public var updateStatusMessage: String = ""
    @Published public var errorMessage: String? = nil
    @Published public var showUpdateDialog: Bool = false
    @Published public var isUpToDateAlertShown: Bool = false

    private var downloadSession: URLSession?
    private var downloadTask: URLSessionDownloadTask?
    private var downloadedZipURL: URL?

    public var currentVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.1.6"
        return version
    }

    public var currentBuild: String {
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return build
    }

    private override init() {
        super.init()
    }

    /// Check for latest release on GitHub
    public func checkForUpdates(manual: Bool = false) {
        guard !isChecking else { return }
        isChecking = true
        errorMessage = nil

        let repo = gitHubRepo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !repo.isEmpty, let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else {
            isChecking = false
            if manual {
                errorMessage = "유효하지 않은 GitHub 저장소 설정입니다: \(repo)"
                showUpdateDialog = true
            }
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("PowerPresenter-Updater", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        Task {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw NSError(domain: "AppUpdateManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "서버 응답 오류"])
                }

                if httpResponse.statusCode == 404 {
                    throw NSError(domain: "AppUpdateManager", code: 404, userInfo: [NSLocalizedDescriptionKey: "GitHub에 릴리즈가 아직 등록되지 않았습니다."])
                }

                guard httpResponse.statusCode == 200 else {
                    throw NSError(domain: "AppUpdateManager", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "GitHub API 오류 (상태 코드: \(httpResponse.statusCode))"])
                }

                let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
                let latestVer = release.versionDisplay

                let newer = isVersion(latestVer, greaterThan: self.currentVersion)

                self.latestRelease = release
                self.isChecking = false

                if newer {
                    self.isUpdateAvailable = true
                    self.showUpdateDialog = true
                } else {
                    self.isUpdateAvailable = false
                    if manual {
                        self.isUpToDateAlertShown = true
                        self.showUpdateDialog = true
                    }
                }
            } catch {
                self.isChecking = false
                if manual {
                    self.errorMessage = "업데이트 확인 중 오류 발생: \(error.localizedDescription)"
                    self.showUpdateDialog = true
                }
            }
        }
    }

    /// Start downloading and installing the new release
    public func downloadAndInstall(release: GitHubRelease) {
        guard !isDownloading else { return }

        // Find .zip asset in release
        guard let asset = release.assets.first(where: { $0.name.lowercased().hasSuffix(".zip") }) ?? release.assets.first else {
            self.errorMessage = "릴리즈에 다운로드 가능한 압축 파일(.zip)이 없습니다."
            return
        }

        guard let downloadUrl = URL(string: asset.browserDownloadUrl) else {
            self.errorMessage = "다운로드 URL이 유효하지 않습니다."
            return
        }

        self.isDownloading = true
        self.downloadProgress = 0.0
        self.updateStatusMessage = "다운로드 시작 중..."
        self.errorMessage = nil

        let sessionConfig = URLSessionConfiguration.default
        let session = URLSession(configuration: sessionConfig, delegate: self, delegateQueue: .main)
        self.downloadSession = session

        let task = session.downloadTask(with: downloadUrl)
        self.downloadTask = task
        task.resume()
    }

    public func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        isDownloading = false
        downloadProgress = 0.0
        updateStatusMessage = "다운로드가 취소되었습니다."
    }

    /// Unzip downloaded asset and relaunch app
    private func processDownloadedFile(at tempLocation: URL) {
        updateStatusMessage = "업데이트 파일 압축 해제 중..."

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let fileManager = FileManager.default
                let tempDir = fileManager.temporaryDirectory.appendingPathComponent("PowerPresenterUpdate_\(UUID().uuidString)")
                try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)

                let savedZip = tempDir.appendingPathComponent("update.zip")
                try fileManager.moveItem(at: tempLocation, to: savedZip)

                let extractDir = tempDir.appendingPathComponent("extracted")
                try fileManager.createDirectory(at: extractDir, withIntermediateDirectories: true)

                // Unpack using /usr/bin/ditto -xk
                let dittoProcess = Process()
                dittoProcess.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                dittoProcess.arguments = ["-xk", savedZip.path, extractDir.path]
                try dittoProcess.run()
                dittoProcess.waitUntilExit()

                guard dittoProcess.terminationStatus == 0 else {
                    throw NSError(domain: "AppUpdateManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "압축 해제 실패 (ditto 종료 코드: \(dittoProcess.terminationStatus))"])
                }

                // Find .app inside extracted folder
                let extractedItems = try fileManager.contentsOfDirectory(at: extractDir, includingPropertiesForKeys: nil)
                guard let newApp = extractedItems.first(where: { $0.pathExtension == "app" }) else {
                    throw NSError(domain: "AppUpdateManager", code: -3, userInfo: [NSLocalizedDescriptionKey: "압축 파일 내에서 PowerPresenter.app을 찾을 수 없습니다."])
                }

                // Ensure execution permissions inside app
                let chmodProcess = Process()
                chmodProcess.executableURL = URL(fileURLWithPath: "/bin/chmod")
                chmodProcess.arguments = ["-R", "+x", newApp.appendingPathComponent("Contents/MacOS").path]
                try? chmodProcess.run()
                chmodProcess.waitUntilExit()

                DispatchQueue.main.async {
                    self?.updateStatusMessage = "새 버전으로 교체 및 재시작 준비 중..."
                    self?.executeRestartScript(newAppURL: newApp)
                }
            } catch {
                DispatchQueue.main.async {
                    self?.isDownloading = false
                    self?.errorMessage = "업데이트 적용 중 오류: \(error.localizedDescription)"
                }
            }
        }
    }

    private func executeRestartScript(newAppURL: URL) {
        let currentAppURL = Bundle.main.bundleURL
        let targetAppPath: String

        if currentAppURL.pathExtension == "app" {
            targetAppPath = currentAppURL.path
        } else {
            targetAppPath = "/Applications/PowerPresenter.app"
        }

        let pid = ProcessInfo.processInfo.processIdentifier

        // Create detached helper shell script to replace app & reopen
        let script = """
        #!/bin/bash
        PID=\(pid)
        SRC="\(newAppURL.path)"
        DST="\(targetAppPath)"

        # Wait until old app quits (max 30s safety)
        for _ in $(seq 1 150); do
            if ! kill -0 "$PID" 2>/dev/null; then
                break
            fi
            sleep 0.2
        done

        # Remove quarantine attribute
        xattr -rd com.apple.quarantine "$SRC" 2>/dev/null || true

        # Replace app atomically via ditto (preserves symlinks & signatures)
        rm -rf "$DST"
        /usr/bin/ditto "$SRC" "$DST"

        # Clean temp directory & script
        rm -rf "$(dirname "$(dirname "$SRC")")"
        rm -f "$0"

        # Relaunch updated app
        open -n "$DST"
        exit 0
        """

        let scriptURL = FileManager.default.temporaryDirectory.appendingPathComponent("powerpresenter_updater.sh")
        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            let chmod = Process()
            chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
            chmod.arguments = ["+x", scriptURL.path]
            try chmod.run()
            chmod.waitUntilExit()

            let updaterProcess = Process()
            updaterProcess.executableURL = URL(fileURLWithPath: "/bin/bash")
            updaterProcess.arguments = [scriptURL.path]
            try updaterProcess.run()

            // Dismiss update sheet & attached sheets first so terminate() is never blocked by a modal sheet
            self.isDownloading = false
            self.showUpdateDialog = false
            for window in NSApplication.shared.windows {
                if let sheet = window.attachedSheet {
                    window.endSheet(sheet)
                }
            }

            // Terminate cleanly, with a hard exit fallback if AppKit delays termination
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                NSApplication.shared.terminate(nil)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                exit(0)
            }
        } catch {
            self.isDownloading = false
            self.errorMessage = "재시작 스크립트 실행 실패: \(error.localizedDescription)"
        }
    }

    /// Semantic version comparison (e.g. 2.0.1 > 2.0.0)
    private func isVersion(_ v1: String, greaterThan v2: String) -> Bool {
        let clean1 = v1.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            .split(separator: "-").first?
            .split(separator: ".")
            .compactMap { Int($0) } ?? []
        let clean2 = v2.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            .split(separator: "-").first?
            .split(separator: ".")
            .compactMap { Int($0) } ?? []

        let maxCount = max(clean1.count, clean2.count)
        for i in 0..<maxCount {
            let p1 = i < clean1.count ? clean1[i] : 0
            let p2 = i < clean2.count ? clean2[i] : 0
            if p1 > p2 { return true }
            if p1 < p2 { return false }
        }
        return false
    }
}

// MARK: - URLSessionDownloadDelegate
extension AppUpdateManager: URLSessionDownloadDelegate {
    public nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesExpectedToWrite > 0 {
            let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            let writtenMB = Double(totalBytesWritten) / (1024 * 1024)
            let totalMB = Double(totalBytesExpectedToWrite) / (1024 * 1024)
            Task { @MainActor in
                self.downloadProgress = progress
                self.updateStatusMessage = String(format: "다운로드 중... %.1f MB / %.1f MB (%.0f%%)", writtenMB, totalMB, progress * 100)
            }
        } else {
            let writtenMB = Double(totalBytesWritten) / (1024 * 1024)
            Task { @MainActor in
                self.updateStatusMessage = String(format: "다운로드 중... %.1f MB", writtenMB)
            }
        }
    }

    public nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // Move to persistent temp before delegate returns
        let tempDestination = FileManager.default.temporaryDirectory.appendingPathComponent("DownloadedUpdate_\(UUID().uuidString).zip")
        do {
            try FileManager.default.moveItem(at: location, to: tempDestination)
            Task { @MainActor in
                self.processDownloadedFile(at: tempDestination)
            }
        } catch {
            Task { @MainActor in
                self.isDownloading = false
                self.errorMessage = "다운로드 파일 처리 실패: \(error.localizedDescription)"
            }
        }
    }

    public nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error, (error as NSError).code != NSURLErrorCancelled {
            Task { @MainActor in
                self.isDownloading = false
                self.errorMessage = "다운로드 실패: \(error.localizedDescription)"
            }
        }
    }
}
