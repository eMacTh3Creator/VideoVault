import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var settings: AppSettings

    @State private var ytdlpFound = false
    @State private var detectedPath: String?
    @State private var isInstalling = false
    @State private var installStatus: String?
    @State private var installError: String?
    @State private var didCheck = false

    @State private var ffmpegFound = false
    @State private var ffmpegPath: String?
    @State private var isInstallingFFmpeg = false
    @State private var ffmpegInstallStatus: String?
    @State private var ffmpegInstallError: String?

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            // Icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.purple, .indigo, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)

                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.white)
            }

            // Welcome text
            VStack(spacing: 8) {
                Text("Welcome to VideoVault")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Download videos from YouTube, Vimeo, Twitter,\nTikTok, and 1000+ other sites in your preferred format.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)

            // yt-dlp status
            ytdlpStatusSection
                .padding(.vertical, 4)

            // ffmpeg status
            ffmpegStatusSection
                .padding(.vertical, 4)

            // Download location
            VStack(spacing: 8) {
                Text("Download Location")
                    .font(.subheadline)
                    .fontWeight(.medium)

                HStack {
                    Text(settings.downloadPath)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 320, alignment: .leading)

                    Button("Change...") {
                        selectFolder()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            Spacer()

            Button(action: {
                settings.hasCompletedOnboarding = true
            }) {
                Text(ytdlpFound && ffmpegFound ? "Get Started" : "Continue Anyway")
                    .font(.headline)
                    .frame(maxWidth: 260)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            if !ytdlpFound || !ffmpegFound {
                Text("You can configure dependencies later in Settings")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
                .frame(height: 16)
        }
        .padding(32)
        .frame(width: 540, height: 720)
        .task {
            guard !didCheck else { return }
            didCheck = true
            checkYTDLP()
            checkFFmpeg()
        }
    }

    // MARK: - yt-dlp Status Section

    @ViewBuilder
    private var ytdlpStatusSection: some View {
        if ytdlpFound {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("yt-dlp found")
                    .font(.subheadline)
                    .foregroundColor(.green)
                if let path = detectedPath {
                    Text("(\(URL(fileURLWithPath: path).lastPathComponent))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        } else if isInstalling {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text(installStatus ?? "Installing yt-dlp...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                if let error = installError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 400)
                }
            }
        } else {
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("yt-dlp is required but not installed")
                        .font(.subheadline)
                        .foregroundColor(.orange)
                }

                VStack(spacing: 8) {
                    Button(action: { installYTDLP() }) {
                        Label("Download & Install yt-dlp", systemImage: "arrow.down.app")
                            .frame(maxWidth: 240)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)
                    .controlSize(.regular)

                    Text("Downloads the official binary to ~/.local/bin")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 4) {
                    Text("Or install via Homebrew:")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("brew install yt-dlp")
                        .font(.system(size: 11, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(4)

                    Button(action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("brew install yt-dlp", forType: .string)
                    }) {
                        Image(systemName: "doc.on.doc")
                            .font(.caption2)
                    }
                    .buttonStyle(.borderless)
                }

                if installError != nil {
                    Button("Re-check") {
                        installError = nil
                        checkYTDLP()
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    // MARK: - Check (file system only)

    private func checkYTDLP() {
        let paths = [
            settings.ytdlpPath,
            "/opt/homebrew/bin/yt-dlp",
            "/usr/local/bin/yt-dlp",
            "/usr/bin/yt-dlp",
            NSHomeDirectory() + "/.local/bin/yt-dlp"
        ]

        for path in paths {
            if FileManager.default.isExecutableFile(atPath: path) {
                ytdlpFound = true
                detectedPath = path
                if path != settings.ytdlpPath {
                    settings.ytdlpPath = path
                }
                return
            }
        }

        ytdlpFound = false
        detectedPath = nil
    }

    // MARK: - Install yt-dlp

    private func installYTDLP() {
        isInstalling = true
        installError = nil
        installStatus = "Downloading yt-dlp..."

        let installDir = NSHomeDirectory() + "/.local/bin"
        let installPath = installDir + "/yt-dlp"
        let downloadURL = "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos"

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try FileManager.default.createDirectory(
                    atPath: installDir,
                    withIntermediateDirectories: true
                )

                guard let url = URL(string: downloadURL) else {
                    throw InstallError.invalidURL
                }

                let semaphore = DispatchSemaphore(value: 0)
                var downloadedData: Data?
                var downloadError: Error?

                let task = URLSession.shared.dataTask(with: url) { data, response, error in
                    if let error = error {
                        downloadError = error
                    } else if let httpResponse = response as? HTTPURLResponse,
                              httpResponse.statusCode != 200 {
                        downloadError = InstallError.httpError(httpResponse.statusCode)
                    } else {
                        downloadedData = data
                    }
                    semaphore.signal()
                }
                task.resume()

                let result = semaphore.wait(timeout: .now() + 60)
                if result == .timedOut {
                    task.cancel()
                    throw InstallError.timeout
                }

                if let error = downloadError { throw error }

                guard let data = downloadedData, !data.isEmpty else {
                    throw InstallError.emptyDownload
                }

                DispatchQueue.main.async {
                    installStatus = "Installing..."
                }

                try data.write(to: URL(fileURLWithPath: installPath), options: .atomic)

                let attrs: [FileAttributeKey: Any] = [.posixPermissions: 0o755]
                try FileManager.default.setAttributes(attrs, ofItemAtPath: installPath)

                guard FileManager.default.isExecutableFile(atPath: installPath) else {
                    throw InstallError.notExecutable
                }

                DispatchQueue.main.async {
                    settings.ytdlpPath = installPath
                    detectedPath = installPath
                    ytdlpFound = true
                    isInstalling = false
                    installStatus = nil
                }

            } catch {
                DispatchQueue.main.async {
                    isInstalling = false
                    installError = "Install failed: \(error.localizedDescription)"
                    installStatus = nil
                }
            }
        }
    }

    // MARK: - ffmpeg Status Section

    @ViewBuilder
    private var ffmpegStatusSection: some View {
        if ffmpegFound {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("ffmpeg found")
                    .font(.subheadline)
                    .foregroundColor(.green)
                if let path = ffmpegPath {
                    Text("(\(URL(fileURLWithPath: path).lastPathComponent))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        } else if isInstallingFFmpeg {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text(ffmpegInstallStatus ?? "Installing ffmpeg...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                if let error = ffmpegInstallError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 400)
                }
            }
        } else {
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("ffmpeg is required for video merging & MP3")
                        .font(.subheadline)
                        .foregroundColor(.orange)
                }

                VStack(spacing: 8) {
                    Button(action: { installFFmpeg() }) {
                        Label("Download & Install ffmpeg", systemImage: "arrow.down.app")
                            .frame(maxWidth: 240)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .controlSize(.regular)

                    Text("Downloads the binary to ~/.local/bin")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 4) {
                    Text("Or install via Homebrew:")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("brew install ffmpeg")
                        .font(.system(size: 11, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(4)

                    Button(action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("brew install ffmpeg", forType: .string)
                    }) {
                        Image(systemName: "doc.on.doc")
                            .font(.caption2)
                    }
                    .buttonStyle(.borderless)
                }

                if ffmpegInstallError != nil {
                    Button("Re-check") {
                        ffmpegInstallError = nil
                        checkFFmpeg()
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    // MARK: - Check ffmpeg

    private func checkFFmpeg() {
        let paths = [
            settings.ffmpegPath,
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/usr/bin/ffmpeg",
            NSHomeDirectory() + "/.local/bin/ffmpeg"
        ]

        for path in paths {
            if FileManager.default.isExecutableFile(atPath: path) {
                ffmpegFound = true
                ffmpegPath = path
                if path != settings.ffmpegPath {
                    settings.ffmpegPath = path
                }
                return
            }
        }

        ffmpegFound = false
        ffmpegPath = nil
    }

    // MARK: - Install ffmpeg

    private func installFFmpeg() {
        isInstallingFFmpeg = true
        ffmpegInstallError = nil
        ffmpegInstallStatus = "Downloading ffmpeg..."

        let installDir = NSHomeDirectory() + "/.local/bin"
        let installPath = installDir + "/ffmpeg"

        // Use yt-dlp's recommended ffmpeg builds for macOS
        let downloadURL = "https://evermeet.cx/ffmpeg/getrelease/zip"

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try FileManager.default.createDirectory(
                    atPath: installDir,
                    withIntermediateDirectories: true
                )

                guard let url = URL(string: downloadURL) else {
                    throw InstallError.invalidURL
                }

                let semaphore = DispatchSemaphore(value: 0)
                var downloadedData: Data?
                var downloadError: Error?

                let task = URLSession.shared.dataTask(with: url) { data, response, error in
                    if let error = error {
                        downloadError = error
                    } else if let httpResponse = response as? HTTPURLResponse,
                              httpResponse.statusCode != 200 {
                        downloadError = InstallError.httpError(httpResponse.statusCode)
                    } else {
                        downloadedData = data
                    }
                    semaphore.signal()
                }
                task.resume()

                let result = semaphore.wait(timeout: .now() + 120)
                if result == .timedOut {
                    task.cancel()
                    throw InstallError.timeout
                }

                if let error = downloadError { throw error }

                guard let data = downloadedData, !data.isEmpty else {
                    throw InstallError.emptyDownload
                }

                DispatchQueue.main.async {
                    ffmpegInstallStatus = "Extracting..."
                }

                // Write zip to temp file and extract
                let tempZip = FileManager.default.temporaryDirectory.appendingPathComponent("ffmpeg.zip")
                try data.write(to: tempZip, options: .atomic)

                // Unzip using /usr/bin/ditto (built-in macOS)
                let unzipDir = FileManager.default.temporaryDirectory.appendingPathComponent("ffmpeg_extract")
                try? FileManager.default.removeItem(at: unzipDir)
                try FileManager.default.createDirectory(at: unzipDir, withIntermediateDirectories: true)

                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                process.arguments = ["-xk", tempZip.path, unzipDir.path]
                try process.run()
                process.waitUntilExit()

                // Find the ffmpeg binary in the extracted directory
                let extractedBinary = unzipDir.appendingPathComponent("ffmpeg")
                guard FileManager.default.fileExists(atPath: extractedBinary.path) else {
                    // Try to find it recursively
                    if let enumerator = FileManager.default.enumerator(at: unzipDir, includingPropertiesForKeys: nil) {
                        var found = false
                        while let fileURL = enumerator.nextObject() as? URL {
                            if fileURL.lastPathComponent == "ffmpeg" {
                                try? FileManager.default.removeItem(atPath: installPath)
                                try FileManager.default.copyItem(at: fileURL, to: URL(fileURLWithPath: installPath))
                                found = true
                                break
                            }
                        }
                        if !found { throw InstallError.notExecutable }
                    } else {
                        throw InstallError.notExecutable
                    }

                    // Clean up
                    try? FileManager.default.removeItem(at: tempZip)
                    try? FileManager.default.removeItem(at: unzipDir)

                    let attrs: [FileAttributeKey: Any] = [.posixPermissions: 0o755]
                    try FileManager.default.setAttributes(attrs, ofItemAtPath: installPath)

                    DispatchQueue.main.async {
                        settings.ffmpegPath = installPath
                        ffmpegPath = installPath
                        ffmpegFound = true
                        isInstallingFFmpeg = false
                        ffmpegInstallStatus = nil
                    }
                    return
                }

                // Move to install location
                try? FileManager.default.removeItem(atPath: installPath)
                try FileManager.default.copyItem(at: extractedBinary, to: URL(fileURLWithPath: installPath))

                let attrs: [FileAttributeKey: Any] = [.posixPermissions: 0o755]
                try FileManager.default.setAttributes(attrs, ofItemAtPath: installPath)

                // Clean up
                try? FileManager.default.removeItem(at: tempZip)
                try? FileManager.default.removeItem(at: unzipDir)

                guard FileManager.default.isExecutableFile(atPath: installPath) else {
                    throw InstallError.notExecutable
                }

                DispatchQueue.main.async {
                    settings.ffmpegPath = installPath
                    ffmpegPath = installPath
                    ffmpegFound = true
                    isInstallingFFmpeg = false
                    ffmpegInstallStatus = nil
                }

            } catch {
                DispatchQueue.main.async {
                    isInstallingFFmpeg = false
                    ffmpegInstallError = "Install failed: \(error.localizedDescription)"
                    ffmpegInstallStatus = nil
                }
            }
        }
    }

    // MARK: - Folder Picker

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
}

private enum InstallError: LocalizedError {
    case invalidURL, httpError(Int), timeout, emptyDownload, notExecutable

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid download URL"
        case .httpError(let code): return "Download failed (HTTP \(code))"
        case .timeout: return "Download timed out"
        case .emptyDownload: return "Downloaded file was empty"
        case .notExecutable: return "Failed to set permissions"
        }
    }
}
