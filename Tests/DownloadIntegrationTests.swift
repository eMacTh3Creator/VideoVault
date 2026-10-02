import XCTest
import Network
import CryptoKit
@testable import VideoVaultCore

final class LocalMediaServer: @unchecked Sendable {
    private let listener: NWListener
    private let bytes: Data
    private let queue = DispatchQueue(label: "VideoVaultTestHTTP")

    init(bytes: Data) throws {
        self.bytes = bytes
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [bytes] connection in
            connection.start(queue: DispatchQueue.global())
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, _ in
                let request = data.map { String(decoding: $0, as: UTF8.self) } ?? ""
                let head = request.hasPrefix("HEAD ")
                var response = Data("HTTP/1.1 200 OK\r\nContent-Type: video/mp4\r\nContent-Length: \(bytes.count)\r\nConnection: close\r\n\r\n".utf8)
                if !head { response.append(bytes) }
                connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
            }
        }
    }
    func start() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [weak self] state in
                if case .ready = state, let port = self?.listener.port {
                    self?.listener.stateUpdateHandler = nil
                    continuation.resume(returning: URL(string: "http://127.0.0.1:\(port)/sample.mp4")!)
                } else if case .failed(let error) = state {
                    self?.listener.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                }
            }
            listener.start(queue: queue)
        }
    }
    func stop() { listener.cancel() }
}

final class DownloadIntegrationTests: XCTestCase {
    @MainActor func testOfficialDependencyInstallation() async throws {
        guard ProcessInfo.processInfo.environment["VIDEOVAULT_VERIFY_DEPENDENCIES"] == "1",
              ProcessInfo.processInfo.environment["VIDEOVAULT_TEST_ROOT"] != nil else {
            throw XCTSkip("Set VIDEOVAULT_VERIFY_DEPENDENCIES=1 and VIDEOVAULT_TEST_ROOT to test live official dependency installation.")
        }
        let settings = AppSettings.shared
        let original = (settings.ytdlpPath, settings.streamlinkPath)
        defer { settings.ytdlpPath = original.0; settings.streamlinkPath = original.1 }
        settings.ytdlpPath = "/missing/yt-dlp"
        let service = DependencyUpdateService.shared
        await service.checkAndUpdate(install: true)
        XCTAssertFalse(service.isBusy)
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: settings.ytdlpPath), service.status)
        XCTAssertEqual(service.installedVersion, service.latestVersion, service.status)
        await service.installStreamlink()
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: settings.streamlinkPath), service.status)
        let version = try await ProcessRunner().run(executable: settings.streamlinkPath, arguments: ["--version"], timeout: 15)
        XCTAssertEqual(version.exitCode, 0)
        let plugins = try await ProcessRunner().run(executable: settings.streamlinkPath, arguments: ["--plugins"], timeout: 15)
        XCTAssertTrue(plugins.output.contains("twitch"))
    }

    func testChecksumValidationRejectsCorruptUpdates() async throws {
        let data = Data("fixture download".utf8)
        let server = try LocalMediaServer(bytes: data)
        let url = try await server.start()
        defer { server.stop() }
        let invalid = ReleaseAsset(name: "fixture", browserDownloadURL: url, digest: "sha256:" + String(repeating: "0", count: 64))
        do { _ = try await VerifiedDownload.asset(invalid); XCTFail("Corrupt checksum must be rejected") }
        catch { XCTAssertTrue(error.localizedDescription.contains("checksum")) }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let valid = ReleaseAsset(name: "fixture", browserDownloadURL: url, digest: "sha256:" + digest)
        let file = try await VerifiedDownload.asset(valid)
        defer { try? FileManager.default.removeItem(at: file) }
        XCTAssertEqual(try Data(contentsOf: file), data)
    }

    @MainActor func testRealVideoAudioAndDirectFallback() async throws {
        guard let ytdlp = YTDLPService.findExecutable("yt-dlp"), let ffmpeg = YTDLPService.findExecutable("ffmpeg") else {
            throw XCTSkip("Real integration requires yt-dlp and ffmpeg on the test Mac.")
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("VideoVaultIntegration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let sample = root.appendingPathComponent("source.mp4")
        let generated = try await ProcessRunner().run(executable: ffmpeg, arguments: ["-nostdin", "-hide_banner", "-loglevel", "error",
            "-f", "lavfi", "-i", "testsrc=size=160x120:rate=10", "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=44100",
            "-t", "1", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac", sample.path])
        XCTAssertEqual(generated.exitCode, 0, generated.message)
        let server = try LocalMediaServer(bytes: Data(contentsOf: sample))
        let url = try await server.start()
        defer { server.stop() }
        let settings = AppSettings.shared
        let original = (settings.ytdlpPath, settings.ffmpegPath, settings.useBrowserCookies, settings.embedMetadata, settings.embedThumbnail, settings.enableFallbackDownloader, settings.skipDuplicates)
        defer {
            settings.ytdlpPath = original.0; settings.ffmpegPath = original.1; settings.useBrowserCookies = original.2
            settings.embedMetadata = original.3; settings.embedThumbnail = original.4; settings.enableFallbackDownloader = original.5; settings.skipDuplicates = original.6
        }
        settings.ytdlpPath = ytdlp
        settings.ffmpegPath = ffmpeg
        settings.useBrowserCookies = false
        settings.embedMetadata = false
        settings.embedThumbnail = false
        settings.enableFallbackDownloader = false
        settings.skipDuplicates = true
        let info = try await YTDLPService.shared.fetchVideoInfo(url: url.absoluteString)
        XCTAssertNotNil(info.mediaID)
        let directory = root.appendingPathComponent("output")
        let video = try await YTDLPService.shared.download(url: url.absoluteString, format: .video720p, outputDirectory: directory, progressHandler: { _, _ in })
        XCTAssertTrue(FileManager.default.fileExists(atPath: video.file.path))
        XCTAssertTrue(video.file.lastPathComponent.contains("[720p]"))
        let same = try await YTDLPService.shared.download(url: url.absoluteString, format: .video720p, outputDirectory: directory, progressHandler: { _, _ in })
        XCTAssertEqual(same.file, video.file)
        let audio = try await YTDLPService.shared.download(url: url.absoluteString, format: .bestAudio, outputDirectory: directory, progressHandler: { _, _ in })
        XCTAssertNotEqual(audio.file, video.file)
        XCTAssertEqual(audio.file.pathExtension, "m4a")
        let fallback = try await FallbackDownloader.download(url: url.absoluteString, format: .bestVideo, directory: directory,
            streamlink: "/missing/streamlink", ffmpeg: ffmpeg, progress: { _, _ in })
        XCTAssertEqual(fallback.downloader, "ffmpeg (direct media)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fallback.file.path))
        let probe = YTDLPService.findExecutable("ffprobe")!
        let streams = try await ProcessRunner().run(executable: probe, arguments: ["-v", "error", "-show_entries", "stream=codec_type", "-of", "json", audio.file.path])
        XCTAssertTrue(streams.output.contains("audio"))
        XCTAssertFalse(streams.output.contains("video"))
    }

    func testConcurrentContentCoalescingKeepsACopyAndAllURLs() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("VideoVaultCoalesce-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("a.mp4")
        let second = root.appendingPathComponent("b.mp4")
        let third = root.appendingPathComponent("c.mp4")
        try Data("same contents".utf8).write(to: first)
        try Data("same contents".utf8).write(to: second)
        try Data("same contents".utf8).write(to: third)
        let library = DuplicateLibrary()
        let a = DownloadResult(file: first, mediaID: "generic:a", downloader: "test", skipped: false)
        let b = DownloadResult(file: second, mediaID: "generic:b", downloader: "test", skipped: false)
        let c = DownloadResult(file: third, mediaID: "generic:c", downloader: "test", skipped: false)
        async let resultA = library.coalesce(a, root: root)
        async let resultB = library.coalesce(b, root: root)
        async let resultC = library.coalesce(c, root: root)
        let results = try await [resultA, resultB, resultC]
        XCTAssertEqual(results[0].file.resolvingSymlinksInPath(), results[1].file.resolvingSymlinksInPath())
        XCTAssertEqual(results[0].file.resolvingSymlinksInPath(), results[2].file.resolvingSymlinksInPath())
        XCTAssertTrue(FileManager.default.fileExists(atPath: results[0].file.path))
        for (index, result) in results.enumerated() {
            try await library.remember(url: "https://example.com/\(index)", mediaID: result.mediaID, format: .bestVideo, file: result.file, root: root)
        }
        for index in 0..<3 {
            let copy = await library.existing(url: "https://example.com/\(index)", mediaID: nil, format: .bestVideo, root: root)
            XCTAssertNotNil(copy)
        }
    }

    @MainActor func testQueueRecoversInterruptedDownloadsWithoutLosingHistory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("VideoVaultQueue-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var active = DownloadItem(url: "https://example.com/active", format: .bestVideo)
        active.status = .downloading(progress: 0.4)
        var completed = DownloadItem(url: "https://example.com/complete", format: .mp3)
        completed.status = .completed
        let file = root.appendingPathComponent("queue.json")
        try JSONEncoder().encode([active, completed]).write(to: file)
        let queue = DownloadQueue(saveURL: file)
        XCTAssertEqual(queue.items.count, 2)
        XCTAssertEqual(queue.items.first?.status, .queued)
        XCTAssertEqual(queue.items.last?.status, .completed)
    }
}
