import XCTest
import AppKit
@testable import VideoVaultCore

final class VideoVaultCoreTests: XCTestCase {
    func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("VideoVaultTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    func testYouTubeIdentityAcrossURLForms() {
        let reference = DownloadIdentity.canonicalURL("https://www.youtube.com/watch?v=abc123")
        for url in ["https://youtu.be/abc123?t=2", "https://m.youtube.com/shorts/abc123?feature=share", "https://youtube.com/embed/abc123", "https://youtube.com/watch?v=abc123&list=playlist"] {
            XCTAssertEqual(DownloadIdentity.canonicalURL(url), reference)
        }
        XCTAssertNotEqual(DownloadIdentity.key(url: reference, mediaID: nil, format: .bestVideo), DownloadIdentity.key(url: reference, mediaID: nil, format: .bestAudio))
    }

    func testDuplicateIndexChecksDestinationFormatAndFileExistence() async throws {
        let root = try temporaryDirectory()
        let other = try temporaryDirectory()
        let file = root.appendingPathComponent("saved.mp4")
        try Data("real media bytes".utf8).write(to: file)
        let library = DuplicateLibrary()
        try await library.remember(url: "https://youtu.be/abc", mediaID: "youtube:abc", format: .bestVideo, file: file, root: root)
        let found = await library.existing(url: "https://youtube.com/shorts/abc", mediaID: nil, format: .bestVideo, root: root)
        XCTAssertEqual(found, file)
        let wrongFormat = await library.existing(url: "https://youtu.be/abc", mediaID: nil, format: .mp3, root: root)
        let wrongFolder = await library.existing(url: "https://youtu.be/abc", mediaID: nil, format: .bestVideo, root: other)
        XCTAssertNil(wrongFormat)
        XCTAssertNil(wrongFolder)
        try FileManager.default.removeItem(at: file)
        let missing = await library.existing(url: "https://youtu.be/abc", mediaID: nil, format: .bestVideo, root: root)
        XCTAssertNil(missing)
    }

    func testDuplicateScannerChecksBytesAndNestedFiles() throws {
        let root = try temporaryDirectory()
        let nested = root.appendingPathComponent("subfolder")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data("same".utf8).write(to: root.appendingPathComponent("one.mp4"))
        try Data("same".utf8).write(to: nested.appendingPathComponent("two.mkv"))
        try Data("diff".utf8).write(to: root.appendingPathComponent("different.mp4"))
        try Data("same".utf8).write(to: root.appendingPathComponent("incomplete.part"))
        let groups = try DuplicateScanner.scanFiles(root: root, progress: { _ in })
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.files.count, 2)
        XCTAssertEqual(groups.first?.reclaimableBytes, 4)
    }

    func testSingleFileIsNeverMistakenForItsSymlinkAlias() async throws {
        let root = try temporaryDirectory()
        let file = root.appendingPathComponent("only.mp4")
        try Data("irreplaceable".utf8).write(to: file)
        let match = try DuplicateScanner.existingCopy(of: file, root: root.resolvingSymlinksInPath())
        XCTAssertNil(match)
        let result = try await DuplicateLibrary().coalesce(DownloadResult(file: file, mediaID: nil, downloader: "test", skipped: false), root: root.resolvingSymlinksInPath())
        XCTAssertFalse(result.skipped)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func testReservationCancellation() async throws {
        let library = DuplicateLibrary()
        let root = try temporaryDirectory()
        try await library.acquire("same-media", root: root)
        let waiting = Task { try await library.acquire("same-media", root: root) }
        try await Task.sleep(nanoseconds: 50_000_000)
        waiting.cancel()
        do { try await waiting.value; XCTFail("Wait should have cancelled") } catch { XCTAssertTrue(error is CancellationError) }
        await library.release("same-media", root: root)
        try await library.acquire("same-media", root: root)
        await library.release("same-media", root: root)
    }

    func testBothProcessPipesDrainWithoutDeadlock() async throws {
        let result = try await ProcessRunner().run(executable: "/bin/sh",
            arguments: ["-c", "head -c 300000 /dev/zero; head -c 300000 /dev/zero >&2; printf '\\ncomplete\\n'"], timeout: 5)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.hasSuffix("complete\n"))
        XCTAssertEqual(result.errorOutput.utf8.count, 300000)
    }

    func testTimeoutStopsProcessAndChild() async throws {
        let started = Date()
        do {
            _ = try await ProcessRunner().run(executable: "/bin/sh", arguments: ["-c", "sleep 30"], timeout: 0.2)
            XCTFail("Expected timeout")
        } catch { XCTAssertTrue(error is ProcessFailure) }
        XCTAssertLessThan(Date().timeIntervalSince(started), 4)
    }

    func testCancellationStopsProcessAndChild() async throws {
        let started = Date()
        let task = Task { try await ProcessRunner().run(executable: "/bin/sh", arguments: ["-c", "sleep 30"], timeout: 40) }
        try await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertLessThan(Date().timeIntervalSince(started), 4)
    }

    func testOutputCannotSelectAnUnrelatedFile() throws {
        let root = try temporaryDirectory()
        let elsewhere = try temporaryDirectory()
        let file = root.appendingPathComponent("correct.mp4")
        let unrelated = elsewhere.appendingPathComponent("wrong.mp4")
        try Data("media".utf8).write(to: file)
        try Data("wrong".utf8).write(to: unrelated)
        XCTAssertThrowsError(try YTDLPService.downloadResult(output: "[download] Done", directory: root))
        let outside = "__VV_RESULT__{\"filepath\":\"\(unrelated.path)\",\"id\":\"1\",\"extractor_key\":\"Generic\"}"
        XCTAssertThrowsError(try YTDLPService.downloadResult(output: outside, directory: root))
        let output = "__VV_RESULT__{\"filepath\":\"\(file.path)\",\"id\":\"1\",\"extractor_key\":\"Generic\"}"
        let result = try YTDLPService.downloadResult(output: output, directory: root)
        XCTAssertEqual(result.file, file)
        XCTAssertEqual(result.mediaID, "generic:1")
    }

    func testFailureClassificationAndFormatFallbacks() {
        XCTAssertTrue(DownloadFailurePolicy.isSiteRestriction("The video was blocked for safety reasons. Submit a form."))
        XCTAssertTrue(DownloadFailurePolicy.isSiteRestriction("This video is DRM-protected"))
        XCTAssertFalse(DownloadFailurePolicy.isSiteRestriction("Unknown algorithm ID: 7; please report this issue"))
        XCTAssertTrue(DownloadFailurePolicy.isTransient("HTTP Error 503"))
        XCTAssertTrue(DownloadFormat.bestAudio.ytdlpArgs.contains("best"))
        XCTAssertFalse(DownloadFormat.bestAudio.ytdlpArgs.contains("m4a"))
        XCTAssertTrue(DownloadFormat.video720p.ytdlpArgs.contains(where: { $0.contains("height<=720") }))
    }

    @MainActor func testClipboardURLsAreValidated() {
        XCTAssertEqual(DownloadManager.urls(from: "https://example.com/a\nhttps://example.com/b"), ["https://example.com/a", "https://example.com/b"])
        XCTAssertTrue(DownloadManager.urls(from: "file:///etc/passwd javascript:alert(1) https://").isEmpty)
    }

    @MainActor func testNativeMenuHasLiveCountsAndBothQuickPasteCommands() async throws {
        guard ProcessInfo.processInfo.environment["VIDEOVAULT_TEST_ROOT"] != nil else { throw XCTSkip("Requires isolated queue.") }
        let queue = DownloadQueue.shared
        let originalItems = queue.items
        let originalVisible = AppSettings.shared.showInMenuBar
        AppSettings.shared.showInMenuBar = false
        defer { queue.items = originalItems; AppSettings.shared.showInMenuBar = originalVisible }
        var active = DownloadItem(url: "https://example.com/active", format: .bestVideo)
        active.status = .fetching
        var failed = DownloadItem(url: "https://example.com/failed", format: .bestAudio)
        failed.status = .error("fixture")
        queue.items = [active, failed, DownloadItem(url: "https://example.com/queued", format: .bestVideo)]
        let controller = MenuBarController()
        try await Task.sleep(nanoseconds: 100_000_000)
        let menu = NSMenu()
        controller.menuNeedsUpdate(menu)
        XCTAssertTrue(menu.items.contains { $0.title == "Active: 1   Queue: 1   Failed: 1" })
        XCTAssertNotNil(menu.items.first { $0.title == "Quick Paste: Best Video Quality" }?.action)
        XCTAssertNotNil(menu.items.first { $0.title == "Quick Paste: Best Audio Quality" }?.action)
        XCTAssertTrue(menu.items.first { $0.title == "Retry Failed" }?.isEnabled == true)
        queue.items = []
        try await Task.sleep(nanoseconds: 100_000_000)
        controller.menuNeedsUpdate(menu)
        XCTAssertTrue(menu.items.contains { $0.title == "Active: 0   Queue: 0   Failed: 0" })
        XCTAssertTrue(menu.items.first { $0.title == "Retry Failed" }?.isEnabled == false)
    }

    @MainActor func testQuickPasteSelectsVideoAndOriginalAudioWithoutDuplicateQueueEntries() async throws {
        guard ProcessInfo.processInfo.environment["VIDEOVAULT_TEST_ROOT"] != nil else { throw XCTSkip("Requires isolated queue.") }
        let manager = DownloadManager.shared
        let queue = DownloadQueue.shared
        let originalItems = queue.items
        let originalPath = AppSettings.shared.ytdlpPath
        AppSettings.shared.ytdlpPath = "/missing/test-yt-dlp"
        queue.items = []
        defer { queue.items = originalItems; AppSettings.shared.ytdlpPath = originalPath }
        manager.quickPaste(format: .bestVideo, text: "https://youtu.be/fixture https://youtube.com/watch?v=fixture")
        XCTAssertEqual(queue.items.count, 1)
        XCTAssertEqual(queue.items.first?.format, .bestVideo)
        manager.quickPaste(format: .bestAudio, text: "https://youtu.be/fixture")
        XCTAssertEqual(queue.items.count, 2)
        XCTAssertTrue(queue.items.contains { $0.format == .bestAudio })
        manager.cancelAllDownloads()
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(manager.isProcessing)
    }
}
