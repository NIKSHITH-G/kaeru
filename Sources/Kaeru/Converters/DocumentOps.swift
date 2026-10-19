import AppKit

/// Rich text documents via NSAttributedString, which natively reads and writes DOCX, ODT, RTF and HTML.
enum DocumentOps {
    static let targets: [(ext: String, title: String)] = [
        ("docx", "DOCX"), ("pdf", "PDF"), ("md", "Markdown"), ("html", "HTML"),
        ("rtf", "RTF"), ("odt", "ODT"), ("txt", "TXT"),
    ]

    static func convertOps() -> [FileOperation] {
        var list = targets + [(ext: "epub", title: "EPUB")]
        if OfficeApps.hasPages { list.append((ext: "pages", title: "Pages")) }
        return list.map { t in
            .perFile("doc.\(t.ext)", t.title, "doc.text", ext: t.ext) { url, _ in
                let out = Output.file(for: url, ext: t.ext)
                switch t.ext {
                case "epub":
                    try await EPUB.write(title: url.deletingPathExtension().lastPathComponent,
                                         markdown: try await markdown(of: url), to: out)
                case "pages":
                    try await toPages(url, out)
                default:
                    let text = try await load(url)
                    try await MainActor.run { try write(text, to: out) }
                }
                return [out]
            }
        }
    }

    /// Reads any supported document, including EPUB, as attributed text.
    static func load(_ url: URL) async throws -> NSAttributedString {
        if url.pathExtension.lowercased() == "epub" {
            let html = try await EPUB.html(url)
            return try await MainActor.run { try self.html(html) }
        }
        return try await MainActor.run { try read(url) }
    }

    static func markdown(of url: URL) async throws -> String {
        if FileKind.normalizedExt(url.pathExtension) == "md" { return try String(contentsOf: url, encoding: .utf8) }
        let text = try await load(url)
        return await MainActor.run { Markdown.fromAttributed(text) }
    }

    /// Pages opens Word, RTF and plain text directly; anything else goes through a temporary DOCX.
    private static func toPages(_ url: URL, _ out: URL) async throws {
        if ["docx", "doc", "rtf", "txt"].contains(FileKind.normalizedExt(url.pathExtension)) {
            try await OfficeApps.pagesExport(url, out)
            return
        }
        let docx = Output.temp(ext: "docx")
        defer { try? FileManager.default.removeItem(at: docx) }
        let text = try await load(url)
        try await MainActor.run { try write(text, to: docx) }
        try await OfficeApps.pagesExport(docx, out)
    }

    static func toolOps() -> [FileOperation] {
        [FileOperation(id: "doc.count", title: "Word Count", symbol: "number") { urls, _ in
            var words = 0, chars = 0
            for url in urls {
                let text = try await load(url).string
                words += text.split { $0.isWhitespace || $0.isNewline }.count
                chars += text.count
            }
            return OpResult(message: "\(words.formatted()) words · \(chars.formatted()) characters")
        }]
    }

    @MainActor
    static func read(_ url: URL) throws -> NSAttributedString {
        switch FileKind.normalizedExt(url.pathExtension) {
        case "md":
            return try html(Markdown.toHTML(try String(contentsOf: url, encoding: .utf8)))
        case "txt", "srt", "vtt", "csv", "tsv", "json":
            let text = try String(contentsOf: url, encoding: .utf8)
            return NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 12)])
        default:
            return try NSAttributedString(url: url, options: [:], documentAttributes: nil)
        }
    }

    static func html(_ html: String) throws -> NSAttributedString {
        try NSAttributedString(data: Data(html.utf8),
                               options: [.documentType: NSAttributedString.DocumentType.html,
                                         .characterEncoding: String.Encoding.utf8.rawValue],
                               documentAttributes: nil)
    }

    @MainActor
    static func write(_ text: NSAttributedString, to url: URL) throws {
        let range = NSRange(location: 0, length: text.length)
        func data(_ type: NSAttributedString.DocumentType) throws -> Data {
            try text.data(from: range, documentAttributes: [.documentType: type])
        }
        switch url.pathExtension.lowercased() {
        case "docx": try data(.officeOpenXML).write(to: url)
        case "odt": try data(.openDocument).write(to: url)
        case "rtf": try data(.rtf).write(to: url)
        case "doc": try data(.docFormat).write(to: url)
        case "html": try data(.html).write(to: url)
        case "txt": try text.string.write(to: url, atomically: true, encoding: .utf8)
        case "md": try Markdown.fromAttributed(text).write(to: url, atomically: true, encoding: .utf8)
        case "pdf": try renderPDF(text, to: url)
        default: throw fail("Can't write .\(url.pathExtension) documents")
        }
    }

    /// Lays text out on pages with an off-screen text view and prints it straight to a PDF file.
    @MainActor
    static func renderPDF(_ text: NSAttributedString, to url: URL) throws {
        let info = NSPrintInfo(dictionary: [.jobSavingURL: url])
        info.jobDisposition = .save
        info.paperSize = NSPrintInfo.shared.paperSize
        info.topMargin = 54; info.bottomMargin = 54; info.leftMargin = 54; info.rightMargin = 54
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false

        let width = info.paperSize.width - info.leftMargin - info.rightMargin
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 1))
        view.appearance = NSAppearance(named: .aqua)  // keep text black even in Dark Mode
        view.drawsBackground = false
        view.textStorage?.setAttributedString(text)
        if let container = view.textContainer, let layout = view.layoutManager {
            layout.ensureLayout(for: container)
            view.frame.size.height = max(layout.usedRect(for: container).height + 20, 1)
        }
        let op = NSPrintOperation(view: view, printInfo: info)
        op.showsPrintPanel = false
        op.showsProgressPanel = false
        guard op.run() else { throw fail("Couldn't render PDF") }
    }
}
