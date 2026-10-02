import XCTest
import Darwin
@testable import VideoVaultCore

final class RecoveryTests: XCTestCase {
    let unsafe = "ERROR: The extracted extension ('v1692889884') is unusual and will be skipped for safety reasons. If you believe this is an error, please report this issue on https://github.com/yt-dlp/yt-dlp/issues?q= , filling out the appropriate issue template. Confirm you are on the latest version using yt-dlp -U"

    func testExactScreenshotErrorIsNotASiteRestriction() {
        XCTAssertTrue(DownloadFailurePolicy.isUnsafeExtension(unsafe))
        XCTAssertFalse(DownloadFailurePolicy.isSiteRestriction(unsafe))
        XCTAssertFalse(DownloadFailurePolicy.explanation(unsafe).contains("website refused"))
        for restriction in ["This video is DRM-protected", "The video was blocked for safety reasons", "Login required"] {
            XCTAssertTrue(DownloadFailurePolicy.isSiteRestriction(unsafe + "\n" + restriction))
            XCTAssertTrue(DownloadFailurePolicy.isSiteRestriction(unsafe + " " + restriction))
        }
        XCTAssertFalse(DownloadFailurePolicy.explanation(unsafe + "\nThis video is DRM-protected").contains("website refused"))
    }

    @MainActor func testThumbnailRetryIsBoundedAndRetainsSecurityChecks() async throws {
        let root = try fixture(mode: "thumbnail")
        let result = try await download(root)
        XCTAssertEqual(result.downloader, "yt-dlp")
        let calls = try calls(root)
        XCTAssertEqual(calls.count, 2)
        XCTAssertTrue(calls[0].args.contains("--embed-thumbnail"))
        XCTAssertFalse(calls[1].args.contains("--embed-thumbnail"))
        XCTAssertTrue(calls[1].args.contains("--no-write-thumbnail"))
        XCTAssertTrue(calls[1].args.contains("--no-embed-thumbnail"))
        XCTAssertTrue(calls[1].args.contains("--embed-metadata"))
        assertSecurity(calls)
    }

    @MainActor func testTechnicalFailuresReachIndependentBackup() async throws {
        for mode in ["unsafe", "invalid-output", "pipe-open"] {
            let root = try fixture(mode: mode)
            let result = try await download(root, force: mode == "invalid-output")
            XCTAssertEqual(result.downloader, "Streamlink", mode)
            XCTAssertTrue(FileManager.default.fileExists(atPath: result.file.path))
            let calls = try calls(root)
            XCTAssertEqual(calls.filter { $0.tool == "yt-dlp" }.count, mode == "unsafe" ? 2 : 1)
            XCTAssertEqual(calls.filter { $0.tool == "streamlink" }.count, 2)
            XCTAssertEqual(calls.filter { $0.tool == "ffmpeg" }.count, 1)
            assertSecurity(calls)
        }
    }

    @MainActor func testUnsupportedBackupRetainsBothErrors() async throws {
        let root = try fixture(mode: "unsafe", extra: ["unsupported": true])
        do { _ = try await download(root); XCTFail("Expected unsupported backup failure") }
        catch {
            XCTAssertTrue(error.localizedDescription.contains("v1692889884"))
            XCTAssertTrue(error.localizedDescription.contains("Streamlink has no plugin"))
            XCTAssertFalse(error.localizedDescription.contains("website refused"))
        }
        XCTAssertEqual(try calls(root).filter { $0.tool == "yt-dlp" }.count, 2)
    }

    @MainActor func testForceNeverOverridesRealRestrictionsOrCancellation() async throws {
        for mode in ["restricted", "mixed-restriction"] {
            let root = try fixture(mode: mode)
            do { _ = try await download(root, force: true); XCTFail("Restriction must remain an error") }
            catch { XCTAssertTrue(error.localizedDescription.contains("DRM-protected")) }
            XCTAssertEqual(try calls(root).count, 1)
        }
        let root = try fixture(mode: "cancel")
        let options = options(root, force: true)
        let task = Task {
            try await YTDLPService.download(url: "https://example.com/recovery", format: .bestVideo,
                outputDirectory: root.appendingPathComponent("output"), options: options, progressHandler: { _, _ in })
        }
        try await waitUntil { FileManager.default.fileExists(atPath: root.appendingPathComponent("started").path) }
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(try calls(root).count, 1)
        let pid = try XCTUnwrap(Int32(String(contentsOf: root.appendingPathComponent("started"))))
        XCTAssertEqual(kill(pid, 0), -1)
    }

    @MainActor func testForceOverridesOnlyOptionalPerJobSettingsAndOldQueuesDecode() throws {
        let root = try fixture(mode: "force")
        let settings = AppSettings.shared
        let before = (settings.embedMetadata, settings.embedThumbnail, settings.enableFallbackDownloader)
        let normal = options(root)
        let forced = options(root, force: true, fallback: false)
        XCTAssertTrue(normal.embedMetadata); XCTAssertTrue(normal.embedThumbnail)
        XCTAssertFalse(forced.embedMetadata); XCTAssertFalse(forced.embedThumbnail)
        XCTAssertTrue(forced.enableFallbackDownloader)
        XCTAssertEqual(settings.embedMetadata, before.0)
        XCTAssertEqual(settings.embedThumbnail, before.1)
        XCTAssertEqual(settings.enableFallbackDownloader, before.2)
        var item = DownloadItem(url: "https://example.com/recovery", format: .bestVideo)
        let legacy = try JSONEncoder().encode(item)
        XCTAssertNil(try JSONDecoder().decode(DownloadItem.self, from: legacy).forceRecovery)
        item.forceRecovery = true
        XCTAssertEqual(try JSONDecoder().decode(DownloadItem.self, from: JSONEncoder().encode(item)).forceRecovery, true)
    }

    @MainActor func testManagerForceRetryPersistsAndCompletesAfterNormalFailure() async throws {
        guard ProcessInfo.processInfo.environment["VIDEOVAULT_TEST_ROOT"] != nil else { throw XCTSkip("Requires isolated queue") }
        let root = try fixture(mode: "force")
        let settings = AppSettings.shared
        let old = (settings.ytdlpPath, settings.ffmpegPath, settings.streamlinkPath, settings.downloadPath,
                   settings.embedMetadata, settings.embedThumbnail, settings.enableFallbackDownloader,
                   settings.notificationsEnabled, settings.skipDuplicates, settings.organizeBySource)
        let queue = DownloadQueue.shared
        let oldItems = queue.items
        let manager = DownloadManager.shared
        defer {
            settings.ytdlpPath = old.0; settings.ffmpegPath = old.1; settings.streamlinkPath = old.2; settings.downloadPath = old.3
            settings.embedMetadata = old.4; settings.embedThumbnail = old.5; settings.enableFallbackDownloader = old.6
            settings.notificationsEnabled = old.7; settings.skipDuplicates = old.8; settings.organizeBySource = old.9
            queue.items = oldItems
        }
        settings.ytdlpPath = root.appendingPathComponent("yt-dlp").path
        settings.ffmpegPath = root.appendingPathComponent("ffmpeg").path
        settings.streamlinkPath = root.appendingPathComponent("streamlink").path
        settings.downloadPath = root.appendingPathComponent("output").path
        settings.embedMetadata = true; settings.embedThumbnail = true; settings.enableFallbackDownloader = false
        settings.notificationsEnabled = false; settings.skipDuplicates = false; settings.organizeBySource = false
        queue.items = []
        manager.addURLs(["https://example.com/recovery"], format: .bestVideo)
        try await waitUntil { !manager.isProcessing }
        let failed = try XCTUnwrap(queue.items.first)
        XCTAssertTrue(failed.status.canRetry)
        manager.retryItem(failed, forceRecovery: true)
        try await waitUntil { !manager.isProcessing }
        XCTAssertEqual(queue.items.first?.status, .completed)
        XCTAssertEqual(queue.items.first?.forceRecovery, true)
        XCTAssertEqual(try calls(root).filter { $0.args.contains("--embed-metadata") }.count, 1)
        XCTAssertTrue(settings.embedMetadata); XCTAssertTrue(settings.embedThumbnail)
        XCTAssertFalse(settings.enableFallbackDownloader)
        await queue.flushPersistence()
        try JSONSerialization.data(withJSONObject: ["mode": "metadata-unsafe"])
            .write(to: root.appendingPathComponent("config.json"))
        queue.items = []
        manager.addURLs(["https://example.com/recovery"], format: .bestVideo)
        try await waitUntil { !manager.isProcessing }
        let metadataFailed = try XCTUnwrap(queue.items.first)
        XCTAssertTrue(metadataFailed.status.canRetry)
        manager.retryItem(metadataFailed, forceRecovery: true)
        try await waitUntil { !manager.isProcessing }
        XCTAssertEqual(queue.items.first?.status, .completed)
        XCTAssertEqual(queue.items.first?.downloader, "Streamlink")
        XCTAssertFalse(settings.enableFallbackDownloader)
        await queue.flushPersistence()
        let completed = try XCTUnwrap(queue.items.first)
        manager.retryItem(completed)
        XCTAssertNil(queue.items.first?.forceRecovery)
        await manager.stopAndWait()
        await queue.flushPersistence()
    }

    @MainActor func testRealYTDLPRecoversMalformedThumbnailFilename() async throws {
        guard let actual = YTDLPService.findExecutable("yt-dlp"), let ffmpeg = YTDLPService.findExecutable("ffmpeg") else {
            throw XCTSkip("Requires real yt-dlp and ffmpeg")
        }
        let root = try fixture(mode: "real-thumbnail")
        let sample = root.appendingPathComponent("sample.mp4")
        let generated = try await ProcessRunner().run(executable: ffmpeg, arguments: ["-nostdin", "-hide_banner", "-loglevel", "error",
            "-f", "lavfi", "-i", "testsrc=size=160x120:rate=10", "-t", "1", "-c:v", "libx264", "-pix_fmt", "yuv420p", sample.path])
        XCTAssertEqual(generated.exitCode, 0, generated.message)
        let server = try LocalMediaServer(bytes: Data(contentsOf: sample))
        let url = try await server.start()
        defer { server.stop() }
        let infoFile = root.appendingPathComponent("info.json")
        let info: [String: Any] = ["id": "recovery", "title": "Recovery", "extractor": "generic", "extractor_key": "Generic",
            "webpage_url": url.absoluteString, "url": url.absoluteString, "ext": "mp4",
            "thumbnail": url.deletingLastPathComponent().appendingPathComponent("poster.jpg.v1692889884").absoluteString]
        try JSONSerialization.data(withJSONObject: info).write(to: infoFile)
        try JSONSerialization.data(withJSONObject: ["mode": "real-thumbnail", "real_ytdlp": actual, "info_file": infoFile.path])
            .write(to: root.appendingPathComponent("config.json"))
        let messages = LockedOutput()
        let result = try await YTDLPService.download(url: url.absoluteString, format: .bestVideo,
            outputDirectory: root.appendingPathComponent("output"), options: options(root, realFFmpeg: ffmpeg, fallback: false), progressHandler: { _, status in
                messages.append(Data((status + "\n").utf8))
            })
        XCTAssertEqual(result.downloader, "yt-dlp")
        XCTAssertTrue(messages.text.contains("Retrying without thumbnail embedding"), messages.text)
        XCTAssertEqual(try calls(root).count, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.file.path))
    }

    private struct Call: Decodable { let tool: String; let args: [String] }
    private func calls(_ root: URL) throws -> [Call] {
        try String(contentsOf: root.appendingPathComponent("calls.jsonl")).split(separator: "\n")
            .map { try JSONDecoder().decode(Call.self, from: Data($0.utf8)) }
    }
    private func assertSecurity(_ calls: [Call]) {
        XCTAssertFalse(calls.flatMap(\.args).contains { $0.contains("allow-unsafe-ext") || $0 == "--allow-unplayable-formats" })
    }
    private func fixture(mode: String, extra: [String: Any] = [:]) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Recovery-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let source = try XCTUnwrap(Bundle.module.url(forResource: "recovery_tools", withExtension: "py", subdirectory: "Fixtures"))
        for name in ["yt-dlp", "streamlink", "ffmpeg"] {
            let target = root.appendingPathComponent(name)
            try FileManager.default.copyItem(at: source, to: target)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: target.path)
        }
        var config = extra
        config["mode"] = mode
        try JSONSerialization.data(withJSONObject: config).write(to: root.appendingPathComponent("config.json"))
        return root
    }
    @MainActor private func options(_ root: URL, force: Bool = false, realFFmpeg: String? = nil, fallback: Bool = true) -> DownloadOptions {
        let settings = AppSettings.shared
        let old = (settings.ytdlpPath, settings.ffmpegPath, settings.streamlinkPath, settings.embedMetadata,
                   settings.embedThumbnail, settings.useBrowserCookies, settings.enableFallbackDownloader)
        defer {
            settings.ytdlpPath = old.0; settings.ffmpegPath = old.1; settings.streamlinkPath = old.2
            settings.embedMetadata = old.3; settings.embedThumbnail = old.4
            settings.useBrowserCookies = old.5; settings.enableFallbackDownloader = old.6
        }
        settings.ytdlpPath = root.appendingPathComponent("yt-dlp").path
        settings.ffmpegPath = realFFmpeg ?? root.appendingPathComponent("ffmpeg").path
        settings.streamlinkPath = root.appendingPathComponent("streamlink").path
        settings.embedMetadata = true; settings.embedThumbnail = true; settings.useBrowserCookies = false
        settings.enableFallbackDownloader = fallback
        return DownloadOptions(forceRecovery: force)
    }
    @MainActor private func download(_ root: URL, force: Bool = false) async throws -> DownloadResult {
        try await YTDLPService.download(url: "https://example.com/recovery", format: .bestVideo,
            outputDirectory: root.appendingPathComponent("output"), options: options(root, force: force), progressHandler: { _, _ in })
    }
    @MainActor private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(10)
        while !condition() {
            guard Date() < deadline else { throw NSError(domain: "RecoveryTestTimeout", code: 1) }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}
