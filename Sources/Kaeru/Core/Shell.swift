import Foundation

/// Locates command-line helpers, preferring copies bundled inside the app.
enum Tools {
    static func path(_ name: String) -> String? {
        var candidates: [String] = []
        if let res = Bundle.main.resourceURL {
            candidates.append(res.appendingPathComponent("bin/\(name)").path)
        }
        candidates += ["/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)", "/usr/bin/\(name)", "/bin/\(name)"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func require(_ name: String, hint: String) throws -> String {
        guard let p = path(name) else { throw fail("\(name) is not installed. \(hint)") }
        return p
    }

    static func ffmpeg() throws -> String { try require("ffmpeg", hint: "Install it with: brew install ffmpeg") }
    static func ffprobe() throws -> String { try require("ffprobe", hint: "Install it with: brew install ffmpeg") }
}

enum Shell {
    /// Runs a process, streaming stdout lines to `onLine`, and throws with the stderr tail on failure.
    @discardableResult
    static func run(_ executable: String, _ args: [String], cwd: URL? = nil, env: [String: String] = [:],
                    onLine: ((String) -> Void)? = nil) async throws -> String {
        try Task.checkCancellation()
        let process = Process()
        // Cancelling the surrounding task (e.g. the Cancel button in the HUD) stops the process.
        return try await withTaskCancellationHandler {
            try await launch(process, executable, args, cwd: cwd, env: env, onLine: onLine)
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }

    private static func launch(_ process: Process, _ executable: String, _ args: [String], cwd: URL?,
                               env: [String: String], onLine: ((String) -> Void)?) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = args
            if let cwd { process.currentDirectoryURL = cwd }
            if !env.isEmpty {
                process.environment = ProcessInfo.processInfo.environment.merging(env) { $1 }
            }
            let out = Pipe(), err = Pipe()
            process.standardOutput = out
            process.standardError = err
            process.standardInput = FileHandle.nullDevice

            let collector = Collector(onLine: onLine)
            out.fileHandleForReading.readabilityHandler = { h in
                let d = h.availableData
                if d.isEmpty { h.readabilityHandler = nil } else { collector.appendOut(d) }
            }
            err.fileHandleForReading.readabilityHandler = { h in
                let d = h.availableData
                if d.isEmpty { h.readabilityHandler = nil } else { collector.appendErr(d) }
            }
            process.terminationHandler = { p in
                out.fileHandleForReading.readabilityHandler = nil
                err.fileHandleForReading.readabilityHandler = nil
                collector.appendOut(out.fileHandleForReading.readDataToEndOfFile())
                collector.appendErr(err.fileHandleForReading.readDataToEndOfFile())
                if p.terminationReason == .uncaughtSignal {
                    cont.resume(throwing: CancellationError())
                } else if p.terminationStatus == 0 {
                    cont.resume(returning: collector.stdout)
                } else {
                    let name = URL(fileURLWithPath: executable).lastPathComponent
                    cont.resume(throwing: fail("\(name) failed: \(collector.stderrTail)"))
                }
            }
            do { try process.run() } catch { cont.resume(throwing: error) }
        }
    }

    private final class Collector {
        private let lock = NSLock()
        private var outData = Data()
        private var errData = Data()
        private var partial = ""
        private let onLine: ((String) -> Void)?

        init(onLine: ((String) -> Void)?) { self.onLine = onLine }

        func appendOut(_ d: Data) {
            guard !d.isEmpty else { return }
            lock.lock()
            outData.append(d)
            var lines: [String] = []
            if onLine != nil {
                partial += String(decoding: d, as: UTF8.self)
                var parts = partial.components(separatedBy: "\n")
                partial = parts.removeLast()
                lines = parts
            }
            lock.unlock()
            lines.forEach { onLine?($0) }
        }

        func appendErr(_ d: Data) {
            lock.lock(); errData.append(d); lock.unlock()
        }

        var stdout: String { lock.lock(); defer { lock.unlock() }; return String(decoding: outData, as: UTF8.self) }

        var stderrTail: String {
            lock.lock(); defer { lock.unlock() }
            let lines = String(decoding: errData, as: UTF8.self)
                .split(separator: "\n").map(String.init).filter { !$0.isEmpty }
            return lines.suffix(3).joined(separator: " · ")
        }
    }
}
