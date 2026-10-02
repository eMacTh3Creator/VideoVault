import Foundation
import Combine

struct QueueCounts: Equatable, Sendable {
    var active = 0
    var queued = 0
    var completed = 0
    var failed = 0

    init(items: [DownloadItem] = []) {
        for item in items {
            if item.status.isActive { active += 1 }
            else if item.status == .queued { queued += 1 }
            else if item.status == .completed || item.status == .skipped { completed += 1 }
            else if case .error = item.status { failed += 1 }
        }
    }
}

// Coalesce writes and serialize them off the UI thread, including JSON encoding.
final class QueuePersistence: @unchecked Sendable {
    private let queue = DispatchQueue(label: "VideoVault.QueuePersistence", qos: .utility)
    private let lock = NSLock()
    private var pending: [DownloadItem]?
    private var scheduled = false
    private let url: URL
    private let writer: @Sendable (Data, URL) throws -> Void

    init(url: URL, writer: @escaping @Sendable (Data, URL) throws -> Void = { data, url in
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }) {
        self.url = url
        self.writer = writer
    }

    func save(_ items: [DownloadItem]) {
        lock.lock()
        pending = items
        let needsSchedule = !scheduled
        scheduled = true
        lock.unlock()
        if needsSchedule { queue.asyncAfter(deadline: .now() + 0.25) { self.drain() } }
    }

    func flush() async {
        await withCheckedContinuation { continuation in
            queue.async { self.drain(); continuation.resume() }
        }
    }

    private func drain() {
        lock.lock()
        let snapshot = pending
        pending = nil
        scheduled = false
        lock.unlock()
        guard let snapshot else { return }
        do { try writer(JSONEncoder().encode(snapshot), url) }
        catch { print("Failed to save download queue: \(error)") }
    }
}

@MainActor
final class DownloadQueue: ObservableObject {
    static let shared = DownloadQueue()
    @Published var items: [DownloadItem] = [] {
        didSet { counts = QueueCounts(items: items) }
    }
    @Published private(set) var counts = QueueCounts()
    private let persistence: QueuePersistence

    init(saveURL: URL? = nil) {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = saveURL?.deletingLastPathComponent()
            ?? ProcessInfo.processInfo.environment["VIDEOVAULT_TEST_ROOT"].map { URL(fileURLWithPath: $0) }
            ?? appSupport.appendingPathComponent("VideoVault")
        let url = saveURL ?? appDir.appendingPathComponent("download_queue.json")
        persistence = QueuePersistence(url: url)
        if let data = try? Data(contentsOf: url), let loaded = try? JSONDecoder().decode([DownloadItem].self, from: data) {
            items = loaded.map { item in
                var recovered = item
                if recovered.status.isActive { recovered.status = .queued }
                return recovered
            }
        }
        counts = QueueCounts(items: items)
        persistence.save(items)
    }

    var activeItems: [DownloadItem] { items.filter { $0.status.isActive } }
    var queuedItems: [DownloadItem] { items.filter { $0.status == .queued } }
    var completedItems: [DownloadItem] { items.filter { $0.status == .completed || $0.status == .skipped } }
    var failedItems: [DownloadItem] { items.filter { if case .error = $0.status { return true }; return false } }
    var totalCompleted: Int { counts.completed }
    var totalQueued: Int { counts.queued }
    var totalActive: Int { counts.active }
    var totalFailed: Int { counts.failed }

    func addItem(_ item: DownloadItem) { addItems([item]) }
    func addItems(_ newItems: [DownloadItem]) {
        guard !newItems.isEmpty else { return }
        items.insert(contentsOf: newItems, at: 0)
        persistence.save(items)
    }

    func updateItem(_ item: DownloadItem) { updateItems([item]) }
    func updateItems(_ changes: [DownloadItem]) {
        guard !changes.isEmpty else { return }
        let byID = Dictionary(changes.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        var snapshot = items
        var changed = false
        for index in snapshot.indices {
            if let replacement = byID[snapshot[index].id], replacement != snapshot[index] {
                snapshot[index] = replacement
                changed = true
            }
        }
        guard changed else { return }
        items = snapshot
        persistence.save(snapshot)
    }

    func removeItem(_ item: DownloadItem) { removeItems([item]) }
    func removeItems(_ removal: [DownloadItem]) {
        let ids = Set(removal.map(\.id))
        items.removeAll { ids.contains($0.id) }
        persistence.save(items)
    }
    func clearCompleted() {
        items.removeAll { $0.status == .completed || $0.status == .skipped }
        persistence.save(items)
    }
    func clearAll() {
        items.removeAll { !$0.status.isActive }
        persistence.save(items)
    }
    func retryFailed() {
        updateItems(failedItems.map { item in
            var updated = item
            updated.status = .queued
            updated.errorMessage = nil
            return updated
        })
    }
    func cancelItem(_ item: DownloadItem) {
        guard var live = items.first(where: { $0.id == item.id }) else { return }
        live.status = .cancelled
        updateItem(live)
    }
    func flushPersistence() async { await persistence.flush() }
}
