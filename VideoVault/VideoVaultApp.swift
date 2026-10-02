import SwiftUI
import UserNotifications

@main
struct VideoVaultApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Window("VideoVault", id: "main") {
            RootView()
                .background(WindowActionsBridge())
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 900, height: 600)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckAppUpdatesButton()
            }
            CommandGroup(replacing: .newItem) {
                Button("Add Downloads...") {
                    MenuBarController.shared.showWindow(notification: .showAddDownloads)
                }
                .keyboardShortcut("n", modifiers: .command)
            }

            CommandGroup(after: .newItem) {
                Divider()
                Button("Home") { MenuBarController.shared.showWindow(notification: .showHome) }
                    .keyboardShortcut("h", modifiers: [.command, .shift])
                Button("Find Duplicates...") { MenuBarController.shared.showWindow(notification: .showDuplicates) }
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

// MARK: - App Delegate

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var menuBar: MenuBarController?
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        StorageManager.shared.ensureDownloadDirectory()
        menuBar = MenuBarController.shared
        menuBar?.checkForAppUpdates = { AppUpdateService.shared.checkForUpdates() }
        AppUpdateService.shared.start()
        DependencyUpdateService.shared.startAutomaticChecks()
        DownloadManager.shared.processQueue()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return !AppSettings.shared.showInMenuBar && !DownloadManager.shared.isProcessing
    }

    func applicationWillTerminate(_ notification: Notification) { DownloadManager.shared.cancelAllDownloads() }
}

struct WindowActionsBridge: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Color.clear.frame(width: 0, height: 0).onAppear {
            MenuBarController.shared.openWindow = { openWindow(id: "main") }
        }
    }
}

struct CheckAppUpdatesButton: View {
    @ObservedObject private var updater = AppUpdateService.shared
    var body: some View {
        Button("Check for Updates...") { updater.checkForUpdates() }.disabled(!updater.canCheckForUpdates)
    }
}
