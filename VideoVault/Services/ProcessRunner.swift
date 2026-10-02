import Foundation
import Darwin

struct ProcessResult {
    let output: String
    let errorOutput: String
    let exitCode: Int32

    var message: String {
        let text = errorOutput.isEmpty ? output : errorOutput
        return String(text.suffix(6000)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum ProcessFailure: LocalizedError {
    case timedOut
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .timedOut: return "The downloader stopped responding. Try again or check your connection."
        case .failed(let message): return message
        }
    }
}

// Drain both pipes while the process runs; waiting first can deadlock on a full pipe.
final class ProcessRunner: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var stopped = false
    private var timedOut = false
    private var lastActivity = Date()

    static var environment: [String: String] {
        var values = ProcessInfo.processInfo.environment
        values["PATH"] = NSHomeDirectory() + "/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        values["PYTHONUNBUFFERED"] = "1"
        return values
    }

    func run(executable: String, arguments: [String], directory: URL? = nil,
             timeout: TimeInterval = 120, inactivityTimeout: Bool = false,
             onLine: @escaping @Sendable (String) -> Void = { _ in }) async throws -> ProcessResult {
        try await withTaskCancellationHandler(operation: {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    let child = Process()
                    let stdout = Pipe()
                    let stderr = Pipe()
                    child.executableURL = URL(fileURLWithPath: executable)
                    child.arguments = arguments
                    child.environment = Self.environment
                    child.currentDirectoryURL = directory
                    child.standardOutput = stdout
                    child.standardError = stderr

                    self.lock.lock()
                    if self.stopped {
                        self.lock.unlock()
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    do {
                        try child.run()
                        self.process = child
                        self.lastActivity = Date()
                        self.lock.unlock()
                    } catch {
                        self.lock.unlock()
                        continuation.resume(throwing: error)
                        return
                    }

                    let output = LockedOutput()
                    let errors = LockedOutput()
                    let readers = DispatchGroup()
                    for (pipe, capture, reportsLines) in [(stdout, output, true), (stderr, errors, false)] {
                        readers.enter()
                        DispatchQueue.global(qos: .utility).async {
                            var pending = Data()
                            while true {
                                let data = pipe.fileHandleForReading.availableData
                                if data.isEmpty { break }
                                self.lock.lock()
                                self.lastActivity = Date()
                                self.lock.unlock()
                                capture.append(data)
                                if reportsLines {
                                    pending.append(data)
                                    while let end = pending.firstIndex(of: 10) {
                                        let line = pending.prefix(upTo: end)
                                        onLine(String(decoding: line, as: UTF8.self))
                                        pending.removeSubrange(...end)
                                    }
                                    if pending.count > 1024 * 1024 { pending.removeAll() }
                                }
                            }
                            if reportsLines, !pending.isEmpty { onLine(String(decoding: pending, as: UTF8.self)) }
                            readers.leave()
                        }
                    }

                    let started = Date()
                    while child.isRunning {
                        self.lock.lock()
                        let deadline = inactivityTimeout ? self.lastActivity : started
                        let expired = Date().timeIntervalSince(deadline) > timeout
                        self.lock.unlock()
                        if expired { self.stop(timeout: true) }
                        Thread.sleep(forTimeInterval: 0.05)
                    }
                    child.waitUntilExit()
                    readers.wait()
                    self.lock.lock()
                    let wasStopped = self.stopped
                    let wasTimedOut = self.timedOut
                    self.process = nil
                    self.lock.unlock()
                    if wasTimedOut { continuation.resume(throwing: ProcessFailure.timedOut) }
                    else if wasStopped { continuation.resume(throwing: CancellationError()) }
                    else { continuation.resume(returning: ProcessResult(output: output.text, errorOutput: errors.text, exitCode: child.terminationStatus)) }
                }
            }
        }, onCancel: { self.stop() })
    }

    private func stop(timeout: Bool = false) {
        lock.lock()
        guard !stopped else { lock.unlock(); return }
        stopped = true
        timedOut = timeout
        let child = process
        lock.unlock()
        guard let child, child.isRunning else { return }
        // Stop descendants too (yt-dlp can have an ffmpeg process holding its pipes open).
        let descendants = Self.descendants(of: child.processIdentifier)
        for pid in descendants.reversed() { kill(pid, SIGTERM) }
        child.terminate()
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
            for pid in descendants.reversed() { kill(pid, SIGKILL) }
            if child.isRunning { kill(child.processIdentifier, SIGKILL) }
        }
    }

    private static func descendants(of pid: Int32) -> [Int32] {
        let query = Process()
        let pipe = Pipe()
        query.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        query.arguments = ["-P", String(pid)]
        query.standardOutput = pipe
        query.standardError = FileHandle.nullDevice
        guard (try? query.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        query.waitUntilExit()
        let children = String(decoding: data, as: UTF8.self).split(whereSeparator: \.isWhitespace).compactMap { Int32($0) }
        return children.flatMap { [$0] + descendants(of: $0) }
    }
}

final class LockedOutput: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    func append(_ value: Data) {
        lock.lock(); defer { lock.unlock() }
        data.append(value)
        if data.count > 4 * 1024 * 1024 { data.removeFirst(data.count - 4 * 1024 * 1024) }
    }
    var text: String {
        lock.lock(); defer { lock.unlock() }
        return String(decoding: data, as: UTF8.self)
    }
}
