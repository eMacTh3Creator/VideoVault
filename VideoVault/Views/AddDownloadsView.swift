import SwiftUI

struct AddDownloadsView: View {
    @EnvironmentObject var manager: DownloadManager
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var queue: DownloadQueue
    @Environment(\.dismiss) private var dismiss

    @State private var urlText = ""
    @State private var selectedFormat: DownloadFormat

    init() {
        _selectedFormat = State(initialValue: AppSettings.shared.defaultFormat)
    }

    private var parsedURLs: [String] {
        urlText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && ($0.hasPrefix("http://") || $0.hasPrefix("https://")) }
    }

    private var invalidLines: [String] {
        urlText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("http://") && !$0.hasPrefix("https://") }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Text("Add Downloads")
                    .font(.headline)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Divider()

            // Scrollable content
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // URL input
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Video URLs")
                                .font(.subheadline)
                                .fontWeight(.medium)

                            Spacer()

                            Button("Paste from Clipboard") {
                                pasteFromClipboard()
                            }
                            .font(.caption)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        Text("Enter one URL per line. Supports YouTube, Vimeo, Twitter/X, TikTok, Reddit, and 1000+ other sites.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        TextEditor(text: $urlText)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(height: 140)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                            )
                    }

                    // URL count
                    HStack(spacing: 16) {
                        Label("\(parsedURLs.count) valid URL\(parsedURLs.count == 1 ? "" : "s")", systemImage: "link")
                            .font(.caption)
                            .foregroundColor(parsedURLs.isEmpty ? .secondary : .green)

                        if !invalidLines.isEmpty {
                            Label("\(invalidLines.count) invalid line\(invalidLines.count == 1 ? "" : "s")", systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }

                    Divider()

                    // Format selection — compact grid
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Download Format")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 8) {
                            ForEach(DownloadFormat.allCases) { format in
                                FormatButton(
                                    format: format,
                                    isSelected: selectedFormat == format
                                ) {
                                    selectedFormat = format
                                }
                            }
                        }
                    }

                    // Download location
                    HStack(spacing: 6) {
                        Image(systemName: "folder")
                            .foregroundColor(.secondary)
                            .font(.caption)
                        Text("Saving to: \(settings.downloadPath)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .padding(20)
            }

            Divider()

            // Action buttons — always visible
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Spacer()

                if queue.totalQueued > 0 {
                    Text("\(queue.totalQueued) already queued")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Button(action: addDownloads) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle.fill")
                        Text("Download \(parsedURLs.count) Video\(parsedURLs.count == 1 ? "" : "s")")
                    }
                    .padding(.horizontal, 8)
                }
                .buttonStyle(.borderedProminent)
                .disabled(parsedURLs.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 520, height: 540)
    }

    private func pasteFromClipboard() {
        guard let clipboard = NSPasteboard.general.string(forType: .string) else { return }

        if urlText.isEmpty {
            urlText = clipboard
        } else {
            urlText += "\n" + clipboard
        }
    }

    private func addDownloads() {
        manager.addURLs(parsedURLs, format: selectedFormat)
        dismiss()
    }
}

// MARK: - Format Button

struct FormatButton: View {
    let format: DownloadFormat
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .font(.system(size: 14))

                Image(systemName: format.iconName)
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .font(.caption)
                    .frame(width: 14)

                Text(format.rawValue)
                    .font(.system(size: 12))
                    .foregroundColor(isSelected ? .primary : .secondary)

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
