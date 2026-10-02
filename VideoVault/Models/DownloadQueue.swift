import Foundation
import Combine

class DownloadQueue: ObservableObject {
    static let shared = DownloadQueue()

    @Published var items: [DownloadItem] = []

    private let saveURL: URL

    init(saveURL: URL? = nil) {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = saveURL?.deletingLastPathComponent()
            ?? ProcessInfo.processInfo.environment["VIDEOVAULT_TEST_ROOT"].map { URL(fileURLWithPath: $0) }
            ?? appSupport.appendingPathComponent("VideoVault")
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        self.saveURL = saveURL ?? appDir.appendingPathComponent("download_queue.json")
        self.items = loadItems()
        for index in items.indices where items[index].status.isActive { items[index].status = .queued }
        save()
    }

    // MARK: - Query

    var activeItems: [DownloadItem] {
        items.filter { $0.status.isActive }
    }

    var queuedItems: [DownloadItem] {
        items.filter { if case .queued = $0.status { return true }; return false }
    }

    var completedItems: [DownloadItem] {
        items.filter { $0.status == .completed || $0.status == .skipped }
    }

    var failedItems: [DownloadItem] {
        items.filter { if case .error = $0.status { return true }; return false }
    }

    var totalCompleted: Int { completedItems.count }
    var totalQueued: Int { queuedItems.count }
    var totalActive: Int { activeItems.count }
    var totalFailed: Int { failedItems.count }

    // MARK: - Mutations

    func addItem(_ item: DownloadItem) {
        items.insert(item, at: 0)
        save()
    }

    func addItems(_ newItems: [DownloadItem]) {
        items.insert(contentsOf: newItems, at: 0)
        save()
    }

    func updateItem(_ item: DownloadItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
            save()
        }
    }

    func removeItem(_ item: DownloadItem) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func removeItems(_ itemsToRemove: [DownloadItem]) {
        let ids = Set(itemsToRemove.map { $0.id })
        items.removeAll { ids.contains($0.id) }
        save()
    }

    func clearCompleted() {
        items.removeAll { $0.status == .completed || $0.status == .skipped }
        save()
    }

    func clearAll() {
        items.removeAll { !$0.status.isActive }
        save()
    }

    func retryFailed() {
        for i in items.indices {
            if case .error = items[i].status {
                items[i].status = .queued
                items[i].errorMessage = nil
            }
        }
        save()
    }

    func cancelItem(_ item: DownloadItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index].status = .cancelled
            save()
        }
    }

    // MARK: - Persistence

    private func save() {
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: saveURL, options: .atomic)
        } catch {
            print("Failed to save download queue: \(error)")
        }
    }

    private func loadItems() -> [DownloadItem] {
        guard FileManager.default.fileExists(atPath: saveURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: saveURL)
            return try JSONDecoder().decode([DownloadItem].self, from: data)
        } catch {
            print("Failed to load download queue: \(error)")
            return []
        }
    }
}
