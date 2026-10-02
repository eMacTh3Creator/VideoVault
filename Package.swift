// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VideoVaultCore",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "VideoVaultCore", path: "VideoVault",
            exclude: ["VideoVaultApp.swift", "Views", "Assets.xcassets", "Info.plist", "Services/AppUpdateService.swift"],
            sources: ["Models", "Utilities", "Services/ProcessRunner.swift", "Services/DuplicateLibrary.swift",
                      "Services/FallbackDownloader.swift", "Services/YTDLPService.swift", "Services/DownloadManager.swift",
                      "Services/DependencyUpdateService.swift", "Services/StorageManager.swift",
                      "Services/MenuBarController.swift"]),
        .testTarget(name: "VideoVaultCoreTests", dependencies: ["VideoVaultCore"], path: "Tests")
    ]
)
