import Foundation

/// Decides where results are written and keeps names from colliding.
enum Output {
    static var fm: FileManager { .default }

    /// Set while a job started from a shelf runs, so its results land in the shelf's staging folder.
    @TaskLocal static var overrideDirectory: URL?

    static func directory(for input: URL) -> URL {
        if let overrideDirectory { return overrideDirectory }
        switch Settings.outputLocation {
        case .downloads: return fm.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        case .desktop: return fm.urls(for: .desktopDirectory, in: .userDomainMask)[0]
        case .sameFolder:
            let dir = input.deletingLastPathComponent()
            return fm.isWritableFile(atPath: dir.path) ? dir : fm.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        }
    }

    /// `photo.heic` + `jpg` → `photo.jpg`, or `photo (compressed).jpg` with a suffix.
    static func file(for input: URL, ext: String, suffix: String? = nil) -> URL {
        let base = input.deletingPathExtension().lastPathComponent + (suffix.map { " (\($0))" } ?? "")
        return unique(directory(for: input).appendingPathComponent(base).appendingPathExtension(ext))
    }

    static func file(named name: String, near input: URL) -> URL {
        unique(directory(for: input).appendingPathComponent(name))
    }

    static func folder(for input: URL, suffix: String? = nil) throws -> URL {
        var base = input.deletingPathExtension().lastPathComponent
        if base.hasSuffix(".tar") { base = String(base.dropLast(4)) }
        if let suffix { base += " (\(suffix))" }
        let url = unique(directory(for: input).appendingPathComponent(base))
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func unique(_ url: URL) -> URL {
        guard fm.fileExists(atPath: url.path) else { return url }
        let dir = url.deletingLastPathComponent()
        let ext = url.pathExtension
        let base = url.deletingPathExtension().lastPathComponent
        for i in 2... {
            let candidate = dir.appendingPathComponent("\(base) \(i)").appendingPathExtension(ext)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
        }
        return url
    }

    static func temp(ext: String) -> URL {
        fm.temporaryDirectory.appendingPathComponent("kaeru-\(UUID().uuidString)").appendingPathExtension(ext)
    }

    static func tempDirectory() throws -> URL {
        let url = fm.temporaryDirectory.appendingPathComponent("kaeru-\(UUID().uuidString)")
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func size(of url: URL) -> Int64 {
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue {
            return (try? fm.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        }
        let files = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey])
        var total: Int64 = 0
        while let f = files?.nextObject() as? URL {
            total += Int64((try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }

    static func format(bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
