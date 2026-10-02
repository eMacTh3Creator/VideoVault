import Foundation
import AppKit
import UserNotifications

// A fast bounded mailbox: thousands of subprocess lines become one UI update per tick.
final class DownloadProgressBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var item: DownloadItem
    private var activity = ""
    private var dirty = false
    private var closed = false

    init(item: DownloadItem) { self.item = item }
    func publish(_ item: DownloadItem, activity: String) {
        lock.lock(); defer { lock.unlock() }
        guard !closed else { return }
        self.item = item
        self.activity = activity
        dirty = true
    }
    func progress(_ progress: Double, status: String) {
        lock.lock(); defer { lock.unlock() }
        guard !closed else { return }
        item.status = status.contains("Converting") ? .converting : .downloading(progress: min(max(progress, 0), 1))
        activity = "\(item.displayTitle): \(status)"
        dirty = true
    }
    func take() -> (item: DownloadItem, activity: String)? {
        lock.lock(); defer { lock.unlock() }
        guard dirty, !closed else { return nil }
        dirty = false
        return (item, activity)
    }
    func close() {
        lock.lock(); defer { lock.unlock() }
        closed = true
        dirty = false
    }
}

@MainActor
final class DownloadManager: ObservableObject {
    static let shared = DownloadManager()
    @Published private(set) var isProcessing = false
    @Published private(set) var currentActivity = ""
    @Published private(set) var clipboardStatus = ""
    private var activeTasks: [UUID: Task<Void, Never>] = [:]
    private var progressBuffers: [UUID: DownloadProgressBuffer] = [:]
    private var progressTimer: Timer?

    func processQueue() {
        isProcessing = !activeTasks.isEmpty
        guard !DependencyUpdateService.shared.isBusy else { return }
        let slots = max(0, min(8, max(1, AppSettings.shared.maxConcurrentDownloads)) - activeTasks.count)
        for item in DownloadQueue.shared.queuedItems.prefix(slots) { startDownload(item) }
        isProcessing = !activeTasks.isEmpty
        if !isProcessing {
            progressTimer?.invalidate()
            progressTimer = nil
            currentActivity = ""
        }
    }

    func startDownload(_ item: DownloadItem) {
        guard activeTasks[item.id] == nil else { return }
        var current = item
        current.status = .fetching
        let job = current
        let options = DownloadOptions(forceRecovery: item.forceRecovery == true)
        let history = DownloadQueue.shared.items
        let buffer = DownloadProgressBuffer(item: current)
        DownloadQueue.shared.updateItem(current)
        progressBuffers[item.id] = buffer
        activeTasks[item.id] = Task {
            var finished: DownloadItem
            do {
                finished = try await BackgroundWork.run {
                    await Self.performDownload(job, options: options, history: history, buffer: buffer)
                }
            } catch {
                finished = job
                finished.status = .cancelled
            }
            buffer.close()
            if Task.isCancelled { finished.status = .cancelled }
            DownloadQueue.shared.updateItem(finished)
            if finished.status == .completed { sendNotification(title: "Download Complete", body: finished.displayTitle) }
            progressBuffers.removeValue(forKey: item.id)
            activeTasks.removeValue(forKey: item.id)
            processQueue()
        }
        if progressTimer == nil {
            let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.flushProgress() }
            }
            // Common modes continue servicing progress while an AppKit menu tracks.
            RunLoop.main.add(timer, forMode: .common)
            progressTimer = timer
        }
        isProcessing = true
    }

    private func flushProgress() {
        let updates = progressBuffers.values.compactMap { $0.take() }
        let activeIDs = Set(DownloadQueue.shared.activeItems.map(\.id))
        let live = updates.filter { activeIDs.contains($0.item.id) }
        DownloadQueue.shared.updateItems(live.map(\.item))
        if let last = live.last { currentActivity = last.activity }
    }

    func cancelDownload(_ item: DownloadItem) {
        progressBuffers[item.id]?.close()
        activeTasks[item.id]?.cancel()
        DownloadQueue.shared.cancelItem(item)
        // Keep the slot until this worker and its subprocesses have actually stopped.
        processQueue()
    }

    func cancelAllDownloads() {
        for buffer in progressBuffers.values { buffer.close() }
        for task in activeTasks.values { task.cancel() }
        let cancelled = (DownloadQueue.shared.activeItems + DownloadQueue.shared.queuedItems).map { item in
            var updated = item
            updated.status = .cancelled
            return updated
        }
        DownloadQueue.shared.updateItems(cancelled)
        isProcessing = !activeTasks.isEmpty
        currentActivity = isProcessing ? "Stopping downloads..." : ""
    }

    func stopAndWait() async {
        cancelAllDownloads()
        while !activeTasks.isEmpty { try? await Task.sleep(nanoseconds: 20_000_000) }
    }

    func retryItem(_ item: DownloadItem, forceRecovery: Bool = false) {
        guard activeTasks[item.id] == nil else { return }
        var updated = item
        updated.status = .queued
        updated.errorMessage = nil
        updated.retryCount = 0
        updated.forceRecovery = forceRecovery ? true : nil
        DownloadQueue.shared.updateItem(updated)
        processQueue()
    }

    func retryAllFailed() {
        for item in DownloadQueue.shared.failedItems where activeTasks[item.id] == nil { retryItem(item) }
    }

    nonisolated static func urls(from text: String) -> [String] {
        text.components(separatedBy: .whitespacesAndNewlines).compactMap { value in
            let cleaned = value.trimmingCharacters(in: CharacterSet(charactersIn: "<>\""))
            guard let url = URL(string: cleaned), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { return nil }
            return cleaned
        }
    }

    func quickPaste(format: DownloadFormat, text: String? = nil) {
        let urls = Self.urls(from: text ?? NSPasteboard.general.string(forType: .string) ?? "")
        guard !urls.isEmpty else { clipboardStatus = "Clipboard has no valid HTTP or HTTPS URLs."; return }
        let count = addURLs(urls, format: format)
        clipboardStatus = count == 0 ? "These URLs are already active or queued." : "Added \(count) \(format.isAudioOnly ? "audio" : "video") download\(count == 1 ? "" : "s")."
    }

    @discardableResult func addURLs(_ urls: [String], format: DownloadFormat) -> Int {
        var seen = Set(DownloadQueue.shared.items.filter { $0.status.isActive || $0.status == .queued }
            .map { DownloadIdentity.key(url: $0.url, mediaID: nil, format: $0.format) })
        let newItems = urls.flatMap { Self.urls(from: $0) }.filter {
            seen.insert(DownloadIdentity.key(url: $0, mediaID: nil, format: format)).inserted
        }.map { DownloadItem(url: $0, format: format) }
        DownloadQueue.shared.addItems(newItems)
        processQueue()
        return newItems.count
    }

    // This entire pipeline executes in a detached worker with immutable settings.
    nonisolated private static func performDownload(_ item: DownloadItem, options: DownloadOptions,
                                                   history: [DownloadItem], buffer: DownloadProgressBuffer) async -> DownloadItem {
        let root = options.root
        var current = item
        var reservation: String?
        do {
            try Task.checkCancellation()
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            if options.skipDuplicates, let file = await DuplicateLibrary.shared.existing(url: item.url, mediaID: nil, format: item.format, root: root) {
                try Task.checkCancellation()
                finish(&current, result: DownloadResult(file: file, mediaID: nil, downloader: "Library", skipped: true))
                return current
            }
            if options.skipDuplicates, let prior = history.first(where: {
                ($0.status == .completed || $0.status == .skipped) && $0.format == item.format
                    && DownloadIdentity.canonicalURL($0.url) == DownloadIdentity.canonicalURL(item.url)
                    && $0.filePath.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path.hasPrefix(root.resolvingSymlinksInPath().path + "/") && FileManager.default.fileExists(atPath: $0) } == true
            }), let path = prior.filePath {
                try await DuplicateLibrary.shared.remember(url: item.url, mediaID: prior.mediaID, format: item.format, file: URL(fileURLWithPath: path), root: root)
                try Task.checkCancellation()
                finish(&current, result: DownloadResult(file: URL(fileURLWithPath: path), mediaID: prior.mediaID, downloader: "Library", skipped: true))
                return current
            }
            buffer.publish(current, activity: "\(options.forceRecovery ? "Force Retry" : "Fetching info"): \(current.displayTitle)")
            do {
                let info = try await YTDLPService.fetchVideoInfo(url: current.url, options: options)
                current.title = info.title
                current.thumbnailURL = info.thumbnailURL
                current.duration = info.duration
                current.source = info.source
                current.mediaID = info.mediaID
                buffer.publish(current, activity: "Fetching info: \(current.displayTitle)")
            } catch is CancellationError { throw CancellationError() }
            catch {
                if DownloadFailurePolicy.isSiteRestriction(error.localizedDescription) { throw error }
                current.title = current.url
            }
            try Task.checkCancellation()
            let key = DownloadIdentity.key(url: item.url, mediaID: current.mediaID, format: item.format)
            if options.skipDuplicates {
                try await DuplicateLibrary.shared.acquire(key, root: root)
                reservation = key
                if let file = await DuplicateLibrary.shared.existing(url: item.url, mediaID: current.mediaID, format: item.format, root: root) {
                    try Task.checkCancellation()
                    finish(&current, result: DownloadResult(file: file, mediaID: current.mediaID, downloader: "Library", skipped: true))
                    await DuplicateLibrary.shared.release(key, root: root)
                    return current
                }
            }
            let source = current.sourceName.components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_")).inverted).joined(separator: "_")
            let output = options.organizeBySource ? root.appendingPathComponent(source.isEmpty ? "Unknown" : source) : root
            var retries = 0
            while true {
                try Task.checkCancellation()
                current.status = .downloading(progress: 0)
                buffer.publish(current, activity: "Downloading: \(current.displayTitle)")
                do {
                    var result = try await YTDLPService.download(url: item.url, format: item.format, outputDirectory: output, options: options) {
                        buffer.progress($0, status: $1)
                    }
                    try Task.checkCancellation()
                    current.status = .converting
                    if options.skipDuplicates, !result.skipped {
                        buffer.publish(current, activity: "Checking destination for duplicate content...")
                        result = try await DuplicateLibrary.shared.coalesce(result, root: root)
                    }
                    do { try await DuplicateLibrary.shared.remember(url: item.url, mediaID: result.mediaID ?? current.mediaID, format: item.format, file: result.file, root: root) }
                    catch { current.errorMessage = "File saved, but duplicate index could not be updated: \(error.localizedDescription)" }
                    try Task.checkCancellation()
                    finish(&current, result: result)
                    break
                } catch {
                    try Task.checkCancellation()
                    guard options.autoRetryFailed, retries < 2, DownloadFailurePolicy.isTransient(error.localizedDescription),
                          !DownloadFailurePolicy.isSiteRestriction(error.localizedDescription) else { throw error }
                    retries += 1
                    current.retryCount = retries
                    buffer.publish(current, activity: "Retry \(retries)/2: \(current.displayTitle)")
                    try await Task.sleep(nanoseconds: UInt64(retries * 3) * 1_000_000_000)
                }
            }
        } catch {
            if error is CancellationError || Task.isCancelled { current.status = .cancelled }
            else { current.status = .error(error.localizedDescription); current.errorMessage = error.localizedDescription }
        }
        if let reservation { await DuplicateLibrary.shared.release(reservation, root: root) }
        return current
    }

    nonisolated private static func finish(_ item: inout DownloadItem, result: DownloadResult) {
        item.status = result.skipped ? .skipped : .completed
        item.filePath = result.file.path
        item.fileSize = (try? result.file.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
        item.mediaID = result.mediaID ?? item.mediaID
        item.downloader = result.downloader
        item.dateCompleted = Date()
    }

    private func sendNotification(title: String, body: String) {
        guard AppSettings.shared.notificationsEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
