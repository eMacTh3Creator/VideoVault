import SwiftUI
import UserNotifications

@main
struct VideoVaultApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 900, height: 600)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add Downloads...") {
                    NotificationCenter.default.post(name: .showAddDownloads, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
            }

            CommandGroup(after: .newItem) {
                Divider()
                Button("Open Download Folder") {
                    StorageManager.shared.openDownloadFolder()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }

            CommandMenu("Downloads") {
                Button("Start Processing Queue") {
                    Task { @MainActor in
                        DownloadManager.shared.processQueue()
                    }
                }
                .keyboardShortcut("r", modifiers: .command)

                Button("Stop All Downloads") {
                    Task { @MainActor in
                        DownloadManager.shared.cancelAllDownloads()
                    }
                }
                .keyboardShortcut(".", modifiers: .command)

                Divider()

                Button("Retry Failed Downloads") {
                    Task { @MainActor in
                        DownloadManager.shared.retryAllFailed()
                    }
                }

                Divider()

                Button("Clear Completed") {
                    DownloadQueue.shared.clearCompleted()
                }
                Button("Clear All") {
                    DownloadQueue.shared.clearAll()
                }
            }

            CommandGroup(replacing: .help) {
                Button("VideoVault Help") {
                    if let url = URL(string: "https://github.com/yt-dlp/yt-dlp#readme") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Button("yt-dlp Supported Sites") {
                    if let url = URL(string: "https://github.com/yt-dlp/yt-dlp/blob/master/supportedsites.md") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
    }
}

// MARK: - Root View

struct RootView: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        if settings.hasCompletedOnboarding {
            MainAppView()
        } else {
            OnboardingView()
                .environmentObject(settings)
        }
    }
}

struct MainAppView: View {
    @StateObject private var manager = DownloadManager.shared
    @ObservedObject private var queue = DownloadQueue.shared
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        ContentView()
            .environmentObject(manager)
            .environmentObject(queue)
            .environmentObject(settings)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let showAddDownloads = Notification.Name("showAddDownloads")
    static let showSettings = Notification.Name("showSettings")
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        StorageManager.shared.ensureDownloadDirectory()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
