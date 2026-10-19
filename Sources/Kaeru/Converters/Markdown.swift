import AppKit

/// Minimal Markdown ↔ HTML/attributed-text conversion covering the common block and inline syntax.
enum Markdown {
    static let css = """
    body { font-family: -apple-system, Helvetica, sans-serif; font-size: 12pt; line-height: 1.45; color: #1d1d1f; }
    h1 { font-size: 22pt; } h2 { font-size: 17pt; } h3 { font-size: 14pt; }
    code, pre { font-family: Menlo, monospace; font-size: 10.5pt; background: #f2f2f4; }
    blockquote { color: #555; border-left: 3px solid #ccc; padding-left: 10px; margin-left: 0; }
    table { border-collapse: collapse; } td, th { border: 1px solid #ccc; padding: 4px 8px; }
    """

    static func wrap(_ body: String) -> String {
        "<!doctype html><html><head><meta charset=\"utf-8\"><style>\(css)</style></head><body>\n\(body)\n</body></html>"
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    // MARK: Markdown → HTML

    static func toHTML(_ markdown: String) -> String { wrap(body(markdown)) }

    /// The converted HTML without the document wrapper; also valid XHTML for EPUB.
    static func body(_ markdown: String) -> String {
        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var html: [String] = []
        var paragraph: [String] = []
        var i = 0

        func flush() {
            if !paragraph.isEmpty { html.append("<p>\(inline(paragraph.joined(separator: " ")))</p>") }
            paragraph = []
        }
        func trimmed(_ i: Int) -> String { lines[i].trimmingCharacters(in: .whitespaces) }

        while i < lines.count {
            let t = trimmed(i)
            if t.hasPrefix("```") {
                flush(); i += 1
                var code: [String] = []
                while i < lines.count && !trimmed(i).hasPrefix("```") { code.append(escape(lines[i])); i += 1 }
                html.append("<pre><code>\(code.joined(separator: "\n"))</code></pre>")
                i += 1
            } else if t.isEmpty {
                flush(); i += 1
            } else if let (level, text) = heading(t) {
                flush(); html.append("<h\(level)>\(inline(text))</h\(level)>"); i += 1
            } else if ["---", "***", "___"].contains(t) {
                flush(); html.append("<hr />"); i += 1
            } else if t.hasPrefix(">") {
                flush()
                var quote: [String] = []
                while i < lines.count && trimmed(i).hasPrefix(">") {
                    quote.append(String(trimmed(i).dropFirst()).trimmingCharacters(in: .whitespaces)); i += 1
                }
                html.append("<blockquote>\(inline(quote.joined(separator: " ")))</blockquote>")
            } else if t.hasPrefix("|") {
                flush()
                var rows: [[String]] = []
                while i < lines.count && trimmed(i).hasPrefix("|") {
                    let cells = trimmed(i).trimmingCharacters(in: CharacterSet(charactersIn: "|"))
                        .components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                    if !cells.allSatisfy({ $0.allSatisfy { "-: ".contains($0) } }) { rows.append(cells) }
                    i += 1
                }
                html.append(table(rows))
            } else if let first = listItem(t) {
                flush()
                var items: [String] = []
                while i < lines.count, let item = listItem(trimmed(i)), item.ordered == first.ordered {
                    items.append("<li>\(inline(item.text))</li>"); i += 1
                }
                let tag = first.ordered ? "ol" : "ul"
                html.append("<\(tag)>\(items.joined())</\(tag)>")
            } else {
                paragraph.append(t); i += 1
            }
        }
        flush()
        return html.joined(separator: "\n")
    }

    static func table(_ rows: [[String]]) -> String {
        guard let header = rows.first else { return "" }
        let head = header.map { "<th>\(inline($0))</th>" }.joined()
        let body = rows.dropFirst().map { "<tr>" + $0.map { "<td>\(inline($0))</td>" }.joined() + "</tr>" }.joined()
        return "<table><tr>\(head)</tr>\(body)</table>"
    }

    private static func heading(_ line: String) -> (Int, String)? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
        return (hashes, String(line.dropFirst(hashes + 1)))
    }

    private static func listItem(_ line: String) -> (ordered: Bool, text: String)? {
        for bullet in ["- ", "* ", "+ "] where line.hasPrefix(bullet) {
            var text = String(line.dropFirst(2))
            for box in ["[ ] ", "[x] ", "[X] "] where text.hasPrefix(box) {
                text = (box == "[ ] " ? "☐ " : "☑ ") + text.dropFirst(4)
            }
            return (false, text)
        }
        if let dot = line.firstIndex(where: { $0 == "." || $0 == ")" }), dot > line.startIndex,
           line[..<dot].allSatisfy(\.isNumber), line[line.index(after: dot)...].hasPrefix(" ") {
            return (true, String(line[line.index(dot, offsetBy: 2)...]))
        }
        return nil
    }

    private static let inlineRules: [(String, String)] = [
        ("`([^`]+)`", "<code>$1</code>"),
        ("!\\[([^\\]]*)\\]\\(([^)\\s]+)[^)]*\\)", "<img alt=\"$1\" src=\"$2\" />"),
        ("\\[([^\\]]+)\\]\\(([^)\\s]+)[^)]*\\)", "<a href=\"$2\">$1</a>"),
        ("\\*\\*(.+?)\\*\\*", "<strong>$1</strong>"),
        ("__(.+?)__", "<strong>$1</strong>"),
        ("\\*(.+?)\\*", "<em>$1</em>"),
        ("(?<![\\w])_(.+?)_(?![\\w])", "<em>$1</em>"),
        ("~~(.+?)~~", "<del>$1</del>"),
    ]

    static func inline(_ text: String) -> String {
        var s = escape(text)
        for (pattern, template) in inlineRules {
            s = s.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
        }
        return s
    }

    // MARK: Attributed text → Markdown

    static func fromAttributed(_ text: NSAttributedString) -> String {
        let ns = text.string as NSString
        let base = bodyFontSize(text)
        var blocks: [(text: String, isList: Bool)] = []

        // Word tables arrive as paragraphs tagged with NSTextTableBlocks; collect them into a grid.
        var table: (id: ObjectIdentifier, cells: [[String]])?
        func flushTable() {
            if let t = table { blocks.append((markdownTable(t.cells), false)) }
            table = nil
        }

        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .byParagraphs) { _, range, _, _ in
            let para = text.attributedSubstring(from: range)
            let plain = para.string.trimmingCharacters(in: .whitespaces)
            let style = para.length > 0 ? para.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle : nil
            if let cell = style?.textBlocks.compactMap({ $0 as? NSTextTableBlock }).first {
                let id = ObjectIdentifier(cell.table)
                if table?.id != id { flushTable(); table = (id, []) }
                while table!.cells.count <= cell.startingRow { table!.cells.append([]) }
                while table!.cells[cell.startingRow].count <= cell.startingColumn { table!.cells[cell.startingRow].append("") }
                let existing = table!.cells[cell.startingRow][cell.startingColumn]
                table!.cells[cell.startingRow][cell.startingColumn] = existing.isEmpty ? plain : existing + " " + plain
                return
            }
            guard !plain.isEmpty else { return }
            flushTable()
            let font = para.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
            let size = font?.pointSize ?? base
            let bold = isEntirely(para, trait: .bold)

            if size >= base * 1.6 { blocks.append(("# " + plain, false)); return }
            if size >= base * 1.3 { blocks.append(("## " + plain, false)); return }
            if size >= base * 1.12 && (bold || plain.count <= 80) { blocks.append(("### " + plain, false)); return }
            if size > base * 1.03 && plain.count <= 80 && plain.last != "." { blocks.append(("#### " + plain, false)); return }

            // Lists arrive either as real text lists or, from DOCX and PDF, as literal "•⇥" / "1⇥" markers.
            let bulletMarker = "^\\s*[•◦▪‣⁃–]\\s+", numberMarker = "^\\s*\\d+([.)]\\s+|\\t\\s*|\\s(?=\\S))"
            let hasBullet = plain.range(of: bulletMarker, options: .regularExpression) != nil
            let hasNumber = plain.range(of: numberMarker, options: .regularExpression) != nil
            let textList = style?.textLists.last
            if textList != nil || hasBullet || (hasNumber && plain.contains("\t")) {
                let ordered = textList.map { $0.markerFormat.rawValue.contains("decimal") } ?? !hasBullet
                let body = inlineMarkdown(para)
                    .replacingOccurrences(of: bulletMarker, with: "", options: .regularExpression)
                    .replacingOccurrences(of: numberMarker, with: "", options: .regularExpression)
                blocks.append(((ordered ? "1. " : "- ") + body, true))
                return
            }
            // Text that happens to start with "#" (a "#" column, a hashtag) must not become a heading.
            let line = inlineMarkdown(para)
            blocks.append((line.hasPrefix("#") ? "\\" + line : line, false))
        }

        flushTable()

        var out = ""
        for (i, block) in blocks.enumerated() {
            if i > 0 { out += block.isList && blocks[i - 1].isList ? "\n" : "\n\n" }
            out += block.text
        }
        return out + "\n"
    }

    private static func markdownTable(_ rows: [[String]]) -> String {
        let width = rows.map(\.count).max() ?? 0
        guard width > 0 else { return "" }
        let lines = rows.map { row in
            "| " + (0..<width).map { $0 < row.count ? row[$0].replacingOccurrences(of: "|", with: "\\|") : "" }
                .joined(separator: " | ") + " |"
        }
        return ([lines[0], "|" + String(repeating: " --- |", count: width)] + lines.dropFirst()).joined(separator: "\n")
    }

    private static func bodyFontSize(_ text: NSAttributedString) -> CGFloat {
        var weights: [CGFloat: Int] = [:]
        text.enumerateAttribute(.font, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            if let f = value as? NSFont { weights[f.pointSize.rounded(), default: 0] += range.length }
        }
        // Tables and footnotes in small type can outweigh the body, so take the largest size that is
        // still common (at least 40% of the most used one) rather than simply the most used.
        guard let top = weights.values.max() else { return 12 }
        return weights.filter { Double($0.value) >= Double(top) * 0.4 }.keys.max() ?? 12
    }

    private static func isEntirely(_ text: NSAttributedString, trait: NSFontDescriptor.SymbolicTraits) -> Bool {
        var all = true
        text.enumerateAttribute(.font, in: NSRange(location: 0, length: text.length)) { value, range, stop in
            let chunk = (text.string as NSString).substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
            if !chunk.isEmpty, (value as? NSFont)?.fontDescriptor.symbolicTraits.contains(trait) != true {
                all = false; stop.pointee = true
            }
        }
        return all
    }

    private static func inlineMarkdown(_ para: NSAttributedString) -> String {
        var out = ""
        para.enumerateAttributes(in: NSRange(location: 0, length: para.length)) { attrs, range, _ in
            var run = (para.string as NSString).substring(with: range).replacingOccurrences(of: "\n", with: "")
            let core = run.trimmingCharacters(in: .whitespaces)
            guard !core.isEmpty else { out += run; return }
            let traits = (attrs[.font] as? NSFont)?.fontDescriptor.symbolicTraits ?? []
            var wrapped = core
            if traits.contains(.bold) { wrapped = "**\(wrapped)**" }
            if traits.contains(.italic) { wrapped = "*\(wrapped)*" }
            if let link = attrs[.link] {
                wrapped = "[\(wrapped)](\((link as? URL)?.absoluteString ?? "\(link)"))"
            }
            run = run.replacingOccurrences(of: core, with: wrapped)
            out += run
        }
        return out.trimmingCharacters(in: .whitespaces)
    }
}
