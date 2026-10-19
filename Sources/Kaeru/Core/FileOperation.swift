import Foundation

/// The three wheels, each opened by its own modifier key.
enum WheelMode: Int, CaseIterable {
    case convert, tools, actions

    var title: String { ["Convert", "Tools", "Actions"][rawValue] }
    var symbol: String { ["arrow.triangle.2.circlepath", "wrench.and.screwdriver", "bolt.fill"][rawValue] }
}

struct OpResult {
    var outputs: [URL] = []
    var message: String? = nil
}

typealias ProgressHandler = (Double) -> Void

/// One slice of the wheel: a conversion, tool or action that runs on a set of files.
struct FileOperation: Identifiable {
    let id: String
    let title: String
    let symbol: String
    /// Extension this operation produces; used to hide "JPG → JPG" style no-ops.
    var targetExt: String? = nil
    /// Actions finish instantly and run on the main thread, so they skip the progress HUD.
    var isInstant = false
    let run: ([URL], @escaping ProgressHandler) async throws -> OpResult
}

extension FileOperation {
    /// Runs `body` on each input in turn, merging outputs and spreading progress across files.
    static func perFile(_ id: String, _ title: String, _ symbol: String, ext: String? = nil,
                        _ body: @escaping (URL, @escaping ProgressHandler) async throws -> [URL]) -> FileOperation {
        FileOperation(id: id, title: title, symbol: symbol, targetExt: ext) { inputs, progress in
            var outputs: [URL] = []
            let n = Double(inputs.count)
            for (i, url) in inputs.enumerated() {
                outputs += try await body(url) { p in progress((Double(i) + p) / n) }
                progress(Double(i + 1) / n)
            }
            return OpResult(outputs: outputs)
        }
    }

    /// Like `perFile`, but reports how much smaller the outputs are than the inputs.
    static func shrinking(_ id: String, _ title: String, _ symbol: String,
                          _ body: @escaping (URL, @escaping ProgressHandler) async throws -> [URL]) -> FileOperation {
        let inner = perFile(id, title, symbol, body)
        return FileOperation(id: id, title: title, symbol: symbol) { inputs, progress in
            var result = try await inner.run(inputs, progress)
            let before = inputs.reduce(0) { $0 + Output.size(of: $1) }
            let after = result.outputs.reduce(0) { $0 + Output.size(of: $1) }
            if before > 0 {
                let pct = Int((1 - Double(after) / Double(before)) * 100)
                result.message = "\(Output.format(bytes: before)) → \(Output.format(bytes: after)) (\(pct >= 0 ? "−\(pct)" : "+\(-pct)")%)"
            }
            return result
        }
    }
}

enum KaeruError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self { case .message(let m): return m }
    }
}

func fail(_ message: String) -> KaeruError { .message(message) }
