import Foundation
import AppKit

class StorageManager {
    static let shared = StorageManager()
    private let fileManager = FileManager.default
    private let settings = AppSettings.shared

    private init() {}

    // MARK: - Directory Management

    func ensureDownloadDirectory() {
        try? fileManager.createDirectory(
            at: settings.downloadURL,
            withIntermediateDirectories: true
        )
    }

    func ensureSourceDirectory(for source: String) {
        let dir = settings.sourceDirectory(for: source)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    // MARK: - File Operations

    func openInFinder(path: String) {
        let url = URL(fileURLWithPath: path)
        if url.hasDirectoryPath {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    func openDownloadFolder() {
        ensureDownloadDirectory()
        NSWorkspace.shared.open(settings.downloadURL)
    }

    func deleteFile(at path: String) {
        try? fileManager.removeItem(atPath: path)
    }

    func fileExists(at path: String) -> Bool {
        fileManager.fileExists(atPath: path)
    }

    // MARK: - Storage Info

    func totalDownloadSize() -> Int64 {
        directorySize(at: settings.downloadURL)
    }

    func formattedTotalSize() -> String {
        formatBytes(totalDownloadSize())
    }

    func directorySize(at url: URL) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    // MARK: - Source Folders

    func sourceFolders() -> [(name: String, size: Int64, count: Int)] {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: settings.downloadURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return contents
            .filter { $0.hasDirectoryPath }
            .map { url in
                let name = url.lastPathComponent
                let size = directorySize(at: url)
                let count = (try? fileManager.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                ).filter { !$0.hasDirectoryPath }.count) ?? 0
                return (name: name, size: size, count: count)
            }
            .sorted { $0.name < $1.name }
    }
}
