import AppKit
import Combine

extension Notification.Name {
    static let showAddDownloads = Notification.Name("showAddDownloads")
    static let showSettings = Notification.Name("showSettings")
    static let showHome = Notification.Name("showHome")
    static let showDuplicates = Notification.Name("showDuplicates")
}

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    static let shared = MenuBarController()
    private var statusItem: NSStatusItem?
    private var subscriptions = Set<AnyCancellable>()
    private var counts = (active: 0, queued: 0, failed: 0)
    private var windowReady = false
    private var pendingWindowAction: Notification.Name?
    var openWindow: (() -> Void)?
    var checkForAppUpdates: (() -> Void)?

    override init() {
        super.init()
        AppSettings.shared.$showInMenuBar.receive(on: DispatchQueue.main).sink { [weak self] visible in self?.setVisible(visible) }.store(in: &subscriptions)
        DownloadQueue.shared.$items.receive(on: DispatchQueue.main).sink { [weak self] items in
            self?.counts = (items.filter { $0.status.isActive }.count, items.filter { $0.status == .queued }.count,
                           items.filter { if case .error = $0.status { return true }; return false }.count)
            self?.updateLabel()
        }.store(in: &subscriptions)
    }

    private func setVisible(_ visible: Bool) {
        if visible, statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            let menu = NSMenu()
            menu.delegate = self
            item.menu = menu
            item.button?.image = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: "VideoVault")
            item.button?.image?.isTemplate = true
            item.button?.imagePosition = .imageLeading
            statusItem = item
            updateLabel()
        } else if !visible, let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    private func updateLabel() {
        statusItem?.button?.title = " A\(counts.active) Q\(counts.queued) F\(counts.failed)"
        statusItem?.button?.toolTip = "VideoVault: \(counts.active) active, \(counts.queued) queued, \(counts.failed) failed"
        statusItem?.button?.setAccessibilityLabel(statusItem?.button?.toolTip)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        add("VideoVault", to: menu, action: nil)
        add("Active: \(counts.active)   Queue: \(counts.queued)   Failed: \(counts.failed)", to: menu, action: nil)
        menu.addItem(.separator())
        let hasURLs = !DownloadManager.urls(from: NSPasteboard.general.string(forType: .string) ?? "").isEmpty
        let video = add("Quick Paste: Best Video Quality", to: menu, action: #selector(pasteVideo))
        video.isEnabled = hasURLs
        let audio = add("Quick Paste: Best Audio Quality", to: menu, action: #selector(pasteAudio))
        audio.isEnabled = hasURLs
        if !DownloadManager.shared.clipboardStatus.isEmpty { add(DownloadManager.shared.clipboardStatus, to: menu, action: nil) }
        menu.addItem(.separator())
        add("Add URLs...", to: menu, action: #selector(addDownloads))
        add("Open VideoVault Home", to: menu, action: #selector(home))
        add("Open Download Folder", to: menu, action: #selector(openFolder))
        add("Find Duplicates...", to: menu, action: #selector(findDuplicates))
        menu.addItem(.separator())
        add("Start Queue", to: menu, action: #selector(startQueue)).isEnabled = counts.queued > 0
        add("Retry Failed", to: menu, action: #selector(retryFailed)).isEnabled = counts.failed > 0
        add("Stop All Downloads", to: menu, action: #selector(stopAll)).isEnabled = counts.active + counts.queued > 0
        menu.addItem(.separator())
        add("Check for App Updates...", to: menu, action: #selector(checkAppUpdates))
        add("Update yt-dlp", to: menu, action: #selector(updateYTDLP)).isEnabled = !DependencyUpdateService.shared.isBusy
        add("Settings...", to: menu, action: #selector(settings))
        menu.addItem(.separator())
        add("Quit VideoVault", to: menu, action: #selector(quit))
        menu.autoenablesItems = false
    }

    @discardableResult private func add(_ title: String, to menu: NSMenu, action: Selector?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.isEnabled = action != nil
        menu.addItem(item)
        return item
    }
    func showWindow(notification: Notification.Name? = nil) {
        pendingWindowAction = notification
        openWindow?()
        NSApp.activate(ignoringOtherApps: true)
        if windowReady { performPendingWindowAction() }
    }
    func windowDidAppear() {
        windowReady = true
        performPendingWindowAction()
    }
    func windowDidDisappear() { windowReady = false }
    private func performPendingWindowAction() {
        guard let notification = pendingWindowAction else { return }
        pendingWindowAction = nil
        NotificationCenter.default.post(name: notification, object: nil)
    }
    @objc private func pasteVideo() { DownloadManager.shared.quickPaste(format: .bestVideo) }
    @objc private func pasteAudio() { DownloadManager.shared.quickPaste(format: .bestAudio) }
    @objc private func addDownloads() { showWindow(notification: .showAddDownloads) }
    @objc private func home() { showWindow(notification: .showHome) }
    @objc private func openFolder() { StorageManager.shared.openDownloadFolder() }
    @objc private func findDuplicates() { showWindow(notification: .showDuplicates) }
    @objc private func startQueue() { DownloadManager.shared.processQueue() }
    @objc private func retryFailed() { DownloadManager.shared.retryAllFailed() }
    @objc private func stopAll() { DownloadManager.shared.cancelAllDownloads() }
    @objc private func checkAppUpdates() { checkForAppUpdates?() }
    @objc private func updateYTDLP() { Task { await DependencyUpdateService.shared.checkAndUpdate(install: true) } }
    @objc private func settings() { showWindow(notification: .showSettings) }
    @objc private func quit() { NSApp.terminate(nil) }
}
