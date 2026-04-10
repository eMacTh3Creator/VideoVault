import SwiftUI

struct DownloadDetailView: View {
    let item: DownloadItem

    @EnvironmentObject var manager: DownloadManager
    @EnvironmentObject var queue: DownloadQueue

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header with gradient
                headerSection

                // Details
                VStack(alignment: .leading, spacing: 20) {
                    statusSection
                    infoSection
                    actionSection
                }
                .padding(24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Header

    private var headerSection: some View {
        ZStack(alignment: .bottomLeading) {
            // Gradient background
            LinearGradient(
                colors: gradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(height: 140)

            // Title overlay
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: item.format.iconName)
                        .font(.caption)
                        .padding(5)
                        .background(.white.opacity(0.2))
                        .cornerRadius(6)

                    Text(item.format.rawValue)
                        .font(.caption)
                        .fontWeight(.medium)
                }

                Text(item.displayTitle)
                    .font(.title2)
                    .fontWeight(.bold)
                    .lineLimit(2)

                Text(item.sourceName)
                    .font(.subheadline)
                    .opacity(0.8)
            }
            .foregroundColor(.white)
            .padding(20)
        }
    }

    private var gradientColors: [Color] {
        switch item.sourceName.lowercased() {
        case let s where s.contains("youtube"):
            return [Color.red, Color.red.opacity(0.7)]
        case let s where s.contains("vimeo"):
            return [Color.cyan, Color.blue]
        case let s where s.contains("twitter") || s.contains("x.com"):
            return [Color.blue, Color.indigo]
        case let s where s.contains("tiktok"):
            return [Color.pink, Color.black]
        case let s where s.contains("reddit"):
            return [Color.orange, Color.red]
        default:
            return [Color.purple, Color.indigo]
        }
    }

    // MARK: - Status

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: item.status.iconName)
                    .foregroundColor(statusColor)

                Text(item.status.displayName)
                    .font(.headline)
                    .foregroundColor(statusColor)
            }

            if case .downloading(let progress) = item.status {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: progress)
                        .tint(.accentColor)

                    Text("\(Int(progress * 100))% complete")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if case .error(let msg) = item.status {
                Text(msg)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(10)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
            }
        }
    }

    private var statusColor: Color {
        switch item.status {
        case .completed: return .green
        case .error: return .red
        case .downloading, .fetching: return .accentColor
        case .converting: return .purple
        case .cancelled: return .secondary
        case .queued: return .secondary
        }
    }

    // MARK: - Info

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Details")
                .font(.headline)

            infoGrid
        }
    }

    private var infoGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible())
        ], alignment: .leading, spacing: 12) {
            InfoCell(label: "URL", value: item.url, isLink: true)

            if let duration = item.duration {
                InfoCell(label: "Duration", value: duration)
            }

            InfoCell(label: "Format", value: item.format.rawValue)

            if let size = item.fileSize {
                InfoCell(label: "File Size", value: StorageManager.shared.formatBytes(size))
            }

            InfoCell(label: "Added", value: item.dateAdded.formatted(date: .abbreviated, time: .shortened))

            if let completed = item.dateCompleted {
                InfoCell(label: "Completed", value: completed.formatted(date: .abbreviated, time: .shortened))
            }

            if let path = item.filePath {
                InfoCell(label: "Location", value: URL(fileURLWithPath: path).lastPathComponent)
            }
        }
    }

    // MARK: - Actions

    private var actionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Actions")
                .font(.headline)

            HStack(spacing: 12) {
                if case .completed = item.status, let path = item.filePath {
                    Button(action: { StorageManager.shared.openInFinder(path: path) }) {
                        Label("Show in Finder", systemImage: "folder")
                    }
                    .buttonStyle(.borderedProminent)
                }

                if item.status.isActive {
                    Button(action: { manager.cancelDownload(item) }) {
                        Label("Cancel", systemImage: "xmark")
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }

                if case .error = item.status {
                    Button(action: { manager.retryItem(item) }) {
                        Label("Retry", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                }

                if case .cancelled = item.status {
                    Button(action: { manager.retryItem(item) }) {
                        Label("Retry", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                }

                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(item.url, forType: .string)
                }) {
                    Label("Copy URL", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)

                Spacer()

                Button(role: .destructive, action: {
                    if let path = item.filePath {
                        StorageManager.shared.deleteFile(at: path)
                    }
                    queue.removeItem(item)
                }) {
                    Label("Delete", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
        }
    }
}

// MARK: - Info Cell

struct InfoCell: View {
    let label: String
    let value: String
    var isLink: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)

            if isLink {
                Text(value)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundColor(.accentColor)
                    .textSelection(.enabled)
            } else {
                Text(value)
                    .font(.system(size: 13))
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
