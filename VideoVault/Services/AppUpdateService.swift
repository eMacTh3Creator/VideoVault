import Foundation
import Combine
import Sparkle

@MainActor
final class AppUpdateService: NSObject, ObservableObject, SPUUpdaterDelegate {
    static let shared = AppUpdateService()
    @Published private(set) var canCheckForUpdates = false
    @Published var automaticallyChecks = true {
        didSet { if controller.updater.automaticallyChecksForUpdates != automaticallyChecks { controller.updater.automaticallyChecksForUpdates = automaticallyChecks } }
    }
    @Published var automaticallyInstalls = true {
        didSet { if controller.updater.automaticallyDownloadsUpdates != automaticallyInstalls { controller.updater.automaticallyDownloadsUpdates = automaticallyInstalls } }
    }
    private var controller: SPUStandardUpdaterController!

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
    }

    func start() {
        controller.startUpdater()
        automaticallyChecks = controller.updater.automaticallyChecksForUpdates
        automaticallyInstalls = controller.updater.automaticallyDownloadsUpdates
        controller.updater.publisher(for: \.canCheckForUpdates).receive(on: DispatchQueue.main).assign(to: &$canCheckForUpdates)
        controller.updater.publisher(for: \.automaticallyChecksForUpdates).receive(on: DispatchQueue.main).assign(to: &$automaticallyChecks)
        controller.updater.publisher(for: \.automaticallyDownloadsUpdates).receive(on: DispatchQueue.main).assign(to: &$automaticallyInstalls)
    }
    func checkForUpdates() { controller.checkForUpdates(nil) }

    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
                 untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        guard DownloadManager.shared.isProcessing else { return false }
        Task {
            while DownloadManager.shared.isProcessing { try? await Task.sleep(nanoseconds: 500_000_000) }
            installHandler()
        }
        return true
    }
}
