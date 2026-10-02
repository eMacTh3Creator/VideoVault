import XCTest
import AppKit
import Combine
import Darwin
@testable import VideoVaultCore

final class ResponsivenessTests: XCTestCase {
    func testExitedParentCannotHangOnInheritedPipe() async throws {
        let started = Date()
        do {
            _ = try await ProcessRunner().run(executable: "/bin/sh", arguments: ["-c", "sleep 2 & printf 'parent done\\n'"], timeout: 5)
            XCTFail("Inherited pipe should produce a bounded failure")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("output open"), error.localizedDescription)
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 1.8)
    }

    @MainActor func testSlowPersistenceDoesNotBlockUIAndKeepsLatestSnapshot() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("queue.json")
        let persistence = QueuePersistence(url: url) { data, file in
            XCTAssertFalse(Thread.isMainThread)
            Thread.sleep(forTimeInterval: 0.3)
            try data.write(to: file, options: .atomic)
        }
        var item = DownloadItem(url: "https://example.com/slow", format: .bestVideo)
        let started = Date()
        for index in 0..<10_000 {
            item.title = "Snapshot \(index)"
            persistence.save([item])
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.2)
        let flushing = Task { await persistence.flush() }
        let heartbeat = Date()
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertLessThan(Date().timeIntervalSince(heartbeat), 0.15)
        await flushing.value
        let saved = try JSONDecoder().decode([DownloadItem].self, from: Data(contentsOf: url))
        XCTAssertEqual(saved.first?.title, "Snapshot 9999")
    }

    func testProgressFloodIsBoundedAndClosedJobsIgnoreLateUpdates() async throws {
        let buffer = DownloadProgressBuffer(item: DownloadItem(url: "https://example.com/flood", format: .bestVideo))
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<4 {
                group.addTask {
                    for index in 0..<25_000 { buffer.progress(Double(index) / 25_000, status: "Downloading") }
                }
            }
        }
        buffer.progress(0.99, status: "Downloading")
        XCTAssertEqual(buffer.take()?.item.status, .downloading(progress: 0.99))
        XCTAssertNil(buffer.take())
        buffer.close()
        buffer.progress(1, status: "Downloading")
        XCTAssertNil(buffer.take())
    }

    @MainActor func testMenuActionsWaitForCloseAndStatsUpdateWithoutRebuilding() async throws {
        guard ProcessInfo.processInfo.environment["VIDEOVAULT_TEST_ROOT"] != nil else { throw XCTSkip("Requires isolated queue") }
        let queue = DownloadQueue.shared
        let oldItems = queue.items
        defer { queue.items = oldItems }
        queue.items = []
        let controller = MenuBarController()
        let menu = NSMenu()
        controller.menuNeedsUpdate(menu)
        controller.menuWillOpen(menu)
        let originalButton = menu.items.first { $0.title == "Quick Paste: Best Video Quality" }
        var executed = false
        controller.afterMenuCloses { executed = true }
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertFalse(executed)
        var active = DownloadItem(url: "https://example.com/active", format: .bestVideo)
        active.status = .downloading(progress: 0.5)
        queue.items = [active]
        XCTAssertEqual(menu.items[1].title, "Active: 1   Queue: 0   Failed: 0")
        XCTAssertTrue(originalButton === menu.items.first { $0.title == "Quick Paste: Best Video Quality" })
        controller.menuDidClose(menu)
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertTrue(executed)
    }

    @MainActor func testAddAndCancelDuringConcurrentProgressFloodKeepsUIResponsive() async throws {
        guard ProcessInfo.processInfo.environment["VIDEOVAULT_TEST_ROOT"] != nil else { throw XCTSkip("Requires isolated queue") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fixture = try XCTUnwrap(Bundle.module.url(forResource: "mock_ytdlp", withExtension: "py", subdirectory: "Fixtures"))
        let executable = root.appendingPathComponent("yt-dlp")
        try FileManager.default.copyItem(at: fixture, to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let settings = AppSettings.shared
        let oldPath = settings.downloadPath, oldTool = settings.ytdlpPath
        let oldConcurrency = settings.maxConcurrentDownloads
        let oldOrganize = settings.organizeBySource, oldDuplicates = settings.skipDuplicates
        let oldNotifications = settings.notificationsEnabled
        let queue = DownloadQueue.shared
        let oldItems = queue.items
        let manager = DownloadManager.shared
        defer {
            manager.cancelAllDownloads()
            queue.items = oldItems
            settings.downloadPath = oldPath; settings.ytdlpPath = oldTool
            settings.maxConcurrentDownloads = oldConcurrency
            settings.organizeBySource = oldOrganize; settings.skipDuplicates = oldDuplicates
            settings.notificationsEnabled = oldNotifications
            try? FileManager.default.removeItem(at: root)
        }
        settings.downloadPath = root.path; settings.ytdlpPath = executable.path
        settings.maxConcurrentDownloads = 2; settings.organizeBySource = false
        settings.skipDuplicates = false; settings.notificationsEnabled = false
        queue.items = []
        var publications = 0
        let observation = queue.$items.sink { _ in publications += 1 }
        defer { observation.cancel() }
        manager.addURLs(["https://example.com/first"], format: .bestVideo)
        try await waitUntil { FileManager.default.fileExists(atPath: root.appendingPathComponent("first.started").path) }
        let controller = MenuBarController()
        let menu = NSMenu()
        controller.menuNeedsUpdate(menu); controller.menuWillOpen(menu)
        var added = false
        controller.afterMenuCloses {
            manager.quickPaste(format: .bestVideo, text: "https://example.com/second")
            added = true
        }
        XCTAssertFalse(added)
        controller.menuDidClose(menu)
        try await waitUntil { FileManager.default.fileExists(atPath: root.appendingPathComponent("second.started").path) }
        XCTAssertTrue(added)
        XCTAssertEqual(queue.counts.active, 2)
        manager.addURLs(["https://example.com/third"], format: .bestVideo)
        XCTAssertEqual(queue.counts.queued, 1)
        let first = try XCTUnwrap(queue.items.first { $0.url.hasSuffix("/first") })
        let cancelling = Date()
        manager.cancelDownload(first)
        XCTAssertLessThan(Date().timeIntervalSince(cancelling), 0.1)
        try await waitUntil { FileManager.default.fileExists(atPath: root.appendingPathComponent("third.started").path) }
        var maxDelay = 0.0
        for _ in 0..<50 {
            let tick = Date()
            try await Task.sleep(nanoseconds: 20_000_000)
            maxDelay = max(maxDelay, Date().timeIntervalSince(tick))
        }
        XCTAssertLessThan(maxDelay, 0.25, "UI heartbeat stalled under progress load")
        try await waitUntil { !manager.isProcessing }
        XCTAssertEqual(queue.items.first { $0.url.hasSuffix("/first") }?.status, .cancelled)
        XCTAssertEqual(queue.items.first { $0.url.hasSuffix("/second") }?.status, .completed)
        XCTAssertEqual(queue.items.first { $0.url.hasSuffix("/third") }?.status, .completed)
        XCTAssertLessThan(publications, 80, "Progress lines should not flood SwiftUI")
        let pidText = try String(contentsOf: root.appendingPathComponent("first.started"))
        let pid = try XCTUnwrap(Int32(pidText))
        XCTAssertEqual(kill(pid, 0), -1, "Cancelled subprocess survived")
        manager.addURLs(["https://example.com/shutdown"], format: .bestVideo)
        try await waitUntil { FileManager.default.fileExists(atPath: root.appendingPathComponent("shutdown.started").path) }
        let stopping = Task { await manager.stopAndWait() }
        let heartbeat = Date()
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertLessThan(Date().timeIntervalSince(heartbeat), 0.25)
        await stopping.value
        XCTAssertFalse(manager.isProcessing)
        XCTAssertEqual(queue.items.first { $0.url.hasSuffix("/shutdown") }?.status, .cancelled)
        let shutdownPID = try XCTUnwrap(Int32(String(contentsOf: root.appendingPathComponent("shutdown.started"))))
        XCTAssertEqual(kill(shutdownPID, 0), -1, "Shutdown returned before the subprocess stopped")
        await queue.flushPersistence()
        print("Responsiveness stress: max UI heartbeat \(maxDelay)s, \(publications) publications for 240,000+ progress lines")
    }

    @MainActor private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(12)
        while !condition() {
            guard Date() < deadline else { throw NSError(domain: "ResponsivenessTestTimeout", code: 1) }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}
