import Foundation
import AppKit
import UserNotifications

@MainActor
final class DownloadManager: ObservableObject {
    static let shared = DownloadManager()
    @Published private(set) var isProcessing = false
    @Published private(set) var currentActivity = ""
    @Published private(set) var clipboardStatus = ""
    private var activeTasks: [UUID: Task<Void, Never>] = [:]
    private var progressTokens: [UUID: UUID] = [:]

    func processQueue() {
        let queue = DownloadQueue.shared
        isProcessing = !activeTasks.isEmpty
        guard !DependencyUpdateService.shared.isBusy else { return }
        let slots = max(0, min(8, max(1, AppSettings.shared.maxConcurrentDownloads)) - activeTasks.count)
        for item in queue.queuedItems.prefix(slots) { startDownload(item) }
        isProcessing = !activeTasks.isEmpty
        if !isProcessing { currentActivity = "" }
    }

    func startDownload(_ item: DownloadItem) {
        guard activeTasks[item.id] == nil else { return }
        var current = item
        current.status = .fetching
        DownloadQueue.shared.updateItem(current)
        activeTasks[item.id] = Task { await performDownload(current) }
        isProcessing = true
    }

    func cancelDownload(_ item: DownloadItem) {
        progressTokens.removeValue(forKey: item.id)
        activeTasks[item.id]?.cancel()
        DownloadQueue.shared.cancelItem(item)
        // Retain the slot until the child process has actually stopped.
        processQueue()
    }

    func cancelAllDownloads() {
        progressTokens.removeAll()
        for task in activeTasks.values { task.cancel() }
        for item in DownloadQueue.shared.activeItems + DownloadQueue.shared.queuedItems { DownloadQueue.shared.cancelItem(item) }
        isProcessing = !activeTasks.isEmpty
        currentActivity = activeTasks.isEmpty ? "" : "Stopping downloads..."
    }

    func retryItem(_ item: DownloadItem) {
        guard activeTasks[item.id] == nil else { return }
        var updated = item
        updated.status = .queued
        updated.errorMessage = nil
        updated.retryCount = 0
        DownloadQueue.shared.updateItem(updated)
        processQueue()
    }

    func retryAllFailed() {
        for item in DownloadQueue.shared.failedItems where activeTasks[item.id] == nil { retryItem(item) }
    }

    static func urls(from text: String) -> [String] {
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

    private func performDownload(_ item: DownloadItem) async {
        defer {
            progressTokens.removeValue(forKey: item.id)
            activeTasks.removeValue(forKey: item.id)
            processQueue()
        }
        let root = AppSettings.shared.downloadURL.standardizedFileURL
        let skipDuplicates = AppSettings.shared.skipDuplicates
        var current = item
        var reservation: String?
        do {
            try Task.checkCancellation()
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            if skipDuplicates, let file = await DuplicateLibrary.shared.existing(url: item.url, mediaID: nil, format: item.format, root: root) {
                try Task.checkCancellation()
                finish(&current, result: DownloadResult(file: file, mediaID: nil, downloader: "Library", skipped: true))
                return
            }
            if skipDuplicates, let prior = DownloadQueue.shared.completedItems.first(where: {
                $0.format == item.format && DownloadIdentity.canonicalURL($0.url) == DownloadIdentity.canonicalURL(item.url)
                    && $0.filePath.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path.hasPrefix(root.resolvingSymlinksInPath().path + "/") && FileManager.default.fileExists(atPath: $0) } == true
            }), let path = prior.filePath {
                let file = URL(fileURLWithPath: path)
                try await DuplicateLibrary.shared.remember(url: item.url, mediaID: prior.mediaID, format: item.format, file: file, root: root)
                try Task.checkCancellation()
                finish(&current, result: DownloadResult(file: file, mediaID: prior.mediaID, downloader: "Library", skipped: true))
                return
            }
            currentActivity = "Fetching info: \(current.displayTitle)"
            do {
                let info = try await YTDLPService.shared.fetchVideoInfo(url: current.url)
                current.title = info.title
                current.thumbnailURL = info.thumbnailURL
                current.duration = info.duration
                current.source = info.source
                current.mediaID = info.mediaID
                DownloadQueue.shared.updateItem(current)
            } catch is CancellationError { throw CancellationError() }
            catch {
                if DownloadFailurePolicy.isSiteRestriction(error.localizedDescription) { throw error }
                // Metadata is optional; a slow or broken info lookup must not strand the queue.
                current.title = current.url
            }
            try Task.checkCancellation()
            let key = DownloadIdentity.key(url: item.url, mediaID: current.mediaID, format: item.format)
            if skipDuplicates {
                try await DuplicateLibrary.shared.acquire(key, root: root)
                reservation = key
                if let file = await DuplicateLibrary.shared.existing(url: item.url, mediaID: current.mediaID, format: item.format, root: root) {
                    try Task.checkCancellation()
                    finish(&current, result: DownloadResult(file: file, mediaID: current.mediaID, downloader: "Library", skipped: true))
                    await DuplicateLibrary.shared.release(key, root: root)
                    return
                }
            }
            let output = AppSettings.shared.organizeBySource
                ? root.appendingPathComponent(current.sourceName.components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_")).inverted).joined(separator: "_")) : root
            let token = UUID()
            progressTokens[item.id] = token
            var retries = 0
            while true {
                current.status = .downloading(progress: 0)
                DownloadQueue.shared.updateItem(current)
                do {
                    var result = try await YTDLPService.shared.download(url: item.url, format: item.format, outputDirectory: output) { [weak self] progress, statusText in
                        Task { @MainActor in
                            guard let self, self.progressTokens[item.id] == token,
                                  var live = DownloadQueue.shared.items.first(where: { $0.id == item.id }), live.status.isActive else { return }
                            live.status = statusText.contains("Converting") ? .converting : .downloading(progress: progress)
                            self.currentActivity = "\(live.displayTitle): \(statusText)"
                            DownloadQueue.shared.updateItem(live)
                        }
                    }
                    try Task.checkCancellation()
                    progressTokens.removeValue(forKey: item.id)
                    if skipDuplicates, !result.skipped {
                        currentActivity = "Checking destination for duplicate content..."
                        result = try await DuplicateLibrary.shared.coalesce(result, root: root)
                    }
                    do { try await DuplicateLibrary.shared.remember(url: item.url, mediaID: result.mediaID ?? current.mediaID, format: item.format, file: result.file, root: root) }
                    catch { current.errorMessage = "File saved, but duplicate index could not be updated: \(error.localizedDescription)" }
                    try Task.checkCancellation()
                    finish(&current, result: result)
                    if !result.skipped { sendNotification(title: "Download Complete", body: current.displayTitle) }
                    break
                } catch {
                    try Task.checkCancellation()
                    guard AppSettings.shared.autoRetryFailed, retries < 2,
                          DownloadFailurePolicy.isTransient(error.localizedDescription), !DownloadFailurePolicy.isSiteRestriction(error.localizedDescription) else { throw error }
                    retries += 1
                    current.retryCount = retries
                    currentActivity = "Retry \(retries)/2: \(current.displayTitle)"
                    try await Task.sleep(nanoseconds: UInt64(retries * 3) * 1_000_000_000)
                }
            }
        } catch {
            progressTokens.removeValue(forKey: item.id)
            if error is CancellationError || Task.isCancelled { current.status = .cancelled }
            else { current.status = .error(error.localizedDescription); current.errorMessage = error.localizedDescription }
            DownloadQueue.shared.updateItem(current)
        }
        if let reservation { await DuplicateLibrary.shared.release(reservation, root: root) }
    }

    private func finish(_ item: inout DownloadItem, result: DownloadResult) {
        item.status = result.skipped ? .skipped : .completed
        item.filePath = result.file.path
        item.fileSize = (try? result.file.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
        item.mediaID = result.mediaID ?? item.mediaID
        item.downloader = result.downloader
        item.dateCompleted = Date()
        DownloadQueue.shared.updateItem(item)
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
