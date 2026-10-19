import Foundation

enum ArchiveOps {
    static let zipOp = FileOperation(id: "archive.zip", title: "ZIP", symbol: "doc.zipper", targetExt: "zip") { urls, _ in
        let out: URL
        if urls.count == 1 {
            out = Output.file(for: urls[0], ext: "zip")
            try await Shell.run("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", urls[0].path, out.path])
        } else {
            out = Output.file(named: "Archive.zip", near: urls[0])
            let (cwd, names) = try staged(urls)
            try await Shell.run("/usr/bin/zip", ["-r", "-X", "-q", out.path] + names + ["-x", "*.DS_Store", "__MACOSX/*"], cwd: cwd)
        }
        return OpResult(outputs: [out])
    }

    static let tarOp = FileOperation(id: "archive.targz", title: "TAR.GZ", symbol: "shippingbox", targetExt: "gz") { urls, _ in
        let name = urls.count == 1 ? urls[0].lastPathComponent + ".tar.gz" : "Archive.tar.gz"
        let out = Output.file(named: name, near: urls[0])
        let (cwd, names) = try staged(urls)
        try await Shell.run("/usr/bin/tar", ["-czf", out.path, "--exclude", ".DS_Store"] + names, cwd: cwd,
                            env: ["COPYFILE_DISABLE": "1"])  // no AppleDouble ._ files
        return OpResult(outputs: [out])
    }

    static let extractOp = FileOperation.perFile("archive.extract", "Extract", "arrow.up.bin") { url, _ in
        let dest = try Output.folder(for: url)
        let ext = url.pathExtension.lowercased()
        let name = url.lastPathComponent.lowercased()
        if ext == "zip" {
            try await Shell.run("/usr/bin/ditto", ["-x", "-k", url.path, dest.path])
        } else if ext == "gz" && !name.hasSuffix(".tar.gz") {
            let target = dest.appendingPathComponent(url.deletingPathExtension().lastPathComponent)
            try await Shell.run("/bin/sh", ["-c", "gunzip -c \"$0\" > \"$1\"", url.path, target.path])
        } else {
            // bsdtar (libarchive) also handles rar, 7z, xz and bz2.
            try await Shell.run("/usr/bin/tar", ["-xf", url.path, "-C", dest.path])
        }
        return [flattenSingleItem(dest)]
    }

    /// If the archive held exactly one item, lift it out instead of nesting it in a folder.
    private static func flattenSingleItem(_ folder: URL) -> URL {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter({ !["__MACOSX", ".DS_Store"].contains($0.lastPathComponent) }),
            items.count == 1 else { return folder }
        let target = Output.unique(folder.deletingLastPathComponent().appendingPathComponent(items[0].lastPathComponent))
        guard (try? fm.moveItem(at: items[0], to: target)) != nil else { return folder }
        try? fm.removeItem(at: folder)
        return target
    }

    /// Archive tools need relative names; items from different folders are copied into one temp folder.
    private static func staged(_ urls: [URL]) throws -> (URL, [String]) {
        let parents = Set(urls.map { $0.deletingLastPathComponent().path })
        if parents.count == 1 { return (urls[0].deletingLastPathComponent(), urls.map(\.lastPathComponent)) }
        let dir = try Output.tempDirectory()
        for url in urls {
            try FileManager.default.copyItem(at: url, to: dir.appendingPathComponent(url.lastPathComponent))
        }
        return (dir, urls.map(\.lastPathComponent))
    }
}
