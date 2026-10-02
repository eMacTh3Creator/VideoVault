import SwiftUI
import CryptoKit

struct DuplicateFinderView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var queue = DownloadQueue.shared
    @State private var folder = AppSettings.shared.downloadURL
    @State private var groups: [DuplicateGroup] = []
    @State private var selected = Set<URL>()
    @State private var message = ""
    @State private var isScanning = false
    @State private var confirmTrash = false
    @State private var scanTask: Task<[DuplicateGroup], Error>?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Duplicate Finder").font(.title2)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            HStack {
                Text(folder.path).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                Spacer()
                Button("Choose Folder...") { chooseFolder() }.disabled(isScanning)
            }
            HStack {
                Button(isScanning ? "Cancel Scan" : "Scan for Duplicates") {
                    if isScanning { scanTask?.cancel() } else { scan() }
                }.disabled(!queue.activeItems.isEmpty && !isScanning)
                if isScanning { ProgressView().controlSize(.small) }
                Spacer()
                Button("Select Extra Copies") { selected = Set(groups.flatMap { Array($0.files.dropFirst()) }) }
                    .disabled(groups.isEmpty || isScanning)
            }
            if !queue.activeItems.isEmpty { Text("Wait for active downloads to finish before scanning.").foregroundColor(.secondary) }
            Text(message).font(.caption).foregroundColor(.secondary).lineLimit(2)
            List {
                ForEach(groups) { group in
                    Section("\(group.files.count) identical copies · \(StorageManager.shared.formatBytes(group.fileSize)) each") {
                        ForEach(group.files, id: \.self) { file in
                            HStack {
                                Toggle(isOn: Binding(get: { selected.contains(file) }, set: { value in
                                    if value { selected.insert(file) } else { selected.remove(file) }
                                })) {
                                    Text(relativePath(file))
                                        .lineLimit(2).truncationMode(.middle)
                                }
                                Spacer()
                                Button { NSWorkspace.shared.activateFileViewerSelecting([file]) } label: { Image(systemName: "folder") }
                                    .help("Show in Finder")
                            }
                        }
                    }
                }
            }
            HStack {
                Text("\(groups.count) duplicate groups").foregroundColor(.secondary)
                Spacer()
                Button("Move \(selected.count) Selected to Trash", role: .destructive) { confirmTrash = true }
                    .disabled(selected.isEmpty || isScanning || !queue.activeItems.isEmpty || groups.contains { Set($0.files).isSubset(of: selected) })
            }
            if groups.contains(where: { Set($0.files).isSubset(of: selected) }) {
                Text("Keep at least one file from every group.").font(.caption).foregroundColor(.orange)
            }
        }
        .padding(20).frame(width: 720, height: 560)
        .confirmationDialog("Move \(selected.count) duplicate files to Trash?", isPresented: $confirmTrash) {
            Button("Move to Trash", role: .destructive) { trashSelected() }
        } message: { Text("At least one original copy will be kept in each group. Files can be restored from Trash.") }
        .onDisappear { scanTask?.cancel() }
        .onChange(of: queue.totalActive) { count in if count > 0 { scanTask?.cancel() } }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url { folder = url; groups = []; selected = []; message = "" }
    }

    private func relativePath(_ file: URL) -> String {
        let prefix = folder.resolvingSymlinksInPath().path + "/"
        let path = file.resolvingSymlinksInPath().path
        return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : file.path
    }

    private func scan() {
        isScanning = true
        groups = []
        selected = []
        message = "Comparing file contents..."
        let root = folder
        let task = Task.detached(priority: .utility) {
            try DuplicateScanner.scanFiles(root: root) { text in Task { @MainActor in if isScanning { message = text } } }
        }
        scanTask = task
        Task { @MainActor in
            do {
                groups = try await task.value
                let bytes = groups.reduce(0) { $0 + $1.reclaimableBytes }
                message = groups.isEmpty ? "No identical media files found." : "\(StorageManager.shared.formatBytes(bytes)) can be reclaimed. Only byte-for-byte identical media files are listed."
            } catch is CancellationError { message = "Scan cancelled." }
            catch { message = "Scan failed: \(error.localizedDescription)" }
            isScanning = false
            scanTask = nil
        }
    }

    private func trashSelected() {
        guard queue.activeItems.isEmpty, !groups.contains(where: { Set($0.files).isSubset(of: selected) }) else { return }
        let choices = groups.map { ($0.id, $0.files.filter { selected.contains($0) }, $0.files.first { !selected.contains($0) }) }
        isScanning = true
        Task { @MainActor in
            do {
                for (digest, files, keeper) in choices where !files.isEmpty {
                    guard let keeper else { continue }
                    let keeperHash = try await Task.detached { try VerifiedDownload.sha256(keeper) }.value
                    guard keeperHash == digest else { throw ProcessFailure.failed("The retained file changed after scanning. Please rescan.") }
                    for file in files {
                        let currentHash = try await Task.detached { try VerifiedDownload.sha256(file) }.value
                        guard currentHash == digest else { throw ProcessFailure.failed("A selected file changed after scanning. Please rescan.") }
                        try FileManager.default.trashItem(at: file, resultingItemURL: nil)
                    }
                }
                isScanning = false
                scan()
            } catch { isScanning = false; message = "Trash operation stopped: \(error.localizedDescription)" }
        }
    }
}
