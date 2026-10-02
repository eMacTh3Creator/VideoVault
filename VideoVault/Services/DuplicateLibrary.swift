import Foundation
import CryptoKit

enum DownloadIdentity {
    static func canonicalURL(_ text: String) -> String {
        guard var parts = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = parts.host?.lowercased() else { return text }
        if host == "youtu.be", let id = parts.path.split(separator: "/").first {
            return "https://www.youtube.com/watch?v=\(id)"
        }
        if host == "youtube.com" || host.hasSuffix(".youtube.com") {
            let pathID = parts.path.split(separator: "/").last.map(String.init)
            let id = parts.queryItems?.first(where: { $0.name == "v" })?.value
                ?? (["/shorts/", "/embed/", "/live/"].contains(where: { parts.path.hasPrefix($0) }) ? pathID : nil)
            if let id { return "https://www.youtube.com/watch?v=\(id)" }
        }
        parts.host = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        parts.fragment = nil
        parts.queryItems = parts.queryItems?.filter { !$0.name.lowercased().hasPrefix("utm_") && !["fbclid", "gclid"].contains($0.name.lowercased()) }
            .sorted { ($0.name, $0.value ?? "") < ($1.name, $1.value ?? "") }
        if parts.queryItems?.isEmpty == true { parts.queryItems = nil }
        return parts.string ?? text
    }

    static func key(url: String, mediaID: String?, format: DownloadFormat) -> String {
        "\(mediaID ?? canonicalURL(url))|\(format.storageKey)"
    }
}

actor DuplicateLibrary {
    static let shared = DuplicateLibrary()
    private var reservations = Set<String>()
    private var retainedContent: [String: URL] = [:]

    struct Record: Codable {
        var url: String
        var mediaID: String?
        var format: DownloadFormat
        var relativePath: String
    }

    func acquire(_ key: String, root: URL) async throws {
        let token = root.resolvingSymlinksInPath().standardizedFileURL.path + "|" + key
        while reservations.contains(token) { try await Task.sleep(nanoseconds: 100_000_000) }
        try Task.checkCancellation()
        reservations.insert(token)
    }

    func release(_ key: String, root: URL) { reservations.remove(root.resolvingSymlinksInPath().standardizedFileURL.path + "|" + key) }

    func existing(url: String, mediaID: String?, format: DownloadFormat, root: URL) -> URL? {
        let canonical = DownloadIdentity.canonicalURL(url)
        return load(root).first { record in
            record.format == format && (record.url == canonical || (mediaID != nil && record.mediaID == mediaID))
                && valid(record, root: root) != nil
        }.flatMap { valid($0, root: root) }
    }

    func remember(url: String, mediaID: String?, format: DownloadFormat, file: URL, root: URL) throws {
        let prefix = root.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        let actualFile = file.resolvingSymlinksInPath().standardizedFileURL
        guard actualFile.path.hasPrefix(prefix) else { return }
        var records = load(root).filter { valid($0, root: root) != nil }
        let relative = String(actualFile.path.dropFirst(prefix.count))
        records.removeAll { $0.url == DownloadIdentity.canonicalURL(url) && $0.format == format }
        records.append(Record(url: DownloadIdentity.canonicalURL(url), mediaID: mediaID, format: format, relativePath: relative))
        try JSONEncoder().encode(records).write(to: root.appendingPathComponent(".videovault-library.json"), options: .atomic)
    }

    func coalesce(_ result: DownloadResult, root: URL) throws -> DownloadResult {
        try Task.checkCancellation()
        guard !result.skipped else { return result }
        let digest = try VerifiedDownload.sha256(result.file)
        let contentKey = root.resolvingSymlinksInPath().standardizedFileURL.path + "|" + digest
        let retained = retainedContent[contentKey].flatMap { file -> URL? in
            guard FileManager.default.fileExists(atPath: file.path), (try? VerifiedDownload.sha256(file)) == digest else { return nil }
            return file
        }
        let existing = try retained ?? DuplicateScanner.existingCopy(of: result.file, root: root)
        let keeper = existing ?? result.file
        retainedContent[contentKey] = keeper
        guard keeper.resolvingSymlinksInPath().standardizedFileURL != result.file.resolvingSymlinksInPath().standardizedFileURL else { return result }
        try Task.checkCancellation()
        try FileManager.default.removeItem(at: result.file)
        return DownloadResult(file: keeper, mediaID: result.mediaID, downloader: result.downloader, skipped: true)
    }

    private func load(_ root: URL) -> [Record] {
        guard let data = try? Data(contentsOf: root.appendingPathComponent(".videovault-library.json")) else { return [] }
        return (try? JSONDecoder().decode([Record].self, from: data)) ?? []
    }

    private func valid(_ record: Record, root: URL) -> URL? {
        let file = root.appendingPathComponent(record.relativePath).standardizedFileURL
        guard file.resolvingSymlinksInPath().path.hasPrefix(root.resolvingSymlinksInPath().path + "/"),
              let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true, (values.fileSize ?? 0) > 0 else { return nil }
        return file
    }
}

struct DuplicateGroup: Identifiable, Sendable {
    let id: String
    let files: [URL]
    let fileSize: Int64
    var reclaimableBytes: Int64 { Int64(files.count - 1) * fileSize }
}

enum DuplicateScanner {
    static let mediaExtensions: Set<String> = ["mp4", "mkv", "webm", "mov", "m4v", "ts", "mp3", "m4a", "mka", "aac", "ogg", "opus", "flac", "wav", "avi", "flv"]

    static func existingCopy(of file: URL, root: URL) throws -> URL? {
        let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize
        guard let iterator = FileManager.default.enumerator(at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return nil }
        var digest: String?
        for case let candidate as URL in iterator {
            try Task.checkCancellation()
            guard candidate.resolvingSymlinksInPath().standardizedFileURL != file.resolvingSymlinksInPath().standardizedFileURL,
                  mediaExtensions.contains(candidate.pathExtension.lowercased()) else { continue }
            let values = try candidate.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true, values.fileSize == size else { continue }
            if digest == nil { digest = try VerifiedDownload.sha256(file) }
            if try VerifiedDownload.sha256(candidate) == digest { return candidate }
        }
        return nil
    }

    static func scanFiles(root: URL, progress: @escaping @Sendable (String) -> Void) throws -> [DuplicateGroup] {
        var bySize: [Int64: [URL]] = [:]
        var scanError: Error?
        guard let iterator = FileManager.default.enumerator(at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, error in scanError = error; return false }) else {
            throw ProcessFailure.failed("Cannot read the selected download folder.")
        }
        for case let file as URL in iterator {
            try Task.checkCancellation()
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            if values.isSymbolicLink == true { iterator.skipDescendants(); continue }
            guard values.isRegularFile == true, mediaExtensions.contains(file.pathExtension.lowercased()), let size = values.fileSize, size > 0 else { continue }
            bySize[Int64(size), default: []].append(file)
        }
        if let scanError { throw scanError }
        var groups: [DuplicateGroup] = []
        for (size, files) in bySize where files.count > 1 {
            var byHash: [String: [URL]] = [:]
            for file in files {
                try Task.checkCancellation()
                progress("Checking \(file.lastPathComponent)")
                let before = try file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                let handle = try FileHandle(forReadingFrom: file)
                defer { try? handle.close() }
                var hash = SHA256()
                while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
                    try Task.checkCancellation()
                    hash.update(data: chunk)
                }
                let after = try file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                guard before.fileSize == after.fileSize, before.contentModificationDate == after.contentModificationDate else { continue }
                let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
                byHash[digest, default: []].append(file)
            }
            for (hash, matches) in byHash where matches.count > 1 {
                groups.append(DuplicateGroup(id: hash, files: matches.sorted { $0.path < $1.path }, fileSize: size))
            }
        }
        return groups.sorted { $0.reclaimableBytes > $1.reclaimableBytes }
    }
}
