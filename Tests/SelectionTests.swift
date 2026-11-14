import XCTest
import Combine
import Darwin
@testable import VideoVaultCore

final class SelectionTests: XCTestCase {
    func testSelectionUsesStableIDsAndCurrentQueueOrder() {
        var first = DownloadItem(url: "https://example.com/first", format: .bestVideo)
        var second = DownloadItem(url: "https://example.com/second", format: .mp3)
        let third = DownloadItem(url: "https://example.com/third", format: .bestVideo)
        let ids: Set<UUID> = [first.id, second.id, UUID()]
        let before = DownloadSelection(ids: ids, in: [first, second, third])
        XCTAssertEqual(before.items.map(\.id), [first.id, second.id])
        first.status = .downloading(progress: 0.75)
        first.title = "Updated metadata"
        second.status = .error("fixture")
        let after = DownloadSelection(ids: ids, in: [first, second, third])
        XCTAssertEqual(after.ids, before.ids)
        XCTAssertEqual(after.items.first?.title, "Updated metadata")
        XCTAssertEqual(after.items.first?.status, .downloading(progress: 0.75))
        XCTAssertEqual(after.copiedURLs, "https://example.com/first\nhttps://example.com/second")
    }

    func testFilteringRemovalAndContextTargetsCannotIncludeHiddenRows() {
        let items = (0..<20).map { DownloadItem(url: "https://example.com/\($0)", format: .bestVideo) }
        let allIDs = Set(items.map(\.id))
        let visible = Array(items[5..<9])
        let selected = DownloadSelection(ids: allIDs, in: visible)
        XCTAssertEqual(selected.ids, Set(visible.map(\.id)))
        XCTAssertEqual(selected.items.count, 4)
        let contextTarget = DownloadSelection(ids: [items[12].id], in: items)
        XCTAssertEqual(contextTarget.items.map(\.id), [items[12].id])
        XCTAssertTrue(DownloadSelection(ids: allIDs, in: []).items.isEmpty)
        XCTAssertEqual(DownloadSelection(ids: allIDs, in: Array(visible.dropFirst())).items.count, 3)
    }

    func testMixedSelectionHasSafeActionEligibility() {
        var failed = DownloadItem(url: "https://example.com/failed", format: .bestVideo)
        failed.status = .error("fixture")
        var cancelled = DownloadItem(url: "https://example.com/cancelled", format: .bestVideo)
        cancelled.status = .cancelled
        var active = DownloadItem(url: "https://example.com/active", format: .bestVideo)
        active.status = .fetching
        active.filePath = "/tmp/previous-output.mkv"
        let queued = DownloadItem(url: "https://example.com/queued", format: .bestVideo)
        var completed = DownloadItem(url: "https://example.com/completed", format: .bestVideo)
        completed.status = .completed; completed.filePath = "/tmp/saved.mkv"
        var skipped = DownloadItem(url: "https://example.com/skipped", format: .bestVideo)
        skipped.status = .skipped; skipped.filePath = completed.filePath
        let items = [failed, cancelled, active, queued, completed, skipped]
        let selection = DownloadSelection(ids: Set(items.map(\.id)), in: items)
        XCTAssertEqual(selection.retryableIDs, [failed.id, cancelled.id])
        XCTAssertEqual(selection.cancellableIDs, [active.id, queued.id])
        XCTAssertEqual(selection.fileURLs, [URL(fileURLWithPath: "/tmp/saved.mkv")])
    }

    @MainActor func testBatchForceRetryOnlyChangesEligibleSelectedRows() async throws {
        try await withManager { manager, queue, _ in
            var failed = DownloadItem(url: "https://example.com/failed", format: .bestVideo)
            failed.status = .error("fixture"); failed.retryCount = 7; failed.errorMessage = "fixture"
            var cancelled = DownloadItem(url: "https://example.com/cancelled", format: .bestVideo)
            cancelled.status = .cancelled
            var completed = DownloadItem(url: "https://example.com/completed", format: .bestVideo)
            completed.status = .completed
            var untouched = DownloadItem(url: "https://example.com/untouched", format: .bestVideo)
            untouched.status = .error("leave me alone")
            queue.items = [failed, cancelled, completed, untouched]
            var snapshots = [[DownloadItem]]()
            let observation = queue.$items.dropFirst().sink { snapshots.append($0) }
            defer { observation.cancel() }
            manager.retryItems([failed.id, cancelled.id, completed.id, UUID()], forceRecovery: true)
            let batch = try XCTUnwrap(snapshots.first)
            XCTAssertTrue(batch.prefix(2).allSatisfy { $0.status == .queued && $0.forceRecovery == true && $0.retryCount == 0 && $0.errorMessage == nil })
            XCTAssertEqual(batch[2], completed); XCTAssertEqual(batch[3], untouched)
            try await waitUntil { !manager.isProcessing }
            XCTAssertTrue(queue.items.prefix(2).allSatisfy { $0.status == .completed && $0.forceRecovery == true })
            XCTAssertEqual(queue.items[2], completed); XCTAssertEqual(queue.items[3], untouched)
            var retry = queue.items[0]
            retry.status = .error("again")
            queue.updateItem(retry)
            manager.retryItems([retry.id])
            XCTAssertNil(queue.items.first?.forceRecovery)
            try await waitUntil { !manager.isProcessing }
        }
    }

    @MainActor func testLargeBatchPublishesOnceInsteadOfOncePerItem() async throws {
        try await withManager { manager, queue, _ in
            queue.items = (0..<2_000).map { index in
                var item = DownloadItem(url: "https://example.com/item-\(index)", format: .bestVideo)
                item.status = .error("fixture")
                return item
            }
            let ids = Set(queue.items.map(\.id))
            var publications = 0
            let observation = queue.$items.dropFirst().sink { _ in publications += 1 }
            defer { observation.cancel() }
            manager.retryItems(ids, forceRecovery: true)
            // One batch change plus the single available worker entering fetching.
            XCTAssertEqual(publications, 2)
            XCTAssertTrue(queue.items.allSatisfy { $0.forceRecovery == true })
            manager.cancelItems(ids)
            try await waitUntil { !manager.isProcessing }
            XCTAssertTrue(queue.items.allSatisfy { $0.status == .cancelled })
        }
    }

    @MainActor func testBulkCancelAndRemovalStopWorkersWithoutDeletingFilesOrRestoringRows() async throws {
        try await withManager { manager, queue, root in
            var untouched = DownloadItem(url: "https://example.com/untouched", format: .bestVideo)
            untouched.status = .error("keep")
            queue.items = [untouched]
            manager.addURLs(["https://example.com/first"], format: .bestVideo)
            try await waitUntil { FileManager.default.fileExists(atPath: root.appendingPathComponent("first.started").path) }
            let first = try XCTUnwrap(queue.items.first { $0.url.hasSuffix("/first") })
            manager.addURLs(["https://example.com/second", "https://example.com/third"], format: .bestVideo)
            let second = try XCTUnwrap(queue.items.first { $0.url.hasSuffix("/second") })
            let third = try XCTUnwrap(queue.items.first { $0.url.hasSuffix("/third") })
            manager.cancelItems([first.id, second.id])
            try await waitUntil { FileManager.default.fileExists(atPath: root.appendingPathComponent("third.started").path) }
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("second.started").path))
            let file = root.appendingPathComponent("keep.mkv")
            try Data("keep this file".utf8).write(to: file)
            var completed = DownloadItem(url: "https://example.com/saved", format: .bestVideo)
            completed.status = .completed; completed.filePath = file.path
            queue.addItem(completed)
            manager.removeItems([first.id, second.id, third.id, completed.id])
            try await waitUntil { !manager.isProcessing }
            XCTAssertEqual(queue.items, [untouched])
            XCTAssertEqual(try Data(contentsOf: file), Data("keep this file".utf8))
            for name in ["first", "third"] {
                let pid = try XCTUnwrap(Int32(String(contentsOf: root.appendingPathComponent("\(name).started"))))
                XCTAssertEqual(kill(pid, 0), -1)
            }
            await queue.flushPersistence()
        }
    }

    @MainActor private func withManager(_ body: (DownloadManager, DownloadQueue, URL) async throws -> Void) async throws {
        guard ProcessInfo.processInfo.environment["VIDEOVAULT_TEST_ROOT"] != nil else { throw XCTSkip("Requires isolated queue") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SelectionTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fixture = try XCTUnwrap(Bundle.module.url(forResource: "mock_ytdlp", withExtension: "py", subdirectory: "Fixtures"))
        let tool = root.appendingPathComponent("yt-dlp")
        try FileManager.default.copyItem(at: fixture, to: tool)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        let settings = AppSettings.shared
        let old = (settings.ytdlpPath, settings.ffmpegPath, settings.downloadPath, settings.maxConcurrentDownloads,
                   settings.organizeBySource, settings.skipDuplicates, settings.notificationsEnabled, settings.autoRetryFailed)
        let manager = DownloadManager.shared
        let queue = DownloadQueue.shared
        let oldItems = queue.items
        defer {
            settings.ytdlpPath = old.0; settings.ffmpegPath = old.1; settings.downloadPath = old.2; settings.maxConcurrentDownloads = old.3
            settings.organizeBySource = old.4; settings.skipDuplicates = old.5; settings.notificationsEnabled = old.6; settings.autoRetryFailed = old.7
            queue.items = oldItems
            try? FileManager.default.removeItem(at: root)
        }
        settings.ytdlpPath = tool.path; settings.ffmpegPath = ""; settings.downloadPath = root.path; settings.maxConcurrentDownloads = 1
        settings.organizeBySource = false; settings.skipDuplicates = false; settings.notificationsEnabled = false; settings.autoRetryFailed = false
        do {
            try await body(manager, queue, root)
            await manager.stopAndWait()
            await queue.flushPersistence()
        } catch {
            await manager.stopAndWait()
            await queue.flushPersistence()
            throw error
        }
    }

    @MainActor private func waitUntil(_ predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(20)
        while !predicate() {
            guard Date() < deadline else { throw NSError(domain: "SelectionTestTimeout", code: 1) }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}
