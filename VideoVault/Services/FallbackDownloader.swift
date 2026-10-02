import Foundation
import CryptoKit

enum FallbackDownloader {
    static func download(url: String, format: DownloadFormat, directory: URL, streamlink: String, ffmpeg: String,
                         progress: @escaping @Sendable (Double, String) -> Void) async throws -> DownloadResult {
        guard FileManager.default.isExecutableFile(atPath: ffmpeg) else {
            throw ProcessFailure.failed("Fallback requires ffmpeg. Install it in Settings.")
        }
        let workspace = directory.appendingPathComponent(".fallback-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }
        let remote = URL(string: url)
        let direct = remote.map { ["mp4", "mkv", "webm", "mov", "m4a", "mp3", "aac", "ogg", "opus", "flac", "wav", "m3u8", "mpd", "ts"].contains($0.pathExtension.lowercased()) } ?? false
        var input = url
        var engine = "ffmpeg (direct media)"
        if !direct {
            let executable = FileManager.default.isExecutableFile(atPath: streamlink) ? streamlink : YTDLPService.findExecutable("streamlink")
            guard let executable else { throw ProcessFailure.failed("Streamlink is not installed. Use Install Streamlink in Settings to enable site fallback.") }
            let supported = try await ProcessRunner().run(executable: executable, arguments: ["--can-handle-url", url], timeout: 15)
            guard supported.exitCode == 0 else { throw ProcessFailure.failed("Streamlink has no plugin for this website. Open the original page to check availability.") }
            let transport = workspace.appendingPathComponent("stream.ts")
            var args = ["--output", transport.path, "--force", "--progress", "force", "--http-timeout", "20", "--stream-timeout", "60",
                        "--stream-segment-attempts", "3", "--retry-open", "2"]
            if let height = format.maxHeight { args += ["--stream-sorting-excludes", ">\(height)p"] }
            args += [url, format.isAudioOnly ? "audio_only,audio,best,best-unfiltered" : "best,best-unfiltered"]
            progress(0, "Streamlink downloading")
            let result = try await ProcessRunner().run(executable: executable, arguments: args, timeout: 180, inactivityTimeout: true)
            guard result.exitCode == 0 else { throw ProcessFailure.failed(result.message) }
            input = transport.path
            engine = "Streamlink"
        }
        try Task.checkCancellation()
        let ext = format == .mp3 ? "mp3" : (format.isAudioOnly ? "mka" : "mkv")
        let converted = workspace.appendingPathComponent("output.\(ext)")
        var args = ["-nostdin", "-hide_banner", "-loglevel", "warning", "-y"]
        if direct { args += ["-rw_timeout", "20000000"] }
        args += ["-i", input]
        if format == .mp3 { args += ["-vn", "-c:a", "libmp3lame", "-q:a", "0"] }
        else if format.isAudioOnly { args += ["-vn", "-c:a", "copy"] }
        else if direct, let height = format.maxHeight {
            args += ["-vf", "scale=-2:'min(\(height),ih)'", "-c:v", "libx264", "-crf", "18", "-c:a", "copy"]
        } else { args += ["-c", "copy"] }
        args += ["-progress", "pipe:1", converted.path]
        progress(0.95, "Converting fallback media")
        let result = try await ProcessRunner().run(executable: ffmpeg, arguments: args, timeout: 180, inactivityTimeout: true) { line in
            if line.hasPrefix("out_time=") { progress(0.95, "Converting fallback media") }
        }
        guard result.exitCode == 0, let size = try converted.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 0 else {
            throw ProcessFailure.failed(result.message.isEmpty ? "Fallback produced no media file." : result.message)
        }
        let hash = SHA256.hash(data: Data(DownloadIdentity.canonicalURL(url).utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        let destination = directory.appendingPathComponent("Media-\(hash) [\(format.storageKey)].\(ext)")
        // Publish only a finished conversion; avoid overwriting another download's output.
        let file = FileManager.default.fileExists(atPath: destination.path)
            ? directory.appendingPathComponent("Media-\(hash)-\(UUID().uuidString.prefix(8)) [\(format.storageKey)].\(ext)") : destination
        try FileManager.default.moveItem(at: converted, to: file)
        return DownloadResult(file: file, mediaID: nil, downloader: engine, skipped: false)
    }
}
