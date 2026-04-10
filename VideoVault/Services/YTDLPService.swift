import Foundation

struct VideoInfo {
    let title: String
    let duration: String?
    let thumbnailURL: String?
    let source: String?
    let uploaderName: String?
}

class YTDLPService {
    static let shared = YTDLPService()
    private let settings = AppSettings.shared

    private init() {}

    private struct DownloadAttempt {
        let formatArgs: [String]
        let includeCookies: Bool
    }

    // MARK: - yt-dlp Availability

    func isYTDLPInstalled() -> Bool {
        FileManager.default.isExecutableFile(atPath: settings.ytdlpPath)
    }

    func findYTDLP() -> String? {
        let commonPaths = [
            "/opt/homebrew/bin/yt-dlp",
            "/usr/local/bin/yt-dlp",
            "/usr/bin/yt-dlp",
            NSHomeDirectory() + "/.local/bin/yt-dlp"
        ]
        for path in commonPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    // MARK: - ffmpeg Availability

    func isFFmpegInstalled() -> Bool {
        FileManager.default.isExecutableFile(atPath: settings.ffmpegPath)
    }

    func findFFmpeg() -> String? {
        let commonPaths = [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/usr/bin/ffmpeg",
            NSHomeDirectory() + "/.local/bin/ffmpeg"
        ]
        for path in commonPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    private func runProcess(
        executablePath: String,
        arguments: [String],
        timeout: TimeInterval = 5.0
    ) -> (output: String, success: Bool) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = Pipe()

        do { try process.run() } catch { return ("", false) }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        if process.isRunning { process.terminate(); return ("", false) }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (output, process.terminationStatus == 0)
    }

    func getVersion() -> String? {
        guard isYTDLPInstalled() else { return nil }
        let result = runProcess(executablePath: settings.ytdlpPath, arguments: ["--version"], timeout: 5.0)
        return result.success ? result.output : nil
    }

    // MARK: - Common Args

    private func commonArgs(includeCookies: Bool) -> [String] {
        var args: [String] = [
            "--no-warnings",
            "--no-check-certificates",
        ]
        if includeCookies, settings.useBrowserCookies, !settings.cookiesBrowser.isEmpty {
            args += ["--cookies-from-browser", settings.cookiesBrowser]
        }
        // Tell yt-dlp where ffmpeg is so it can merge streams and convert audio
        if isFFmpegInstalled() {
            let ffmpegDir = URL(fileURLWithPath: settings.ffmpegPath).deletingLastPathComponent().path
            args += ["--ffmpeg-location", ffmpegDir]
        }
        args += [
            "--extractor-args", "youtube:player_client=web,default;lang=en",
            "--user-agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        ]
        return args
    }

    // MARK: - Video Info (with timeout)

    func fetchVideoInfo(url: String) async throws -> VideoInfo {
        guard isYTDLPInstalled() else { throw YTDLPError.notInstalled }

        return try await withThrowingTaskGroup(of: VideoInfo.self) { group in
            group.addTask {
                try await self._fetchVideoInfo(url: url)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 15_000_000_000)
                throw YTDLPError.fetchFailed("Timed out")
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    private func _fetchVideoInfo(url: String) async throws -> VideoInfo {
        do {
            return try await fetchVideoInfo(url: url, includeCookies: settings.useBrowserCookies)
        } catch let error as YTDLPError {
            if settings.useBrowserCookies, shouldRetryWithoutCookies(error: error) {
                return try await fetchVideoInfo(url: url, includeCookies: false)
            }
            throw error
        }
    }

    private func fetchVideoInfo(url: String, includeCookies: Bool) async throws -> VideoInfo {
        let process = Process()
        let pipe = Pipe()
        let errorPipe = Pipe()

        var arguments = ["--dump-json", "--no-download"]
        arguments += commonArgs(includeCookies: includeCookies)
        arguments += [url]

        process.executableURL = URL(fileURLWithPath: settings.ytdlpPath)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = errorPipe

        return try await withCheckedThrowingContinuation { continuation in
            var resumed = false
            let lock = NSLock()
            var timeoutTask: DispatchWorkItem?

            func safeResume(with result: Result<VideoInfo, Error>) {
                lock.lock(); defer { lock.unlock() }
                guard !resumed else { return }
                resumed = true
                timeoutTask?.cancel()
                continuation.resume(with: result)
            }

            timeoutTask = DispatchWorkItem {
                guard process.isRunning else { return }
                process.terminate()
                safeResume(with: .failure(YTDLPError.fetchFailed("Timed out")))
            }

            func finish() {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

                guard process.terminationStatus == 0 else {
                    let errorMsg = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown error"
                    safeResume(with: .failure(YTDLPError.fetchFailed(errorMsg)))
                    return
                }

                guard !data.isEmpty,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    safeResume(with: .failure(YTDLPError.parseFailed))
                    return
                }

                let title = json["title"] as? String ?? "Unknown"
                let durationSec = json["duration"] as? Double
                let thumbnail = json["thumbnail"] as? String
                let extractor = json["extractor"] as? String
                let uploader = json["uploader"] as? String

                let duration: String? = durationSec.map { sec in
                    let mins = Int(sec) / 60
                    let secs = Int(sec) % 60
                    return String(format: "%d:%02d", mins, secs)
                }

                safeResume(with: .success(VideoInfo(
                    title: title, duration: duration, thumbnailURL: thumbnail,
                    source: extractor, uploaderName: uploader
                )))
            }

            do {
                try process.run()
                if let timeoutTask {
                    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 15, execute: timeoutTask)
                }
                DispatchQueue.global(qos: .utility).async {
                    process.waitUntilExit()
                    finish()
                }
            }
            catch { safeResume(with: .failure(YTDLPError.launchFailed)) }
        }
    }

    // MARK: - Download

    func download(
        url: String,
        format: DownloadFormat,
        outputDirectory: URL,
        progressHandler: @escaping (Double, String) -> Void
    ) async throws -> URL {
        guard isYTDLPInstalled() else { throw YTDLPError.notInstalled }

        // Ensure output directory exists
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        // Snapshot existing files BEFORE download so we can diff later
        let existingFiles = Set((try? FileManager.default.contentsOfDirectory(
            at: outputDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ))?.map { $0.lastPathComponent } ?? [])

        let attempts = downloadAttempts(for: format)
        var lastError: Error = YTDLPError.downloadFailed("Download failed")

        for (index, attempt) in attempts.enumerated() {
            do {
                return try await runDownloadAttempt(
                    url: url,
                    format: format,
                    outputDirectory: outputDirectory,
                    existingFiles: existingFiles,
                    attempt: attempt,
                    progressHandler: progressHandler
                )
            } catch let error as YTDLPError {
                lastError = error

                let hasMoreAttempts = index < attempts.count - 1
                guard hasMoreAttempts, shouldRetryDownload(error: error) else {
                    throw error
                }
            } catch {
                lastError = error
                throw error
            }
        }

        throw lastError
    }

    private func runDownloadAttempt(
        url: String,
        format: DownloadFormat,
        outputDirectory: URL,
        existingFiles: Set<String>,
        attempt: DownloadAttempt,
        progressHandler: @escaping (Double, String) -> Void
    ) async throws -> URL {
        let process = Process()
        let pipe = Pipe()
        let errorPipe = Pipe()

        let outputTemplate = outputDirectory.path + "/%(title)s.%(ext)s"

        var arguments = attempt.formatArgs
        arguments += [
            "-o", outputTemplate,
            "--newline",
            "--print", "after_move:filepath",
        ]
        arguments += commonArgs(includeCookies: attempt.includeCookies)

        if settings.embedThumbnail && !format.isAudioOnly {
            arguments += ["--embed-thumbnail"]
        }
        if settings.embedMetadata {
            arguments += ["--embed-metadata"]
        }

        arguments += [url]

        process.executableURL = URL(fileURLWithPath: settings.ytdlpPath)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = errorPipe
        process.currentDirectoryURL = outputDirectory

        return try await withCheckedThrowingContinuation { continuation in
            var resumed = false
            let lock = NSLock()
            var capturedPaths: [String] = []
            var allOutput = ""

            func safeResume(with result: Result<URL, Error>) {
                lock.lock(); defer { lock.unlock() }
                guard !resumed else { return }
                resumed = true
                continuation.resume(with: result)
            }

            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty,
                      let line = String(data: data, encoding: .utf8) else { return }

                lock.lock()
                allOutput += line
                lock.unlock()

                for singleLine in line.components(separatedBy: .newlines) {
                    let trimmed = singleLine.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { continue }

                    // Parse download progress
                    if trimmed.contains("%") && trimmed.contains("[download]") {
                        let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                        for part in parts {
                            let cleaned = part.replacingOccurrences(of: "%", with: "")
                            if let percent = Double(cleaned), percent > 0, percent <= 100 {
                                progressHandler(min(percent / 100.0, 1.0), trimmed)
                                break
                            }
                        }
                    }

                    // Capture any file path printed by --print after_move:filepath
                    // This line will NOT start with [ and will be a file path
                    if !trimmed.hasPrefix("[") && !trimmed.hasPrefix("WARNING") &&
                       !trimmed.hasPrefix("ERROR") && trimmed.contains("/") {
                        let possiblePath = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
                        if FileManager.default.fileExists(atPath: possiblePath) {
                            lock.lock()
                            capturedPaths.append(possiblePath)
                            lock.unlock()
                        }
                    }

                    // Also capture [download] Destination lines
                    if trimmed.contains("Destination:") {
                        let path = trimmed.components(separatedBy: "Destination:").last?
                            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        if !path.isEmpty {
                            lock.lock()
                            capturedPaths.append(path)
                            lock.unlock()
                        }
                    }

                    // Merging / converting progress
                    if trimmed.hasPrefix("[Merger]") || trimmed.hasPrefix("[ExtractAudio]") ||
                       trimmed.contains("Merging") || trimmed.contains("Converting") {
                        progressHandler(0.99, "Converting...")
                    }
                }
            }

            func finish() {
                pipe.fileHandleForReading.readabilityHandler = nil

                if process.terminationStatus == 0 {
                    // Strategy 1: Use path from --print after_move:filepath
                    lock.lock()
                    let paths = capturedPaths
                    lock.unlock()

                    for path in paths.reversed() {
                        if FileManager.default.fileExists(atPath: path) {
                            safeResume(with: .success(URL(fileURLWithPath: path)))
                            return
                        }
                    }

                    // Strategy 2: Find new files that weren't there before
                    if let newFile = self.findNewFile(in: outputDirectory, excluding: existingFiles) {
                        safeResume(with: .success(newFile))
                        return
                    }

                    // Strategy 3: Newest file in directory
                    if let newest = self.newestFile(in: outputDirectory) {
                        safeResume(with: .success(newest))
                        return
                    }

                    // Strategy 4: Check parent directory too
                    let parentDir = outputDirectory.deletingLastPathComponent()
                    if let newInParent = self.findNewFile(in: parentDir, excluding: []) {
                        safeResume(with: .success(newInParent))
                        return
                    }

                    safeResume(with: .failure(YTDLPError.fileNotFound))
                } else {
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorMsg = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Download failed"

                    // Also include stdout for debugging
                    lock.lock()
                    let output = allOutput
                    lock.unlock()

                    let fullError = errorMsg.isEmpty ? output : errorMsg
                    safeResume(with: .failure(YTDLPError.downloadFailed(fullError)))
                }
            }

            do {
                try process.run()
                DispatchQueue.global(qos: .utility).async {
                    process.waitUntilExit()
                    finish()
                }
            }
            catch { safeResume(with: .failure(YTDLPError.launchFailed)) }
        }
    }

    private func downloadAttempts(for format: DownloadFormat) -> [DownloadAttempt] {
        let cookieModes = settings.useBrowserCookies && !settings.cookiesBrowser.isEmpty
            ? [true, false]
            : [false]

        var attempts: [DownloadAttempt] = []
        var seenKeys = Set<String>()

        for includeCookies in cookieModes {
            for formatArgs in format.ytdlpArgVariants {
                let key = "\(includeCookies)|\(formatArgs.joined(separator: " "))"
                guard seenKeys.insert(key).inserted else { continue }
                attempts.append(DownloadAttempt(formatArgs: formatArgs, includeCookies: includeCookies))
            }
        }

        return attempts
    }

    private func shouldRetryDownload(error: YTDLPError) -> Bool {
        switch error {
        case .downloadFailed(let message):
            let normalized = message.lowercased()
            return normalized.contains("requested format is not available")
                || normalized.contains("operation not permitted")
                || normalized.contains("cookies")
                || normalized.contains("browser")
                || normalized.contains("failed to decrypt")
        default:
            return false
        }
    }

    private func shouldRetryWithoutCookies(error: YTDLPError) -> Bool {
        switch error {
        case .fetchFailed(let message), .downloadFailed(let message):
            let normalized = message.lowercased()
            return normalized.contains("operation not permitted")
                || normalized.contains("cookies")
                || normalized.contains("browser")
                || normalized.contains("failed to decrypt")
        default:
            return false
        }
    }

    /// Find files in directory that weren't in the existing set
    private func findNewFile(in directory: URL, excluding existingFiles: Set<String>) -> URL? {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        let newFiles = files.filter {
            !$0.hasDirectoryPath &&
            !existingFiles.contains($0.lastPathComponent) &&
            !$0.lastPathComponent.hasSuffix(".part") &&
            !$0.lastPathComponent.hasSuffix(".ytdl") &&
            !$0.lastPathComponent.hasSuffix(".temp")
        }

        // Return the newest new file
        return newFiles.sorted { url1, url2 in
            let date1 = (try? url1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            let date2 = (try? url2.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            return date1 > date2
        }.first
    }

    private func newestFile(in directory: URL) -> URL? {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        return files
            .filter {
                !$0.hasDirectoryPath &&
                !$0.lastPathComponent.hasSuffix(".part") &&
                !$0.lastPathComponent.hasSuffix(".ytdl") &&
                !$0.lastPathComponent.hasSuffix(".temp")
            }
            .sorted { url1, url2 in
                let date1 = (try? url1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let date2 = (try? url2.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return date1 > date2
            }
            .first
    }
}

// MARK: - Errors

enum YTDLPError: LocalizedError {
    case notInstalled, launchFailed, fetchFailed(String), parseFailed
    case downloadFailed(String), fileNotFound, cancelled

    var errorDescription: String? {
        switch self {
        case .notInstalled: return "yt-dlp is not installed"
        case .launchFailed: return "Failed to launch yt-dlp"
        case .fetchFailed(let msg): return "Info fetch failed: \(msg)"
        case .parseFailed: return "Failed to parse video info"
        case .downloadFailed(let msg): return "Download failed: \(msg)"
        case .fileNotFound: return "Downloaded file not found"
        case .cancelled: return "Cancelled"
        }
    }
}
