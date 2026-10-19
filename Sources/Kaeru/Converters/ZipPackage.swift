import Foundation

/// Zip containers used by EPUB, ODS, XLSX and PPTX.
enum ZipPackage {
    /// Writes `files` (relative path → contents) into a zip at `out`. EPUB and ODF require an
    /// uncompressed `mimetype` entry first, which `mimetype` provides.
    static func write(_ files: [String: Data], to out: URL, mimetype: String? = nil) async throws {
        let dir = try Output.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        for (path, data) in files {
            let file = dir.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file)
        }
        try? FileManager.default.removeItem(at: out)
        if let mimetype {
            try Data(mimetype.utf8).write(to: dir.appendingPathComponent("mimetype"))
            try await Shell.run("/usr/bin/zip", ["-X", "-0", "-q", out.path, "mimetype"], cwd: dir)
        }
        let entries = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0 != "mimetype" }.sorted()
        try await Shell.run("/usr/bin/zip", ["-X", "-r", "-q", out.path] + entries, cwd: dir)
    }

    static func write(_ files: [String: String], to out: URL, mimetype: String? = nil) async throws {
        try await write(files.mapValues { Data($0.utf8) }, to: out, mimetype: mimetype)
    }

    static func read(_ archive: URL, entry: String) async throws -> String {
        try await Shell.run("/usr/bin/unzip", ["-p", archive.path, entry])
    }

    static func entries(_ archive: URL) async throws -> [String] {
        try await Shell.run("/usr/bin/unzip", ["-Z1", archive.path]).split(separator: "\n").map(String.init)
    }

    static func xmlEscape(_ s: String) -> String {
        String(s.unicodeScalars.filter { $0.value >= 0x20 || $0 == "\t" || $0 == "\n" || $0 == "\r" })
            .replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}
