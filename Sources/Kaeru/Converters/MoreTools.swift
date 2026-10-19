import Foundation
import PDFKit

/// Tools for file types whose ⌘ wheel would otherwise be empty: Office packages, presentations,
/// spreadsheets, subtitles, archives, folders and plists.
enum OfficeTools {
    private static let imageExts: Set<String> = ["png", "jpg", "jpeg", "gif", "bmp", "tif", "tiff", "webp", "svg", "emf", "wmf"]

    /// Pulls every embedded picture out of a zip-based document (DOCX, PPTX, XLSX, ODT, EPUB).
    static let extractImages = FileOperation.perFile("office.images", "Extract Images", "photo.stack") { url, _ in
        let entries = try await ZipPackage.entries(url).filter {
            !$0.hasSuffix("/") && imageExts.contains(($0 as NSString).pathExtension.lowercased())
        }
        guard !entries.isEmpty else { throw fail("\(url.lastPathComponent) has no embedded images") }
        let tmp = try Output.tempDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        try await Shell.run("/usr/bin/unzip", ["-q", "-o", url.path] + entries + ["-d", tmp.path])
        let folder = try Output.folder(for: url, suffix: "images")
        for entry in entries {
            let source = tmp.appendingPathComponent(entry)
            let target = Output.unique(folder.appendingPathComponent((entry as NSString).lastPathComponent))
            try? FileManager.default.moveItem(at: source, to: target)
        }
        return [folder]
    }

    /// Re-encodes large embedded JPEG/PNG pictures (max 2000px), keeping every file name and reference intact.
    static let compress = FileOperation.shrinking("office.compress", "Compress", "arrow.down.right.and.arrow.up.left") { url, _ in
        let tmp = try Output.tempDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        try await Shell.run("/usr/bin/ditto", ["-x", "-k", url.path, tmp.path])
        let files = FileManager.default.enumerator(at: tmp, includingPropertiesForKeys: [.fileSizeKey])
        while let file = files?.nextObject() as? URL {
            let ext = file.pathExtension.lowercased()
            guard ["jpg", "jpeg", "png"].contains(ext), Output.size(of: file) > 150_000,
                  let (image, _) = try? ImageOps.load(file, maxPixel: 2000) else { continue }
            let candidate = Output.temp(ext: ext == "jpeg" ? "jpg" : ext)
            defer { try? FileManager.default.removeItem(at: candidate) }
            try? await ImageOps.write(image, to: candidate, quality: 0.72)
            if Output.size(of: candidate) > 0, Output.size(of: candidate) < Output.size(of: file) {
                _ = try? FileManager.default.replaceItemAt(file, withItemAt: candidate)
            }
        }
        let out = Output.file(for: url, ext: url.pathExtension.lowercased(), suffix: "compressed")
        // ODF and EPUB need an uncompressed "mimetype" entry first.
        if FileManager.default.fileExists(atPath: tmp.appendingPathComponent("mimetype").path) {
            try await Shell.run("/usr/bin/zip", ["-X", "-0", "-q", out.path, "mimetype"], cwd: tmp)
            try await Shell.run("/usr/bin/zip", ["-X", "-r", "-q", out.path, ".", "-x", "mimetype"], cwd: tmp)
        } else {
            try await Shell.run("/usr/bin/zip", ["-X", "-r", "-q", out.path, "."], cwd: tmp)
        }
        return [out]
    }

    static func presentationOps(for url: URL) -> [FileOperation] {
        var ops: [FileOperation] = [extractSlideText, slideCount]
        if url.pathExtension.lowercased() == "pptx" { ops += [extractImages, compress] }
        return ops
    }

    /// Slide text, slide by slide. PPTX is read directly; PPT and Keynote go through a PDF export.
    static let extractSlideText = FileOperation.perFile("slides.text", "Extract Text", "text.alignleft") { url, _ in
        let slides = try await slideTexts(url)
        let out = Output.file(for: url, ext: "txt")
        let text = slides.enumerated().map { "Slide \($0.offset + 1)\n\($0.element)" }.joined(separator: "\n\n")
        try text.write(to: out, atomically: true, encoding: .utf8)
        return [out]
    }

    static let slideCount = FileOperation(id: "slides.count", title: "Slide Count", symbol: "number") { urls, _ in
        var slides = 0, words = 0
        for url in urls {
            let texts = try await slideTexts(url)
            slides += texts.count
            words += texts.joined(separator: " ").split { $0.isWhitespace }.count
        }
        return OpResult(message: "\(slides) slides · \(words.formatted()) words")
    }

    static func slideTexts(_ url: URL) async throws -> [String] {
        if url.pathExtension.lowercased() == "pptx" {
            let slidePaths = try await ZipPackage.entries(url)
                .filter { $0.hasPrefix("ppt/slides/slide") && $0.hasSuffix(".xml") }
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            var texts: [String] = []
            for path in slidePaths {
                let xml = try await ZipPackage.read(url, entry: path)
                // One line per paragraph (<a:p>), joining its text runs (<a:t>).
                let paragraphs = xml.components(separatedBy: "</a:p>").map { para -> String in
                    matches("<a:t>([^<]*)</a:t>", in: para).joined()
                }.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                texts.append(unescape(paragraphs.joined(separator: "\n")))
            }
            return texts
        }
        let (pdf, _) = try await PresentationOps.toPDF(url)
        defer { try? FileManager.default.removeItem(at: pdf) }
        guard let doc = PDFDocument(url: pdf) else { throw fail("Couldn't read \(url.lastPathComponent)") }
        return (0..<doc.pageCount).map { doc.page(at: $0)?.string ?? "" }
    }

    private static func matches(_ pattern: String, in text: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        return re.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range(at: 1), in: text).map { String(text[$0]) }
        }
    }

    private static func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}

extension DataOps {
    /// Same format in and out, except XLS, which can be read but not written.
    private static func tableOutputExt(_ url: URL) -> String {
        let ext = FileKind.normalizedExt(url.pathExtension)
        return ext == "xls" ? "xlsx" : ext
    }

    private static func tableTool(_ id: String, _ title: String, _ symbol: String, suffix: String,
                                  _ transform: @escaping ([[String]]) -> [[String]]) -> FileOperation {
        .perFile(id, title, symbol) { url, _ in
            let rows = try await readTable(url)
            let out = Output.file(for: url, ext: tableOutputExt(url), suffix: suffix)
            try await writeTable(transform(rows), to: out)
            return [out]
        }
    }

    static func tableToolOps() -> [FileOperation] {
        [
            tableTool("table.dedupe", "Remove Duplicates", "line.3.horizontal.decrease", suffix: "deduplicated") { rows in
                var seen = Set<[String]>()
                return rows.enumerated().filter { $0.offset == 0 || seen.insert($0.element).inserted }.map(\.element)
            },
            tableTool("table.sort", "Sort A→Z", "arrow.up.arrow.down", suffix: "sorted") { rows in
                guard let header = rows.first else { return rows }
                return [header] + rows.dropFirst().sorted {
                    ($0.first ?? "").localizedStandardCompare($1.first ?? "") == .orderedAscending
                }
            },
            tableTool("table.transpose", "Transpose", "arrow.triangle.swap", suffix: "transposed") { rows in
                let width = rows.map(\.count).max() ?? 0
                return (0..<width).map { c in rows.map { c < $0.count ? $0[c] : "" } }
            },
            tableTool("table.trim", "Trim Spaces", "scissors", suffix: "trimmed") { rows in
                rows.map { $0.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } }
                    .filter { $0.contains { !$0.isEmpty } }
            },
            FileOperation(id: "table.count", title: "Row Count", symbol: "number") { urls, _ in
                var rows = 0, columns = 0
                for url in urls {
                    let table = try await readTable(url)
                    rows += max(0, table.count - 1)
                    columns = max(columns, table.map(\.count).max() ?? 0)
                }
                return OpResult(message: "\(rows.formatted()) rows · \(columns) columns (plus a header row)")
            },
        ]
    }

    static func subtitleToolOps() -> [FileOperation] {
        func shifted(_ id: String, _ title: String, _ symbol: String, by seconds: Double) -> FileOperation {
            .perFile(id, title, symbol) { url, _ in
                let cues = parseSubtitles(try readText(url)).map { cue in
                    (start: shift(cue.start, seconds), end: shift(cue.end, seconds), text: cue.text)
                }
                let ext = FileKind.normalizedExt(url.pathExtension)
                let out = Output.file(for: url, ext: ext, suffix: seconds > 0 ? "+\(Int(seconds))s" : "\(Int(seconds))s")
                try formatSubtitles(cues, as: ext).write(to: out, atomically: true, encoding: .utf8)
                return [out]
            }
        }
        return [
            shifted("sub.later", "Shift +1s", "goforward", by: 1),
            shifted("sub.earlier", "Shift −1s", "gobackward", by: -1),
            .perFile("sub.plain", "Remove Formatting", "textformat") { url, _ in
                let cues = parseSubtitles(try readText(url)).map { cue in
                    (start: cue.start, end: cue.end,
                     text: cue.text.replacingOccurrences(of: "<[^>]+>|\\{[^}]*\\}", with: "", options: .regularExpression))
                }
                let ext = FileKind.normalizedExt(url.pathExtension)
                let out = Output.file(for: url, ext: ext, suffix: "plain")
                try formatSubtitles(cues, as: ext).write(to: out, atomically: true, encoding: .utf8)
                return [out]
            },
        ]
    }

    /// "00:01:02.500" shifted by `seconds`, clamped at zero.
    static func shift(_ time: String, _ seconds: Double) -> String {
        let parts = time.split(separator: ":").compactMap { Double($0) }
        guard parts.count == 3 else { return time }
        let total = max(0, parts[0] * 3600 + parts[1] * 60 + parts[2] + seconds)
        let ms = Int((total * 1000).rounded())
        return String(format: "%02d:%02d:%02d.%03d", ms / 3_600_000, ms / 60_000 % 60, ms / 1000 % 60, ms % 1000)
    }

    static func plistToolOps() -> [FileOperation] {
        [("xml", "XML Plist", PropertyListSerialization.PropertyListFormat.xml),
         ("binary", "Binary Plist", PropertyListSerialization.PropertyListFormat.binary)].map { tag, title, format in
            .perFile("plist.\(tag)", title, "list.bullet.indent") { url, _ in
                let object = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil)
                let out = Output.file(for: url, ext: "plist", suffix: tag)
                try PropertyListSerialization.data(fromPropertyList: object, format: format, options: 0).write(to: out)
                return [out]
            }
        }
    }
}

extension ArchiveOps {
    static let toolOps: [FileOperation] = [
        FileOperation(id: "archive.list", title: "List Contents", symbol: "list.bullet") { urls, _ in
            var files = 0
            for url in urls { files += try await entries(url).filter { !$0.hasSuffix("/") }.count }
            let size = urls.reduce(0) { $0 + Output.size(of: $1) }
            return OpResult(message: "\(files.formatted()) files · \(Output.format(bytes: size)) compressed")
        },
        FileOperation(id: "archive.test", title: "Test Archive", symbol: "checkmark.shield") { urls, _ in
            for url in urls {
                if url.pathExtension.lowercased() == "zip" {
                    try await Shell.run("/usr/bin/unzip", ["-tq", url.path])
                } else {
                    try await Shell.run("/usr/bin/tar", ["-tf", url.path])
                }
            }
            return OpResult(message: urls.count == 1 ? "\(urls[0].lastPathComponent) is intact" : "All \(urls.count) archives are intact")
        },
    ]

    static func entries(_ url: URL) async throws -> [String] {
        let output = url.pathExtension.lowercased() == "zip"
            ? try await Shell.run("/usr/bin/zipinfo", ["-1", url.path])
            : try await Shell.run("/usr/bin/tar", ["-tf", url.path])
        return output.split(separator: "\n").map(String.init)
    }
}

enum FolderTools {
    static let all: [FileOperation] = [
        FileOperation(id: "folder.info", title: "Folder Info", symbol: "info.circle") { urls, _ in
            var files = 0
            for url in urls {
                let items = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey],
                                                           options: [.skipsHiddenFiles])
                while let item = items?.nextObject() as? URL {
                    if (try? item.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true { files += 1 }
                }
            }
            let size = urls.reduce(0) { $0 + Output.size(of: $1) }
            return OpResult(message: "\(files.formatted()) files · \(Output.format(bytes: size))")
        },
        .perFile("folder.pdf", "Images → PDF", "doc.richtext") { url, progress in
            let images = (try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil,
                                                                      options: [.skipsHiddenFiles]))
                .filter { FileKind.of($0) == .image }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            guard !images.isEmpty else { throw fail("\(url.lastPathComponent) has no images") }
            let doc = PDFDocument()
            for (i, image) in images.enumerated() {
                let tmp = Output.temp(ext: "pdf")
                defer { try? FileManager.default.removeItem(at: tmp) }
                try ImageOps.makePDF(images: [try ImageOps.load(image, maxPixel: 3000).0], to: tmp)
                if let page = PDFDocument(url: tmp)?.page(at: 0) { doc.insert(page, at: doc.pageCount) }
                progress(Double(i + 1) / Double(images.count))
            }
            let out = Output.unique(Output.directory(for: url).appendingPathComponent(url.lastPathComponent + ".pdf"))
            guard doc.write(to: out) else { throw fail("Couldn't write PDF") }
            return [out]
        },
    ]
}
