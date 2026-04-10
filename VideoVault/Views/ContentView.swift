import SwiftUI

struct ContentView: View {
    @EnvironmentObject var queue: DownloadQueue
    @EnvironmentObject var manager: DownloadManager
    @EnvironmentObject var settings: AppSettings

    @State private var selectedItem: DownloadItem?
    @State private var showAddSheet = false
    @State private var showSettings = false
    @State private var filterStatus: FilterOption = .all

    enum FilterOption: String, CaseIterable {
        case all = "All"
        case active = "Active"
        case queued = "Queued"
        case completed = "Completed"
        case failed = "Failed"
    }

    var filteredItems: [DownloadItem] {
        switch filterStatus {
        case .all: return queue.items
        case .active: return queue.items.filter { $0.status.isActive }
        case .queued: return queue.items.filter { if case .queued = $0.status { return true }; return false }
        case .completed: return queue.completedItems
        case .failed: return queue.failedItems
        }
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(
                selectedItem: $selectedItem,
                filterStatus: $filterStatus,
                showAddSheet: $showAddSheet
            )
            .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 400)
        } detail: {
            if let item = selectedItem {
                DownloadDetailView(item: item)
            } else {
                emptyState
            }
        }
        .frame(minWidth: 800, minHeight: 520)
        .sheet(isPresented: $showAddSheet) {
            AddDownloadsView()
                .environmentObject(manager)
                .environmentObject(settings)
                .environmentObject(queue)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(settings)
        }
        .onReceive(NotificationCenter.default.publisher(for: .showAddDownloads)) { _ in
            showAddSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .showSettings)) { _ in
            showSettings = true
        }
        .onChange(of: queue.items) { _ in
            // Clear selection if the selected item was removed from the queue
            if let selected = selectedItem,
               !queue.items.contains(where: { $0.id == selected.id }) {
                selectedItem = nil
            }
            // Also update the selected item's data if it still exists (e.g. status changed)
            if let selected = selectedItem,
               let updated = queue.items.first(where: { $0.id == selected.id }),
               updated != selected {
                selectedItem = updated
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: { showAddSheet = true }) {
                    Label("Add URLs", systemImage: "plus")
                }

                if manager.isProcessing {
                    Button(action: { manager.cancelAllDownloads() }) {
                        Label("Stop All", systemImage: "stop.fill")
                    }
                    .tint(.red)
                } else if !queue.queuedItems.isEmpty || !queue.failedItems.isEmpty {
                    Button(action: { manager.processQueue() }) {
                        Label("Process Queue", systemImage: "play.fill")
                    }
                }

                Button(action: { showSettings = true }) {
                    Label("Settings", systemImage: "gear")
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 56, weight: .thin))
                .foregroundColor(.secondary)

            Text("No Download Selected")
                .font(.title2)
                .fontWeight(.medium)

            Text("Add URLs to start downloading videos")
                .font(.body)
                .foregroundColor(.secondary)

            Button(action: { showAddSheet = true }) {
                Label("Add URLs", systemImage: "plus")
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
