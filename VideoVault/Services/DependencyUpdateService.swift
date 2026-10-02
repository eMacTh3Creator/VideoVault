import Foundation
import CryptoKit
import Darwin

struct ReleaseAsset: Decodable {
    let name: String
    let browserDownloadURL: URL
    let digest: String?
    enum CodingKeys: String, CodingKey { case name, digest; case browserDownloadURL = "browser_download_url" }
}

struct DependencyRelease: Decodable {
    let tagName: String
    let assets: [ReleaseAsset]
    enum CodingKeys: String, CodingKey { case tagName = "tag_name", assets }
}

enum VerifiedDownload {
    static func request(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        request.setValue("VideoVault", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        return request
    }
    static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ProcessFailure.failed("Update server returned HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0). Try again later.")
        }
    }
    static func release(_ repository: String) async throws -> DependencyRelease {
        let (data, response) = try await URLSession.shared.data(for: request(URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!))
        try validate(response)
        return try JSONDecoder().decode(DependencyRelease.self, from: data)
    }
    static func asset(_ asset: ReleaseAsset, checksum: String? = nil) async throws -> URL {
        let (file, response) = try await URLSession.shared.download(for: request(asset.browserDownloadURL))
        do {
            try validate(response)
            guard let expected = checksum ?? asset.digest?.replacingOccurrences(of: "sha256:", with: ""), expected.count == 64 else {
                throw ProcessFailure.failed("The release has no SHA-256 checksum. Installation was stopped.")
            }
            let actual = try await Task.detached(priority: .utility) { try sha256(file) }.value
            guard actual.lowercased() == expected.lowercased() else { throw ProcessFailure.failed("Update checksum did not match. Installation was stopped.") }
            return file
        } catch { try? FileManager.default.removeItem(at: file); throw error }
    }
    static func sha256(_ file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty {
            try Task.checkCancellation()
            hash.update(data: data)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

@MainActor
final class DependencyUpdateService: ObservableObject {
    static let shared = DependencyUpdateService()
    @Published private(set) var isBusy = false
    @Published private(set) var status = ""
    @Published private(set) var installedVersion = ""
    @Published private(set) var latestVersion = ""
    @Published private(set) var lastChecked: Date?
    private var maintenanceTask: Task<Void, Never>?
    private var deferredTask: Task<Void, Never>?

    static var toolsDirectory: URL {
        if let testRoot = ProcessInfo.processInfo.environment["VIDEOVAULT_TEST_ROOT"] {
            return URL(fileURLWithPath: testRoot).appendingPathComponent("tools", isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("VideoVault/tools", isDirectory: true)
    }

    func startAutomaticChecks() {
        guard maintenanceTask == nil else { return }
        maintenanceTask = Task {
            while !Task.isCancelled {
                if AppSettings.shared.automaticallyUpdateYTDLP { await checkAndUpdate(install: true) }
                try? await Task.sleep(nanoseconds: 6 * 60 * 60 * 1_000_000_000)
            }
        }
    }

    func checkAndUpdate(install: Bool) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false; DownloadManager.shared.processQueue() }
        do {
            status = "Checking latest yt-dlp release..."
            let release = try await VerifiedDownload.release("yt-dlp/yt-dlp")
            latestVersion = release.tagName
            lastChecked = Date()
            let path = AppSettings.shared.ytdlpPath
            if FileManager.default.isExecutableFile(atPath: path) {
                let result = try await ProcessRunner().run(executable: path, arguments: ["--version"], timeout: 10)
                installedVersion = result.exitCode == 0 ? result.output.trimmingCharacters(in: .whitespacesAndNewlines) : ""
            }
            if installedVersion.compare(latestVersion, options: .numeric) != .orderedAscending, !installedVersion.isEmpty {
                status = "yt-dlp \(installedVersion) is up to date."
            } else if install {
                guard !DownloadManager.shared.isProcessing else {
                    status = "yt-dlp \(latestVersion) is available. Update will run after downloads finish."
                    if deferredTask == nil {
                        deferredTask = Task {
                            while DownloadManager.shared.isProcessing { try? await Task.sleep(nanoseconds: 500_000_000) }
                            deferredTask = nil
                            await checkAndUpdate(install: true)
                        }
                    }
                    return
                }
                guard let asset = release.assets.first(where: { $0.name == "yt-dlp_macos" }) else { throw ProcessFailure.failed("Official macOS yt-dlp binary was not found.") }
                var checksum: String?
                if asset.digest == nil, let sums = release.assets.first(where: { $0.name == "SHA2-256SUMS" }) {
                    let (data, response) = try await URLSession.shared.data(for: VerifiedDownload.request(sums.browserDownloadURL))
                    try VerifiedDownload.validate(response)
                    checksum = String(decoding: data, as: UTF8.self).split(separator: "\n").first { $0.split(whereSeparator: \.isWhitespace).last == "yt-dlp_macos" }?.split(whereSeparator: \.isWhitespace).first.map(String.init)
                }
                status = "Downloading verified yt-dlp \(latestVersion)..."
                let temporary = try await VerifiedDownload.asset(asset, checksum: checksum)
                defer { try? FileManager.default.removeItem(at: temporary) }
                try FileManager.default.createDirectory(at: Self.toolsDirectory, withIntermediateDirectories: true)
                let candidate = Self.toolsDirectory.appendingPathComponent("yt-dlp-\(UUID().uuidString)")
                try FileManager.default.copyItem(at: temporary, to: candidate)
                defer { try? FileManager.default.removeItem(at: candidate) }
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: candidate.path)
                let version = try await ProcessRunner().run(executable: candidate.path, arguments: ["--version"], timeout: 30)
                guard version.exitCode == 0, version.output.trimmingCharacters(in: .whitespacesAndNewlines) == release.tagName else {
                    throw ProcessFailure.failed("Downloaded yt-dlp could not be validated on this Mac.")
                }
                let destination = Self.toolsDirectory.appendingPathComponent("yt-dlp")
                guard rename(candidate.path, destination.path) == 0 else { throw ProcessFailure.failed("Could not install yt-dlp: \(String(cString: strerror(errno)))") }
                AppSettings.shared.ytdlpPath = destination.path
                installedVersion = release.tagName
                status = "Updated yt-dlp to \(installedVersion)."
            } else { status = "yt-dlp \(latestVersion) is available." }
            if install, !DownloadManager.shared.isProcessing, YTDLPService.findExecutable("deno") == nil, YTDLPService.findExecutable("node") == nil {
                try await installDeno()
            }
        } catch { status = error.localizedDescription }
    }

    func installDeno() async throws {
        status = "Installing YouTube JavaScript runtime..."
        let release = try await VerifiedDownload.release("denoland/deno")
        #if arch(arm64)
        let name = "deno-aarch64-apple-darwin.zip"
        #else
        let name = "deno-x86_64-apple-darwin.zip"
        #endif
        guard let asset = release.assets.first(where: { $0.name == name }) else { throw ProcessFailure.failed("Deno runtime is not available for this Mac.") }
        let zip = try await VerifiedDownload.asset(asset)
        defer { try? FileManager.default.removeItem(at: zip) }
        let extracted = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: extracted) }
        let unzip = try await ProcessRunner().run(executable: "/usr/bin/ditto", arguments: ["-xk", zip.path, extracted.path])
        guard unzip.exitCode == 0 else { throw ProcessFailure.failed(unzip.message) }
        let binary = extracted.appendingPathComponent("deno")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
        let result = try await ProcessRunner().run(executable: binary.path, arguments: ["--version"], timeout: 10)
        guard result.exitCode == 0, result.output.hasPrefix("deno ") else { throw ProcessFailure.failed("Deno runtime validation failed.") }
        try FileManager.default.createDirectory(at: Self.toolsDirectory, withIntermediateDirectories: true)
        let destination = Self.toolsDirectory.appendingPathComponent("deno")
        if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
        try FileManager.default.copyItem(at: binary, to: destination)
        status = "yt-dlp and YouTube runtime are ready."
    }

    func installStreamlink() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false; DownloadManager.shared.processQueue() }
        status = "Installing Streamlink..."
        do {
            // Use a private environment rather than modifying a user's Python packages.
            guard let python = YTDLPService.findExecutable("python3") else {
                throw ProcessFailure.failed("Install Python 3.10+ or Streamlink with Homebrew (brew install streamlink), then click Detect.")
            }
            let environment = Self.toolsDirectory.appendingPathComponent("streamlink-env")
            try FileManager.default.createDirectory(at: Self.toolsDirectory, withIntermediateDirectories: true)
            let create = try await ProcessRunner().run(executable: python, arguments: ["-m", "venv", environment.path], timeout: 120)
            guard create.exitCode == 0 else { throw ProcessFailure.failed(create.message) }
            let install = try await ProcessRunner().run(executable: environment.appendingPathComponent("bin/python3").path,
                arguments: ["-m", "pip", "install", "--disable-pip-version-check", "--upgrade", "streamlink"], timeout: 600, inactivityTimeout: true)
            guard install.exitCode == 0 else { throw ProcessFailure.failed(install.message) }
            let executable = environment.appendingPathComponent("bin/streamlink").path
            let version = try await ProcessRunner().run(executable: executable, arguments: ["--version"], timeout: 15)
            guard version.exitCode == 0 else { throw ProcessFailure.failed(version.message) }
            AppSettings.shared.streamlinkPath = executable
            status = "\(version.output.trimmingCharacters(in: .whitespacesAndNewlines)) installed."
        } catch { status = error.localizedDescription }
    }
}
