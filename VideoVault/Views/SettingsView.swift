import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @State private var ytdlpVersion: String?
    @State private var ytdlpFound: Bool = false
    @State private var ffmpegFound: Bool = false
    @State private var storageSize: String = "Calculating..."

    var body: some View {
        VStack(spacing: 0) {
            // Title
            HStack {
                Text("Settings")
                    .font(.headline)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Download Location
                    settingsSection("Download Location", icon: "folder") {
                        HStack {
                            TextField("Download path", text: $settings.downloadPath)
                                .textFieldStyle(.roundedBorder)

                            Button("Browse...") { selectFolder() }
                                .buttonStyle(.bordered)
                        }

                        Toggle("Organize by source site", isOn: $settings.organizeBySource)
                            .font(.subheadline)

                        HStack {
                            Text("Storage used: \(storageSize)")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Button("Open Folder") {
                                StorageManager.shared.openDownloadFolder()
                            }
                            .font(.caption)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }

                    // Default Format
                    settingsSection("Default Format", icon: "film") {
                        Picker("Default download format", selection: $settings.defaultFormat) {
                            ForEach(DownloadFormat.allCases) { format in
                                Text(format.rawValue).tag(format)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }

                    // Performance
                    settingsSection("Performance", icon: "gauge.with.dots.needle.67percent") {
                        HStack {
                            Text("Concurrent downloads:")
                            Picker("", selection: $settings.maxConcurrentDownloads) {
                                Text("1").tag(1)
                                Text("2").tag(2)
                                Text("3").tag(3)
                                Text("5").tag(5)
                                Text("8").tag(8)
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 250)
                        }

                        Toggle("Auto-retry failed downloads", isOn: $settings.autoRetryFailed)
                            .font(.subheadline)
                    }

                    // Metadata
                    settingsSection("Metadata", icon: "tag") {
                        Toggle("Embed thumbnail in file", isOn: $settings.embedThumbnail)
                            .font(.subheadline)
                        Toggle("Embed metadata (title, uploader, etc.)", isOn: $settings.embedMetadata)
                            .font(.subheadline)
                    }

                    // Behavior
                    settingsSection("Behavior", icon: "gearshape") {
                        Toggle("Launch at login", isOn: $settings.launchAtLogin)
                            .font(.subheadline)
                        Toggle("Show in menu bar", isOn: $settings.showInMenuBar)
                            .font(.subheadline)
                        Toggle("Show notifications", isOn: $settings.notificationsEnabled)
                            .font(.subheadline)
                    }

                    // YouTube / Cookies
                    settingsSection("YouTube Workarounds", icon: "play.rectangle") {
                        Toggle("Use browser cookies (recommended for YouTube)", isOn: $settings.useBrowserCookies)
                            .font(.subheadline)

                        if settings.useBrowserCookies {
                            Picker("Browser:", selection: $settings.cookiesBrowser) {
                                Text("Safari").tag("safari")
                                Text("Chrome").tag("chrome")
                                Text("Firefox").tag("firefox")
                                Text("Brave").tag("brave")
                                Text("Edge").tag("edge")
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: 200)

                            Text("Sends your browser's cookies to yt-dlp so YouTube treats it as a logged-in browser request.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    // yt-dlp
                    settingsSection("yt-dlp", icon: "terminal") {
                        HStack {
                            TextField("yt-dlp path", text: $settings.ytdlpPath)
                                .textFieldStyle(.roundedBorder)

                            Button("Detect") { detectYTDLP() }
                                .buttonStyle(.bordered)
                        }

                        HStack(spacing: 8) {
                            if ytdlpFound {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("yt-dlp found")
                                    .font(.caption)
                                    .foregroundColor(.green)
                                if let version = ytdlpVersion {
                                    Text("v\(version)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            } else {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text("yt-dlp not found — install via: brew install yt-dlp")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                    }

                    // ffmpeg
                    settingsSection("ffmpeg", icon: "film.stack") {
                        HStack {
                            TextField("ffmpeg path", text: $settings.ffmpegPath)
                                .textFieldStyle(.roundedBorder)

                            Button("Detect") { detectFFmpeg() }
                                .buttonStyle(.bordered)
                        }

                        HStack(spacing: 8) {
                            if ffmpegFound {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("ffmpeg found")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            } else {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text("ffmpeg not found — install via: brew install ffmpeg")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }

                        Text("Required for merging video/audio streams and MP3 conversion.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 540, height: 720)
        .onAppear {
            checkYTDLP()
            checkFFmpeg()
            calculateStorage()
        }
    }

    // MARK: - Section Builder

    private func settingsSection<Content: View>(
        _ title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.subheadline)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .padding(.leading, 4)
        }
    }

    // MARK: - Actions

    private func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose where to save downloaded videos"

        if panel.runModal() == .OK, let url = panel.url {
            settings.downloadPath = url.path
        }
    }

    private func detectYTDLP() {
        // Fast file-system check for common paths
        let knownPaths = [
            "/opt/homebrew/bin/yt-dlp",
            "/usr/local/bin/yt-dlp",
            "/usr/bin/yt-dlp",
            NSHomeDirectory() + "/.local/bin/yt-dlp"
        ]

        for path in knownPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                settings.ytdlpPath = path
                break
            }
        }
        checkYTDLP()
    }

    private func checkYTDLP() {
        ytdlpFound = YTDLPService.shared.isYTDLPInstalled()
        // Get version on background thread to avoid UI hang
        if ytdlpFound {
            DispatchQueue.global(qos: .utility).async {
                let version = YTDLPService.shared.getVersion()
                DispatchQueue.main.async {
                    ytdlpVersion = version
                }
            }
        } else {
            ytdlpVersion = nil
        }
    }

    private func detectFFmpeg() {
        let knownPaths = [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/usr/bin/ffmpeg",
            NSHomeDirectory() + "/.local/bin/ffmpeg"
        ]

        for path in knownPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                settings.ffmpegPath = path
                break
            }
        }
        checkFFmpeg()
    }

    private func checkFFmpeg() {
        ffmpegFound = YTDLPService.shared.isFFmpegInstalled()
    }

    private func calculateStorage() {
        DispatchQueue.global(qos: .utility).async {
            let size = StorageManager.shared.formattedTotalSize()
            DispatchQueue.main.async {
                storageSize = size
            }
        }
    }
}
