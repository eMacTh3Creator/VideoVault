import Foundation
import Darwin

enum BackgroundWork {
    static func run<Value: Sendable>(_ operation: @escaping @Sendable () async throws -> Value) async throws -> Value {
        let task = Task.detached(priority: .utility, operation: operation)
        return try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
    }
}

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
                    self.process = child
                    self.lastActivity = Date()
                    self.lock.unlock()
                    do { try child.run() }
                    catch {
                        continuation.resume(throwing: error)
                        return
                    }
                    self.lock.lock()
                    let cancelledDuringLaunch = self.stopped
                    self.lock.unlock()
                    if cancelledDuringLaunch { Self.terminate(child) }

                    let output = LockedOutput()
                    let errors = LockedOutput()
                    let readers = DispatchGroup()
                    var pipeReaders: [ProcessPipeReader] = []
                    for (pipe, capture, reportsLines) in [(stdout, output, true), (stderr, errors, false)] {
                        pipeReaders.append(ProcessPipeReader(handle: pipe.fileHandleForReading, capture: capture,
                            group: readers, onData: {
                                self.lock.lock(); self.lastActivity = Date(); self.lock.unlock()
                            }, onLine: reportsLines ? onLine : nil))
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
                    // A descendant can inherit a pipe after its parent exits. Never wait forever for EOF.
                    let pipesClosed = readers.wait(timeout: .now() + 1) == .success
                    if !pipesClosed {
                        pipeReaders.forEach { $0.cancel() }
                        readers.wait()
                    }
                    self.lock.lock()
                    let wasStopped = self.stopped
                    let wasTimedOut = self.timedOut
                    self.process = nil
                    self.lock.unlock()
                    if wasTimedOut { continuation.resume(throwing: ProcessFailure.timedOut) }
                    else if wasStopped { continuation.resume(throwing: CancellationError()) }
                    else if !pipesClosed { continuation.resume(throwing: ProcessFailure.failed("The downloader exited but left its output open. Please retry the download.")) }
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
        guard let child else { return }
        Self.terminate(child)
    }

    private static func terminate(_ child: Process) {
        // Cancellation handlers may execute on the UI thread. Process-tree inspection must not.
        DispatchQueue.global(qos: .utility).async {
            guard child.isRunning else { return }
            let descendants = Self.descendants(of: child.processIdentifier)
            for pid in descendants.reversed() { kill(pid, SIGTERM) }
            kill(child.processIdentifier, SIGTERM)
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) {
                for pid in descendants.reversed() { kill(pid, SIGKILL) }
                if child.isRunning { kill(child.processIdentifier, SIGKILL) }
            }
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

// Nonblocking descriptors let cancellation close an inherited pipe without a stuck read thread.
private final class ProcessPipeReader: @unchecked Sendable {
    private let source: DispatchSourceRead
    private let handle: FileHandle
    private let capture: LockedOutput
    private let onData: @Sendable () -> Void
    private let onLine: (@Sendable (String) -> Void)?
    private var pending = Data()

    init(handle: FileHandle, capture: LockedOutput, group: DispatchGroup,
         onData: @escaping @Sendable () -> Void, onLine: (@Sendable (String) -> Void)?) {
        self.handle = handle
        self.capture = capture
        self.onData = onData
        self.onLine = onLine
        let fd = handle.fileDescriptor
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        source = DispatchSource.makeReadSource(fileDescriptor: fd,
            queue: DispatchQueue(label: "VideoVault.ProcessPipe", qos: .utility))
        group.enter()
        source.setEventHandler { [weak self] in self?.readAvailable() }
        source.setCancelHandler { [weak self] in
            if let self {
                if !self.pending.isEmpty { self.onLine?(String(decoding: self.pending, as: UTF8.self)) }
                try? self.handle.close()
            }
            group.leave()
        }
        source.resume()
    }

    func cancel() { source.cancel() }

    private func readAvailable() {
        var bytes = [UInt8](repeating: 0, count: 65536)
        for _ in 0..<16 {
            guard !source.isCancelled else { return }
            let count = Darwin.read(handle.fileDescriptor, &bytes, bytes.count)
            if count == 0 { source.cancel(); return }
            if count < 0 {
                if errno == EINTR { continue }
                if errno != EAGAIN && errno != EWOULDBLOCK { source.cancel() }
                return
            }
            let data = Data(bytes.prefix(count))
            onData()
            capture.append(data)
            if let onLine {
                pending.append(data)
                while let end = pending.firstIndex(of: 10) {
                    onLine(String(decoding: pending.prefix(upTo: end), as: UTF8.self))
                    pending.removeSubrange(...end)
                }
                if pending.count > 1024 * 1024 { pending.removeAll() }
            }
        }
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
