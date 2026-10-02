import Foundation

struct VideoInfo: Decodable, Sendable {
    let title: String
    let durationSeconds: Double?
    let thumbnailURL: String?
    let source: String?
    let uploaderName: String?
    let id: String?
    let extractorKey: String?
    var mediaID: String? {
        guard let id, let extractorKey else { return nil }
        return "\(extractorKey.lowercased()):\(id)"
    }
    var duration: String? { durationSeconds.map { String(format: "%d:%02d", Int($0) / 60, Int($0) % 60) } }
    enum CodingKeys: String, CodingKey {
        case title, id
        case durationSeconds = "duration", thumbnailURL = "thumbnail", source = "extractor"
        case uploaderName = "uploader", extractorKey = "extractor_key"
    }
}

struct DownloadResult: Sendable {
    let file: URL
    let mediaID: String?
    let downloader: String
    let skipped: Bool
}

struct DownloadOptions: Sendable {
    let root: URL
    let ytdlpPath: String
    let ffmpegPath: String
    let streamlinkPath: String
    let useBrowserCookies: Bool
    let cookiesBrowser: String
    let embedMetadata: Bool
    let embedThumbnail: Bool
    let skipDuplicates: Bool
    let enableFallbackDownloader: Bool
    let organizeBySource: Bool
    let autoRetryFailed: Bool

    @MainActor init(settings: AppSettings = .shared) {
        root = settings.downloadURL.standardizedFileURL
        ytdlpPath = settings.ytdlpPath
        ffmpegPath = settings.ffmpegPath
        streamlinkPath = settings.streamlinkPath
        useBrowserCookies = settings.useBrowserCookies
        cookiesBrowser = settings.cookiesBrowser
        embedMetadata = settings.embedMetadata
        embedThumbnail = settings.embedThumbnail
        skipDuplicates = settings.skipDuplicates
        enableFallbackDownloader = settings.enableFallbackDownloader
        organizeBySource = settings.organizeBySource
        autoRetryFailed = settings.autoRetryFailed
    }
}

enum DownloadFailurePolicy {
    static func isSiteRestriction(_ message: String) -> Bool {
        let text = message.lowercased()
        return ["safety reason", "video has been removed", "video is unavailable", "private video", "drm protected", "drm-protected",
                "copyright", "not available in your country", "geo-restricted", "login required", "sign in to confirm your age",
                "age verification", "video closed", "video is blocked"].contains { text.contains($0) }
    }
    static func isTransient(_ message: String) -> Bool {
        let text = message.lowercased()
        return ["timed out", "stopped responding", "connection reset", "temporary failure", "http error 429", "http error 50", "network is unreachable"].contains { text.contains($0) }
    }
    static func explanation(_ message: String) -> String {
        if message.lowercased().contains("safety reason") {
            return "The website refused access to this video for safety reasons. yt-dlp is reporting the website's response. Open the original page in your browser and follow the site's support instructions.\n\n\(message)"
        }
        return message
    }
}

final class YTDLPService {
    static let shared = YTDLPService()
    private let settings = AppSettings.shared
    func isYTDLPInstalled() -> Bool { FileManager.default.isExecutableFile(atPath: settings.ytdlpPath) }
    func isFFmpegInstalled() -> Bool { FileManager.default.isExecutableFile(atPath: settings.ffmpegPath) }
    func findYTDLP() -> String? { Self.findExecutable("yt-dlp") }
    func findFFmpeg() -> String? { Self.findExecutable("ffmpeg") }
    static func findExecutable(_ name: String) -> String? {
        ([FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("VideoVault/tools").path,
          NSHomeDirectory() + "/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
            + (ProcessRunner.environment["PATH"] ?? "").components(separatedBy: ":"))
            .map { $0 + "/" + name }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    // Legacy status check, called only on a background queue.
    func getVersion() -> String? {
        guard isYTDLPInstalled() else { return nil }
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: settings.ytdlpPath)
        process.arguments = ["--version"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 5, execute: timeout)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timeout.cancel()
        return process.terminationStatus == 0 ? String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) : nil
    }

    private static func commonArgs(cookies: Bool, options: DownloadOptions) -> [String] {
        var args = ["--ignore-config", "--no-playlist", "--socket-timeout", "20", "--retries", "3", "--fragment-retries", "3", "--no-colors"]
        if cookies, options.useBrowserCookies, !options.cookiesBrowser.isEmpty { args += ["--cookies-from-browser", options.cookiesBrowser] }
        if FileManager.default.isExecutableFile(atPath: options.ffmpegPath) { args += ["--ffmpeg-location", options.ffmpegPath] }
        if let deno = Self.findExecutable("deno") { args += ["--js-runtimes", "deno:\(deno)"] }
        else if let node = Self.findExecutable("node") { args += ["--js-runtimes", "node:\(node)"] }
        return args
    }

    @MainActor func fetchVideoInfo(url: String) async throws -> VideoInfo {
        let options = DownloadOptions()
        return try await BackgroundWork.run { try await Self.fetchVideoInfo(url: url, options: options) }
    }

    static func fetchVideoInfo(url: String, options: DownloadOptions) async throws -> VideoInfo {
        guard FileManager.default.isExecutableFile(atPath: options.ytdlpPath) else { throw YTDLPError.notInstalled }
        var lastError = "No metadata returned"
        for cookies in (options.useBrowserCookies ? [true, false] : [false]) {
            let result = try await ProcessRunner().run(executable: options.ytdlpPath,
                arguments: ["--dump-single-json", "--skip-download"] + commonArgs(cookies: cookies, options: options) + ["--", url], timeout: 25)
            if result.exitCode == 0, let data = result.output.data(using: .utf8), let info = try? JSONDecoder().decode(VideoInfo.self, from: data) { return info }
            lastError = result.message
            if DownloadFailurePolicy.isSiteRestriction(lastError) { break }
        }
        throw YTDLPError.fetchFailed(DownloadFailurePolicy.explanation(lastError))
    }

    @MainActor func download(url: String, format: DownloadFormat, outputDirectory: URL,
                  progressHandler: @escaping @Sendable (Double, String) -> Void) async throws -> DownloadResult {
        let options = DownloadOptions()
        return try await BackgroundWork.run {
            try await Self.download(url: url, format: format, outputDirectory: outputDirectory, options: options, progressHandler: progressHandler)
        }
    }

    static func download(url: String, format: DownloadFormat, outputDirectory: URL, options: DownloadOptions,
                         progressHandler: @escaping @Sendable (Double, String) -> Void) async throws -> DownloadResult {
        guard FileManager.default.isExecutableFile(atPath: options.ytdlpPath) else { throw YTDLPError.notInstalled }
        let hasFFmpeg = FileManager.default.isExecutableFile(atPath: options.ffmpegPath)
        if format.isAudioOnly && !hasFFmpeg { throw YTDLPError.downloadFailed("ffmpeg is required for audio extraction. Install it in Settings.") }
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        var variants = format.ytdlpArgVariants
        if !hasFFmpeg, !format.isAudioOnly {
            let selector = format.maxHeight.map { "best[height<=\($0)]/best" } ?? "best"
            variants = [["-f", selector]]
        }
        var lastMessage = "Download failed"
        for cookies in (options.useBrowserCookies ? [true, false] : [false]) {
            for variant in variants {
                try Task.checkCancellation()
                var args = commonArgs(cookies: cookies, options: options) + variant + [
                    "-P", outputDirectory.path,
                    "-o", "%(title).160B [%(extractor_key)s-%(id)s] [\(format.storageKey)].%(ext)s",
                    "--newline", "--progress", "--progress-template", "download:__VV_PROGRESS__%(progress._percent_str)s",
                    "--print", "after_move:__VV_RESULT__%(.{filepath,id,extractor_key})j"
                ]
                args += options.skipDuplicates ? ["--no-overwrites"] : ["--force-overwrites"]
                if options.embedMetadata { args += ["--embed-metadata"] }
                if options.embedThumbnail && !format.isAudioOnly { args += ["--embed-thumbnail"] }
                args += ["--", url]
                let result = try await ProcessRunner().run(executable: options.ytdlpPath, arguments: args,
                    directory: outputDirectory, timeout: 180, inactivityTimeout: true) { line in
                    if line.hasPrefix("__VV_PROGRESS__") {
                        let value = line.dropFirst("__VV_PROGRESS__".count).replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)
                        if let percent = Double(value) { progressHandler(min(max(percent / 100, 0), 1), "Downloading") }
                    } else if line.contains("[Merger]") || line.contains("[ExtractAudio]") { progressHandler(0.99, "Converting") }
                }
                if result.exitCode == 0 { return try Self.downloadResult(output: result.output, directory: outputDirectory) }
                lastMessage = result.message
                if DownloadFailurePolicy.isSiteRestriction(lastMessage) { throw YTDLPError.downloadFailed(DownloadFailurePolicy.explanation(lastMessage)) }
                if !lastMessage.lowercased().contains("requested format is not available") { break }
                progressHandler(0, "Trying another available format")
            }
        }
        if options.enableFallbackDownloader {
            progressHandler(0, "Trying fallback downloader")
            do {
                return try await FallbackDownloader.download(url: url, format: format, directory: outputDirectory,
                    streamlink: options.streamlinkPath, ffmpeg: options.ffmpegPath, progress: progressHandler)
            } catch is CancellationError { throw CancellationError() }
            catch { lastMessage += "\n\nFallback: \(error.localizedDescription)" }
        }
        throw YTDLPError.downloadFailed(lastMessage)
    }

    static func downloadResult(output: String, directory: URL) throws -> DownloadResult {
        struct PrintedFile: Decodable { let filepath: String; let id: String?; let extractor_key: String? }
        for line in output.split(separator: "\n").reversed() where line.hasPrefix("__VV_RESULT__") {
            guard let record = try? JSONDecoder().decode(PrintedFile.self, from: Data(line.dropFirst("__VV_RESULT__".count).utf8)) else { continue }
            let file = URL(fileURLWithPath: record.filepath).standardizedFileURL
            guard file.resolvingSymlinksInPath().path.hasPrefix(directory.resolvingSymlinksInPath().path + "/"),
                  let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true, (values.fileSize ?? 0) > 0 else { continue }
            let identity = record.id.flatMap { id in record.extractor_key.map { "\($0.lowercased()):\(id)" } }
            return DownloadResult(file: file, mediaID: identity, downloader: "yt-dlp", skipped: output.contains("has already been downloaded"))
        }
        throw YTDLPError.fileNotFound
    }
}

enum YTDLPError: LocalizedError {
    case notInstalled, fetchFailed(String), downloadFailed(String), fileNotFound
    var errorDescription: String? {
        switch self {
        case .notInstalled: return "yt-dlp is not installed. Install it in Settings."
        case .fetchFailed(let msg): return "Info fetch failed: \(msg)"
        case .downloadFailed(let msg): return "Download failed: \(msg)"
        case .fileNotFound: return "The downloader finished without a valid output file. No unrelated file was selected."
        }
    }
}
