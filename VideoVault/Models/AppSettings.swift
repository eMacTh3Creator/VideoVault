import Foundation
import Combine

class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let defaults: UserDefaults

    @Published var downloadPath: String {
        didSet { defaults.set(downloadPath, forKey: "downloadPath") }
    }

    @Published var defaultFormat: DownloadFormat {
        didSet { defaults.set(defaultFormat.rawValue, forKey: "defaultFormat") }
    }

    @Published var maxConcurrentDownloads: Int {
        didSet { defaults.set(maxConcurrentDownloads, forKey: "maxConcurrentDownloads") }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: "launchAtLogin")
            LaunchAtLogin.setEnabled(launchAtLogin)
        }
    }

    @Published var showInMenuBar: Bool {
        didSet { defaults.set(showInMenuBar, forKey: "showInMenuBar") }
    }

    @Published var notificationsEnabled: Bool {
        didSet { defaults.set(notificationsEnabled, forKey: "notificationsEnabled") }
    }

    @Published var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") }
    }

    @Published var autoRetryFailed: Bool {
        didSet { defaults.set(autoRetryFailed, forKey: "autoRetryFailed") }
    }

    @Published var autoForceRetry: Bool {
        didSet { defaults.set(autoForceRetry, forKey: "autoForceRetry") }
    }

    @Published var maxForceRetries: Int {
        didSet { defaults.set(maxForceRetries, forKey: "maxForceRetries") }
    }

    @Published var ytdlpPath: String {
        didSet { defaults.set(ytdlpPath, forKey: "ytdlpPath") }
    }

    @Published var embedThumbnail: Bool {
        didSet { defaults.set(embedThumbnail, forKey: "embedThumbnail") }
    }

    @Published var embedMetadata: Bool {
        didSet { defaults.set(embedMetadata, forKey: "embedMetadata") }
    }

    @Published var organizeBySource: Bool {
        didSet { defaults.set(organizeBySource, forKey: "organizeBySource") }
    }

    @Published var useBrowserCookies: Bool {
        didSet { defaults.set(useBrowserCookies, forKey: "useBrowserCookies") }
    }

    @Published var cookiesBrowser: String {
        didSet { defaults.set(cookiesBrowser, forKey: "cookiesBrowser") }
    }

    @Published var ffmpegPath: String {
        didSet { defaults.set(ffmpegPath, forKey: "ffmpegPath") }
    }

    @Published var automaticallyUpdateYTDLP: Bool {
        didSet { defaults.set(automaticallyUpdateYTDLP, forKey: "automaticallyUpdateYTDLP") }
    }
    @Published var skipDuplicates: Bool {
        didSet { defaults.set(skipDuplicates, forKey: "skipDuplicates") }
    }
    @Published var enableFallbackDownloader: Bool {
        didSet { defaults.set(enableFallbackDownloader, forKey: "enableFallbackDownloader") }
    }
    @Published var streamlinkPath: String {
        didSet { defaults.set(streamlinkPath, forKey: "streamlinkPath") }
    }

    private init() {
        // Test workers must never change the running application's preferences.
        defaults = ProcessInfo.processInfo.environment["VIDEOVAULT_TEST_ROOT"]
            .flatMap { UserDefaults(suiteName: "VideoVault.Tests." + URL(fileURLWithPath: $0).lastPathComponent) }
            ?? UserDefaults.standard

        let defaultDownloadPath = NSHomeDirectory() + "/Downloads/VideoVault"

        self.downloadPath = defaults.string(forKey: "downloadPath") ?? defaultDownloadPath
        self.defaultFormat = DownloadFormat(rawValue: defaults.string(forKey: "defaultFormat") ?? "") ?? .video1080p
        self.maxConcurrentDownloads = defaults.integer(forKey: "maxConcurrentDownloads") == 0 ? 3 : defaults.integer(forKey: "maxConcurrentDownloads")
        self.launchAtLogin = defaults.bool(forKey: "launchAtLogin")
        self.showInMenuBar = defaults.object(forKey: "showInMenuBar") as? Bool ?? true
        self.notificationsEnabled = defaults.object(forKey: "notificationsEnabled") as? Bool ?? true
        self.hasCompletedOnboarding = defaults.bool(forKey: "hasCompletedOnboarding")
        self.autoRetryFailed = defaults.object(forKey: "autoRetryFailed") as? Bool ?? true
        self.autoForceRetry = defaults.object(forKey: "autoForceRetry") as? Bool ?? true
        self.maxForceRetries = min(10, max(1, defaults.object(forKey: "maxForceRetries") as? Int ?? 3))
        self.ytdlpPath = defaults.string(forKey: "ytdlpPath") ?? "/opt/homebrew/bin/yt-dlp"
        self.embedThumbnail = defaults.object(forKey: "embedThumbnail") as? Bool ?? true
        self.embedMetadata = defaults.object(forKey: "embedMetadata") as? Bool ?? true
        self.organizeBySource = defaults.object(forKey: "organizeBySource") as? Bool ?? true
        self.useBrowserCookies = defaults.object(forKey: "useBrowserCookies") as? Bool ?? false
        self.cookiesBrowser = defaults.string(forKey: "cookiesBrowser") ?? "safari"
        self.ffmpegPath = defaults.string(forKey: "ffmpegPath") ?? "/opt/homebrew/bin/ffmpeg"
        self.automaticallyUpdateYTDLP = defaults.object(forKey: "automaticallyUpdateYTDLP") as? Bool ?? true
        self.skipDuplicates = defaults.object(forKey: "skipDuplicates") as? Bool ?? true
        self.enableFallbackDownloader = defaults.object(forKey: "enableFallbackDownloader") as? Bool ?? true
        self.streamlinkPath = defaults.string(forKey: "streamlinkPath") ?? "/opt/homebrew/bin/streamlink"
    }

    var downloadURL: URL {
        URL(fileURLWithPath: downloadPath)
    }

    func sourceDirectory(for source: String) -> URL {
        if organizeBySource {
            let safeSource = source.components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_")).inverted).joined(separator: "_")
            return downloadURL.appendingPathComponent(safeSource.isEmpty ? "Unknown" : safeSource)
        }
        return downloadURL
    }
}
