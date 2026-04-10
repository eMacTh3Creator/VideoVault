import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var queue: DownloadQueue
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // App title header
            HStack {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundColor(.accentColor)
                    .font(.title3)

                Text("VideoVault")
                    .font(.headline)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            Divider()
                .padding(.vertical, 4)

            // Stats row
            HStack(spacing: 16) {
                StatBadge(icon: "arrow.down.circle", count: queue.totalActive, label: "active", color: .accentColor)
                StatBadge(icon: "clock", count: queue.totalQueued, label: "queued", color: .orange)
                StatBadge(icon: "checkmark.circle", count: queue.totalCompleted, label: "done", color: .green)
                if queue.totalFailed > 0 {
                    StatBadge(icon: "exclamationmark.triangle", count: queue.totalFailed, label: "failed", color: .red)
                }
            }
            .padding(.horizontal, 12)

            // Recent items
            if !recentItems.isEmpty {
                Divider()
                    .padding(.vertical, 4)

                Text("Recent")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)

                ForEach(recentItems) { item in
                    HStack(spacing: 8) {
                        Image(systemName: item.status.iconName)
                            .font(.caption)
                            .foregroundColor(iconColor(for: item.status))
                            .frame(width: 16)

                        Text(item.displayTitle)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Spacer()

                        if case .downloading(let progress) = item.status {
                            Text("\(Int(progress * 100))%")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundColor(.accentColor)
                        } else if case .completed = item.status, let size = item.fileSize {
                            Text(StorageManager.shared.formatBytes(size))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 2)
                }
            }

            Divider()
                .padding(.vertical, 4)

            // Actions
            MenuBarButton(icon: "plus", label: "Add Downloads") {
                showMainWindow()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    NotificationCenter.default.post(name: .showAddDownloads, object: nil)
                }
            }

            MenuBarButton(icon: "folder", label: "Open Download Folder") {
                StorageManager.shared.openDownloadFolder()
            }

            Divider()
                .padding(.vertical, 4)

            MenuBarButton(icon: "macwindow", label: "Open VideoVault") {
                showMainWindow()
            }

            MenuBarButton(icon: "gear", label: "Settings...") {
                showMainWindow()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    NotificationCenter.default.post(name: .showSettings, object: nil)
                }
            }

            Divider()
                .padding(.vertical, 2)

            MenuBarButton(icon: "power", label: "Quit VideoVault") {
                NSApplication.shared.terminate(nil)
            }
            .padding(.bottom, 6)
        }
        .frame(width: 300)
    }

    // MARK: - Helpers

    private var recentItems: [DownloadItem] {
        Array(queue.items.prefix(5))
    }

    private func iconColor(for status: DownloadStatus) -> Color {
        switch status {
        case .completed: return .green
        case .error: return .red
        case .downloading, .fetching: return .accentColor
        case .converting: return .purple
        default: return .secondary
        }
    }

    private func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows {
            if window.canBecomeKey && !window.title.isEmpty {
                window.makeKeyAndOrderFront(nil)
                break
            }
        }
    }
}

// MARK: - Subviews

struct StatBadge: View {
    let icon: String
    let count: Int
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundColor(count > 0 ? color : .secondary)
            Text("\(count)")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(count > 0 ? color : .secondary)
        }
    }
}

struct MenuBarButton: View {
    let icon: String
    let label: String
    var color: Color = .primary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.caption)
                    .frame(width: 16)
                Text(label)
                    .font(.callout)
                Spacer()
            }
            .foregroundColor(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
