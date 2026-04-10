import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var queue: DownloadQueue
    @EnvironmentObject var manager: DownloadManager

    @Binding var selectedItem: DownloadItem?
    @Binding var filterStatus: ContentView.FilterOption
    @Binding var showAddSheet: Bool

    @State private var searchText = ""

    var filteredItems: [DownloadItem] {
        var items: [DownloadItem]
        switch filterStatus {
        case .all: items = queue.items
        case .active: items = queue.items.filter { $0.status.isActive }
        case .queued: items = queue.items.filter { if case .queued = $0.status { return true }; return false }
        case .completed: items = queue.completedItems
        case .failed: items = queue.failedItems
        }

        if !searchText.isEmpty {
            items = items.filter {
                $0.displayTitle.localizedCaseInsensitiveContains(searchText) ||
                $0.url.localizedCaseInsensitiveContains(searchText) ||
                $0.sourceName.localizedCaseInsensitiveContains(searchText)
            }
        }

        return items
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerBar

            // Filter chips
            filterBar

            // Search
            searchBar

            // Download list
            if filteredItems.isEmpty {
                emptyList
            } else {
                downloadList
            }

            // Bottom bar
            bottomBar
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            Text("Downloads")
                .font(.headline)

            Spacer()

            Button(action: { showAddSheet = true }) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Filter

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(ContentView.FilterOption.allCases, id: \.self) { option in
                    FilterChip(
                        title: option.rawValue,
                        count: countFor(option),
                        isSelected: filterStatus == option
                    ) {
                        filterStatus = option
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 8)
    }

    private func countFor(_ option: ContentView.FilterOption) -> Int {
        switch option {
        case .all: return queue.items.count
        case .active: return queue.totalActive
        case .queued: return queue.totalQueued
        case .completed: return queue.totalCompleted
        case .failed: return queue.totalFailed
        }
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: 12))

            TextField("Search downloads...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))

            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    // MARK: - List

    private var downloadList: some View {
        List(filteredItems, selection: $selectedItem) { item in
            DownloadRowView(item: item)
                .tag(item)
                .contextMenu {
                    contextMenuItems(for: item)
                }
        }
        .listStyle(.sidebar)
    }

    private var emptyList: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 32, weight: .thin))
                .foregroundColor(.secondary)

            Text(searchText.isEmpty ? "No downloads" : "No matches")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack {
            Text("\(queue.items.count) items")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            if manager.isProcessing {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 16, height: 16)

                Text(manager.currentActivity)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 140, alignment: .trailing)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func contextMenuItems(for item: DownloadItem) -> some View {
        if item.status.isActive {
            Button("Cancel") { manager.cancelDownload(item) }
        }

        if case .error = item.status {
            Button("Retry") { manager.retryItem(item) }
        }

        if case .completed = item.status, let path = item.filePath {
            Button("Show in Finder") { StorageManager.shared.openInFinder(path: path) }
        }

        Divider()

        Button("Copy URL") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(item.url, forType: .string)
        }

        Divider()

        Button("Remove", role: .destructive) {
            queue.removeItem(item)
            if selectedItem == item { selectedItem = nil }
        }
    }
}

// MARK: - Download Row

struct DownloadRowView: View {
    let item: DownloadItem

    var body: some View {
        HStack(spacing: 10) {
            // Status icon
            statusIcon

            // Info
            VStack(alignment: .leading, spacing: 3) {
                Text(item.displayTitle)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)

                HStack(spacing: 6) {
                    Text(item.sourceName)
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Text("·")
                        .foregroundColor(.secondary)

                    Label(item.format.rawValue, systemImage: item.format.iconName)
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    if let duration = item.duration {
                        Text("·")
                            .foregroundColor(.secondary)
                        Text(duration)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            // Progress or status
            statusBadge
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch item.status {
        case .downloading(let progress):
            ZStack {
                Circle()
                    .stroke(Color.accentColor.opacity(0.2), lineWidth: 2.5)
                    .frame(width: 24, height: 24)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 24, height: 24)
            }
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.system(size: 18))
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
                .font(.system(size: 18))
        case .cancelled:
            Image(systemName: "xmark.circle")
                .foregroundColor(.secondary)
                .font(.system(size: 18))
        case .fetching, .converting:
            ProgressView()
                .scaleEffect(0.7)
                .frame(width: 24, height: 24)
        case .queued:
            Image(systemName: "clock")
                .foregroundColor(.secondary)
                .font(.system(size: 18))
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch item.status {
        case .downloading(let progress):
            Text("\(Int(progress * 100))%")
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(.accentColor)
        case .completed:
            if let size = item.fileSize {
                Text(StorageManager.shared.formatBytes(size))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        case .error:
            Text("Error")
                .font(.caption2)
                .foregroundColor(.red)
        default:
            Text(item.status.displayName)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let title: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.caption)
                if count > 0 {
                    Text("\(count)")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(isSelected ? Color.white.opacity(0.3) : Color.secondary.opacity(0.2))
                        .cornerRadius(6)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isSelected ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}
