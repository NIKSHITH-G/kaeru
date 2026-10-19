import Foundation

/// EPUB 3 writing (from Markdown, one chapter per top-level heading) and reading (spine → HTML).
enum EPUB {
    static func write(title: String, markdown: String, to out: URL) async throws {
        let chapters = split(markdown, fallbackTitle: title)
        var files: [String: String] = [
            "META-INF/container.xml": """
            <?xml version="1.0" encoding="UTF-8"?>
            <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
              <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
            </container>
            """,
            "OEBPS/style.css": """
            body { font-family: serif; line-height: 1.5; margin: 0 5%; }
            h1, h2, h3 { font-family: sans-serif; line-height: 1.2; }
            pre, code { font-family: monospace; font-size: 0.9em; }
            pre { white-space: pre-wrap; background: #f4f4f4; padding: 0.6em; }
            blockquote { margin-left: 1em; padding-left: 0.8em; border-left: 3px solid #ccc; color: #555; }
            table { border-collapse: collapse; } td, th { border: 1px solid #aaa; padding: 0.2em 0.5em; }
            img { max-width: 100%; }
            """,
        ]
        var manifest = "", spine = "", toc = ""
        for (i, chapter) in chapters.enumerated() {
            let name = "chapter\(i + 1).xhtml"
            files["OEBPS/\(name)"] = xhtml(title: chapter.title, body: Markdown.body(chapter.markdown))
            manifest += "<item id=\"c\(i + 1)\" href=\"\(name)\" media-type=\"application/xhtml+xml\"/>\n"
            spine += "<itemref idref=\"c\(i + 1)\"/>\n"
            toc += "<li><a href=\"\(name)\">\(ZipPackage.xmlEscape(chapter.title))</a></li>\n"
        }
        files["OEBPS/nav.xhtml"] = xhtml(title: "Contents",
                                         body: "<nav epub:type=\"toc\" id=\"toc\"><h1>Contents</h1><ol>\n\(toc)</ol></nav>")
        let modified = ISO8601DateFormatter().string(from: Date()).prefix(19) + "Z"
        files["OEBPS/content.opf"] = """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:identifier id="bookid">urn:uuid:\(UUID().uuidString.lowercased())</dc:identifier>
            <dc:title>\(ZipPackage.xmlEscape(title))</dc:title>
            <dc:language>en</dc:language>
            <meta property="dcterms:modified">\(modified)</meta>
          </metadata>
          <manifest>
            <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
            <item id="css" href="style.css" media-type="text/css"/>
        \(manifest)  </manifest>
          <spine>
        \(spine)  </spine>
        </package>
        """
        try await ZipPackage.write(files, to: out, mimetype: "application/epub+zip")
    }

    private static func xhtml(title: String, body: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE html>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="en">
        <head><meta charset="utf-8"/><title>\(ZipPackage.xmlEscape(title))</title><link rel="stylesheet" type="text/css" href="style.css"/></head>
        <body>
        \(body)
        </body>
        </html>
        """
    }

    /// Splits at each `# Heading`, so readers get a usable table of contents.
    private static func split(_ markdown: String, fallbackTitle: String) -> [(title: String, markdown: String)] {
        var chapters: [(title: String, markdown: String)] = []
        var current: [String] = [], title = fallbackTitle
        for line in markdown.components(separatedBy: "\n") {
            if line.hasPrefix("# ") {
                if current.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                    chapters.append((title, current.joined(separator: "\n")))
                }
                current = []
                title = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            }
            current.append(line)
        }
        chapters.append((title, current.joined(separator: "\n")))
        return chapters
    }

    // MARK: Reading

    /// Joins the book's chapters, in reading order, into one HTML document with absolute image paths.
    /// The extracted files stay in a temp folder so images still resolve while the HTML is imported.
    static func html(_ url: URL) async throws -> String {
        let dir = try Output.tempDirectory()
        try await Shell.run("/usr/bin/ditto", ["-x", "-k", url.path, dir.path])
        let container = try String(contentsOf: dir.appendingPathComponent("META-INF/container.xml"), encoding: .utf8)
        guard let opfPath = firstMatch("full-path=\"([^\"]+)\"", in: container) else { throw fail("Not a valid EPUB") }
        let opfURL = dir.appendingPathComponent(opfPath)
        let parser = OPFParser()
        parser.parse(try Data(contentsOf: opfURL))

        var body = ""
        for idref in parser.spine {
            guard let href = parser.manifest[idref]?.removingPercentEncoding else { continue }
            let chapterURL = opfURL.deletingLastPathComponent().appendingPathComponent(href)
            guard var chapter = try? String(contentsOf: chapterURL, encoding: .utf8) else { continue }
            if let start = chapter.range(of: "<body[^>]*>", options: .regularExpression),
               let end = chapter.range(of: "</body>", options: .backwards) {
                chapter = String(chapter[start.upperBound..<end.lowerBound])
            }
            // Make image references absolute so they survive being merged into one document.
            let base = chapterURL.deletingLastPathComponent()
            chapter = replace("(src|xlink:href)=\"(?!https?:|data:|/)([^\"]+)\"", in: chapter) { groups in
                "\(groups[1])=\"\(base.appendingPathComponent(groups[2]).absoluteString)\""
            }
            body += chapter + "\n"
        }
        guard !body.isEmpty else { throw fail("This EPUB has no readable chapters") }
        return Markdown.wrap(body)
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }

    private static func replace(_ pattern: String, in text: String, _ transform: ([String]) -> String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return text }
        var result = "", last = text.startIndex
        for m in re.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let whole = Range(m.range, in: text) else { continue }
            let groups = (0..<m.numberOfRanges).map { i in Range(m.range(at: i), in: text).map { String(text[$0]) } ?? "" }
            result += text[last..<whole.lowerBound] + transform(groups)
            last = whole.upperBound
        }
        return result + text[last...]
    }
}

private final class OPFParser: NSObject, XMLParserDelegate {
    var manifest: [String: String] = [:]
    var spine: [String] = []

    func parse(_ data: Data) {
        let p = XMLParser(data: data); p.delegate = self; p.parse()
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        switch name.split(separator: ":").last {
        case "item": if let id = attributes["id"], let href = attributes["href"] { manifest[id] = href }
        case "itemref": if let id = attributes["idref"] { spine.append(id) }
        default: break
        }
    }
}
