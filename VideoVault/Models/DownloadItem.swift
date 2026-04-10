import Foundation

enum DownloadStatus: Equatable, Codable {
    case queued
    case fetching
    case downloading(progress: Double)
    case converting
    case completed
    case error(String)
    case cancelled

    var displayName: String {
        switch self {
        case .queued: return "Queued"
        case .fetching: return "Fetching Info"
        case .downloading(let progress): return "Downloading \(Int(progress * 100))%"
        case .converting: return "Converting"
        case .completed: return "Completed"
        case .error(let msg): return "Error: \(msg)"
        case .cancelled: return "Cancelled"
        }
    }

    var isActive: Bool {
        switch self {
        case .fetching, .downloading, .converting: return true
        default: return false
        }
    }

    var isFinished: Bool {
        switch self {
        case .completed, .error, .cancelled: return true
        default: return false
        }
    }

    var iconName: String {
        switch self {
        case .queued: return "clock"
        case .fetching: return "magnifyingglass"
        case .downloading: return "arrow.down.circle"
        case .converting: return "wand.and.stars"
        case .completed: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        case .cancelled: return "xmark.circle"
        }
    }

    var iconColor: String {
        switch self {
        case .queued: return "secondary"
        case .fetching: return "blue"
        case .downloading: return "accentColor"
        case .converting: return "purple"
        case .completed: return "green"
        case .error: return "red"
        case .cancelled: return "gray"
        }
    }
}

enum DownloadFormat: String, Codable, CaseIterable, Identifiable {
    case mp3 = "MP3 Audio"
    case bestAudio = "Best Audio (M4A)"
    case video720p = "720p Video"
    case video1080p = "1080p Video"
    case video1440p = "1440p Video"
    case video4k = "4K Video"
    case bestVideo = "Best Quality Video"

    var id: String { rawValue }

    var isAudioOnly: Bool {
        switch self {
        case .mp3, .bestAudio: return true
        default: return false
        }
    }

    var fileExtension: String {
        switch self {
        case .mp3: return "mp3"
        case .bestAudio: return "m4a"
        default: return "mp4"
        }
    }

    var ytdlpArgs: [String] {
        switch self {
        case .mp3:
            return ["-x", "--audio-format", "mp3", "--audio-quality", "0"]
        case .bestAudio:
            return ["-x", "--audio-format", "m4a", "--audio-quality", "0"]
        case .video720p:
            return ["-f", "bestvideo[height<=720]+bestaudio/bestvideo[height<=720]+bestaudio/best[height<=720]/bestvideo+bestaudio/best", "--merge-output-format", "mp4"]
        case .video1080p:
            return ["-f", "bestvideo[height<=1080]+bestaudio/best[height<=1080]/bestvideo+bestaudio/best", "--merge-output-format", "mp4"]
        case .video1440p:
            return ["-f", "bestvideo[height<=1440]+bestaudio/best[height<=1440]/bestvideo+bestaudio/best", "--merge-output-format", "mp4"]
        case .video4k:
            return ["-f", "bestvideo[height<=2160]+bestaudio/best[height<=2160]/bestvideo+bestaudio/best", "--merge-output-format", "mp4"]
        case .bestVideo:
            return ["-f", "bestvideo+bestaudio/best", "--merge-output-format", "mp4"]
        }
    }

    var iconName: String {
        switch self {
        case .mp3, .bestAudio: return "music.note"
        default: return "film"
        }
    }
}

struct DownloadItem: Identifiable, Codable, Equatable, Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }


    let id: UUID
    var url: String
    var title: String?
    var thumbnailURL: String?
    var status: DownloadStatus
    var format: DownloadFormat
    var filePath: String?
    var fileSize: Int64?
    var duration: String?
    var source: String?
    var dateAdded: Date
    var dateCompleted: Date?
    var errorMessage: String?

    init(url: String, format: DownloadFormat) {
        self.id = UUID()
        self.url = url.trimmingCharacters(in: .whitespacesAndNewlines)
        self.status = .queued
        self.format = format
        self.dateAdded = Date()
    }

    var displayTitle: String {
        title ?? extractDomain(from: url) ?? "Unknown"
    }

    var sourceName: String {
        if let source = source { return source }
        return extractDomain(from: url) ?? "Unknown"
    }

    private func extractDomain(from urlString: String) -> String? {
        guard let url = URL(string: urlString),
              let host = url.host else { return nil }
        return host.replacingOccurrences(of: "www.", with: "")
    }

    static func == (lhs: DownloadItem, rhs: DownloadItem) -> Bool {
        lhs.id == rhs.id &&
        lhs.status == rhs.status &&
        lhs.title == rhs.title &&
        lhs.filePath == rhs.filePath &&
        lhs.fileSize == rhs.fileSize &&
        lhs.errorMessage == rhs.errorMessage
    }
}
