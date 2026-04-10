import Foundation
import Combine

class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var downloadPath: String {
        didSet { UserDefaults.standard.set(downloadPath, forKey: "downloadPath") }
    }

    @Published var defaultFormat: DownloadFormat {
        didSet { UserDefaults.standard.set(defaultFormat.rawValue, forKey: "defaultFormat") }
    }

    @Published var maxConcurrentDownloads: Int {
        didSet { UserDefaults.standard.set(maxConcurrentDownloads, forKey: "maxConcurrentDownloads") }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: "launchAtLogin")
            LaunchAtLogin.setEnabled(launchAtLogin)
        }
    }

    @Published var showInMenuBar: Bool {
        didSet { UserDefaults.standard.set(showInMenuBar, forKey: "showInMenuBar") }
    }

    @Published var notificationsEnabled: Bool {
        didSet { UserDefaults.standard.set(notificationsEnabled, forKey: "notificationsEnabled") }
    }

    @Published var hasCompletedOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") }
    }

    @Published var autoRetryFailed: Bool {
        didSet { UserDefaults.standard.set(autoRetryFailed, forKey: "autoRetryFailed") }
    }

    @Published var ytdlpPath: String {
        didSet { UserDefaults.standard.set(ytdlpPath, forKey: "ytdlpPath") }
    }

    @Published var embedThumbnail: Bool {
        didSet { UserDefaults.standard.set(embedThumbnail, forKey: "embedThumbnail") }
    }

    @Published var embedMetadata: Bool {
        didSet { UserDefaults.standard.set(embedMetadata, forKey: "embedMetadata") }
    }

    @Published var organizeBySource: Bool {
        didSet { UserDefaults.standard.set(organizeBySource, forKey: "organizeBySource") }
    }

    @Published var useBrowserCookies: Bool {
        didSet { UserDefaults.standard.set(useBrowserCookies, forKey: "useBrowserCookies") }
    }

    @Published var cookiesBrowser: String {
        didSet { UserDefaults.standard.set(cookiesBrowser, forKey: "cookiesBrowser") }
    }

    @Published var ffmpegPath: String {
        didSet { UserDefaults.standard.set(ffmpegPath, forKey: "ffmpegPath") }
    }

    private init() {
        let defaults = UserDefaults.standard

        let defaultDownloadPath = NSHomeDirectory() + "/Downloads/VideoVault"

        self.downloadPath = defaults.string(forKey: "downloadPath") ?? defaultDownloadPath
        self.defaultFormat = DownloadFormat(rawValue: defaults.string(forKey: "defaultFormat") ?? "") ?? .video1080p
        self.maxConcurrentDownloads = defaults.integer(forKey: "maxConcurrentDownloads") == 0 ? 3 : defaults.integer(forKey: "maxConcurrentDownloads")
        self.launchAtLogin = defaults.bool(forKey: "launchAtLogin")
        self.showInMenuBar = defaults.object(forKey: "showInMenuBar") as? Bool ?? true
        self.notificationsEnabled = defaults.object(forKey: "notificationsEnabled") as? Bool ?? true
        self.hasCompletedOnboarding = defaults.bool(forKey: "hasCompletedOnboarding")
        self.autoRetryFailed = defaults.object(forKey: "autoRetryFailed") as? Bool ?? true
        self.ytdlpPath = defaults.string(forKey: "ytdlpPath") ?? "/opt/homebrew/bin/yt-dlp"
        self.embedThumbnail = defaults.object(forKey: "embedThumbnail") as? Bool ?? true
        self.embedMetadata = defaults.object(forKey: "embedMetadata") as? Bool ?? true
        self.organizeBySource = defaults.object(forKey: "organizeBySource") as? Bool ?? true
        self.useBrowserCookies = defaults.object(forKey: "useBrowserCookies") as? Bool ?? true
        self.cookiesBrowser = defaults.string(forKey: "cookiesBrowser") ?? "safari"
        self.ffmpegPath = defaults.string(forKey: "ffmpegPath") ?? "/opt/homebrew/bin/ffmpeg"
    }

    var downloadURL: URL {
        URL(fileURLWithPath: downloadPath)
    }

    func sourceDirectory(for source: String) -> URL {
        if organizeBySource {
            return downloadURL.appendingPathComponent(source)
        }
        return downloadURL
    }
}
