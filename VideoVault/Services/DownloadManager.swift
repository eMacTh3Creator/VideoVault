import Foundation
import UserNotifications

class DownloadManager: ObservableObject {
    static let shared = DownloadManager()

    @Published var isProcessing = false
    @Published var currentActivity = ""

    private var activeTasks: [UUID: Task<Void, Never>] = [:]

    private init() {}

    // MARK: - Queue Processing

    @MainActor
    func processQueue() {
        let queue = DownloadQueue.shared
        let settings = AppSettings.shared

        guard !queue.queuedItems.isEmpty else {
            if activeTasks.isEmpty {
                isProcessing = false
                currentActivity = ""
            }
            return
        }

        isProcessing = true

        let availableSlots = settings.maxConcurrentDownloads - activeTasks.count
        guard availableSlots > 0 else { return }

        let itemsToProcess = Array(queue.queuedItems.prefix(availableSlots))

        for item in itemsToProcess {
            startDownload(item)
        }
    }

    @MainActor
    func startDownload(_ item: DownloadItem) {
        guard activeTasks[item.id] == nil else { return }

        let task = Task.detached { [weak self] in
            guard let self = self else { return }
            await self.performDownload(item)
        }

        activeTasks[item.id] = task
    }

    @MainActor
    func cancelDownload(_ item: DownloadItem) {
        activeTasks[item.id]?.cancel()
        activeTasks.removeValue(forKey: item.id)
        DownloadQueue.shared.cancelItem(item)
        processQueue()
    }

    @MainActor
    func cancelAllDownloads() {
        let queue = DownloadQueue.shared

        for (_, task) in activeTasks {
            task.cancel()
        }
        activeTasks.removeAll()

        for item in queue.activeItems + queue.queuedItems {
            queue.cancelItem(item)
        }

        isProcessing = false
        currentActivity = ""
    }

    @MainActor
    func retryItem(_ item: DownloadItem) {
        var updated = item
        updated.status = .queued
        updated.errorMessage = nil
        DownloadQueue.shared.updateItem(updated)
        processQueue()
    }

    @MainActor
    func retryAllFailed() {
        DownloadQueue.shared.retryFailed()
        processQueue()
    }

    // MARK: - Add Downloads

    @MainActor
    func addURLs(_ urls: [String], format: DownloadFormat) {
        let newItems = urls
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && ($0.hasPrefix("http://") || $0.hasPrefix("https://")) }
            .map { DownloadItem(url: $0, format: format) }

        guard !newItems.isEmpty else { return }

        DownloadQueue.shared.addItems(newItems)
        processQueue()
    }

    // MARK: - Download Execution (runs detached, NOT on main actor)

    private func performDownload(_ item: DownloadItem) async {
        let queue = DownloadQueue.shared
        let ytdlp = YTDLPService.shared
        let settings = AppSettings.shared
        var current = item

        // Step 1: Fetch video info
        await MainActor.run {
            current.status = .fetching
            self.currentActivity = "Fetching info: \(current.url)"
            queue.updateItem(current)
        }

        do {
            let info = try await ytdlp.fetchVideoInfo(url: current.url)
            current.title = info.title
            current.thumbnailURL = info.thumbnailURL
            current.duration = info.duration
            current.source = info.source
            await MainActor.run {
                queue.updateItem(current)
            }
        } catch {
            // Non-fatal — continue with download even if info fetch fails
            current.title = current.url
            await MainActor.run {
                queue.updateItem(current)
            }
        }

        // Check cancellation
        guard !Task.isCancelled else {
            current.status = .cancelled
            await MainActor.run {
                queue.updateItem(current)
                self.activeTasks.removeValue(forKey: item.id)
            }
            return
        }

        // Step 2: Download
        await MainActor.run {
            current.status = .downloading(progress: 0)
            self.currentActivity = "Downloading: \(current.displayTitle)"
            queue.updateItem(current)
        }

        do {
            let outputDir = settings.sourceDirectory(for: current.sourceName)

            let fileURL = try await ytdlp.download(
                url: current.url,
                format: current.format,
                outputDirectory: outputDir
            ) { progress, statusText in
                Task { @MainActor in
                    if statusText.contains("Converting") || statusText.contains("Merging") {
                        current.status = .converting
                    } else {
                        current.status = .downloading(progress: progress)
                    }
                    self.currentActivity = "\(current.displayTitle) — \(statusText)"
                    queue.updateItem(current)
                }
            }

            // Success
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64) ?? 0

            current.status = .completed
            current.filePath = fileURL.path
            current.fileSize = fileSize
            current.dateCompleted = Date()

            await MainActor.run {
                queue.updateItem(current)
                self.activeTasks.removeValue(forKey: item.id)
                self.processQueue()
            }
            sendNotification(title: "Download Complete", body: current.displayTitle)

        } catch {
            guard !Task.isCancelled else {
                current.status = .cancelled
                await MainActor.run {
                    queue.updateItem(current)
                    self.activeTasks.removeValue(forKey: item.id)
                }
                return
            }

            current.status = .error(error.localizedDescription)
            current.errorMessage = error.localizedDescription
            await MainActor.run {
                queue.updateItem(current)
                self.activeTasks.removeValue(forKey: item.id)
                self.processQueue()
            }
        }
    }

    // MARK: - Notifications

    private func sendNotification(title: String, body: String) {
        guard AppSettings.shared.notificationsEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }
}
