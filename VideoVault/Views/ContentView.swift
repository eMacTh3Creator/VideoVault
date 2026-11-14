import SwiftUI

struct ContentView: View {
    @EnvironmentObject var queue: DownloadQueue
    @EnvironmentObject var manager: DownloadManager
    @EnvironmentObject var settings: AppSettings

    @State private var selectedIDs = Set<UUID>()
    @State private var pendingRemovalIDs = Set<UUID>()
    @State private var showRemovalConfirmation = false
    @State private var showAddSheet = false
    @State private var showSettings = false
    @State private var showDuplicates = false
    @State private var filterStatus: FilterOption = .all

    enum FilterOption: String, CaseIterable {
        case all = "All"
        case active = "Active"
        case queued = "Queued"
        case completed = "Completed"
        case failed = "Failed"
    }

    private var selection: DownloadSelection { DownloadSelection(ids: selectedIDs, in: queue.items) }

    var body: some View {
        NavigationSplitView {
            SidebarView(
                selectedIDs: $selectedIDs,
                filterStatus: $filterStatus,
                showAddSheet: $showAddSheet,
                onRemove: requestRemoval
            )
            .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 400)
        } detail: {
            if selection.items.count > 1 {
                selectionSummary
            } else if let item = selection.items.first {
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
        .sheet(isPresented: $showDuplicates) { DuplicateFinderView() }
        .alert("Remove \(pendingRemovalIDs.count) downloads?", isPresented: $showRemovalConfirmation) {
            Button("Remove from List", role: .destructive) {
                removeFromList(pendingRemovalIDs)
                pendingRemovalIDs = []
            }
            Button("Cancel", role: .cancel) { pendingRemovalIDs = [] }
        } message: {
            Text("Saved files will not be deleted. Selected active downloads will be cancelled, and selected queued downloads will be removed.")
        }
        .onAppear { MenuBarController.shared.windowDidAppear() }
        .onDisappear { MenuBarController.shared.windowDidDisappear() }
        .onReceive(NotificationCenter.default.publisher(for: .showHome)) { _ in selectedIDs = []; filterStatus = .all }
        .onReceive(NotificationCenter.default.publisher(for: .showDuplicates)) { _ in showDuplicates = true }
        .onReceive(NotificationCenter.default.publisher(for: .showAddDownloads)) { _ in
            showAddSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .showSettings)) { _ in
            showSettings = true
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { selectedIDs = []; filterStatus = .all } label: {
                    Label("Home", systemImage: "house")
                }
                .help("Return to Home")
                Button { showDuplicates = true } label: { Label("Find Duplicates", systemImage: "doc.on.doc") }
                    .help("Find identical files in your download folder")
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

    private func requestRemoval(_ ids: Set<UUID>) {
        let liveIDs = DownloadSelection(ids: ids, in: queue.items).ids
        guard !liveIDs.isEmpty else { return }
        if liveIDs.count == 1 { removeFromList(liveIDs) }
        else { pendingRemovalIDs = liveIDs; showRemovalConfirmation = true }
    }

    private func removeFromList(_ ids: Set<UUID>) {
        manager.removeItems(ids)
        selectedIDs.subtract(ids)
    }

    private var selectionSummary: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("\(selection.items.count) downloads selected", systemImage: "checklist")
                .font(.title2).fontWeight(.semibold)
            Text("Command-click to add or remove items. Shift-click to select a range. Command-A selects all downloads shown in the list.")
                .foregroundColor(.secondary)
            Text("\(selection.retryableIDs.count) ready to retry; \(selection.cancellableIDs.count) active or queued.")
                .font(.subheadline)
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Button("Retry (\(selection.retryableIDs.count))") { manager.retryItems(selectedIDs) }
                        .disabled(selection.retryableIDs.isEmpty)
                    Button("Force Retry (\(selection.retryableIDs.count))") { manager.retryItems(selectedIDs, forceRecovery: true) }
                        .buttonStyle(.borderedProminent)
                        .disabled(selection.retryableIDs.isEmpty)
                }
                HStack {
                    Button("Cancel (\(selection.cancellableIDs.count))") { manager.cancelItems(selectedIDs) }
                        .disabled(selection.cancellableIDs.isEmpty)
                    Button("Copy URLs") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(selection.copiedURLs, forType: .string)
                    }
                }
                HStack {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(selection.fileURLs) }
                        .disabled(selection.fileURLs.isEmpty)
                    Button("Remove from List...", role: .destructive) { requestRemoval(selectedIDs) }
                }
            }
            .buttonStyle(.bordered)
            Text("Retry applies only to failed or cancelled downloads. Completed downloads are left unchanged. Remove deletes list entries, not saved files.")
                .font(.caption).foregroundColor(.secondary)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
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
