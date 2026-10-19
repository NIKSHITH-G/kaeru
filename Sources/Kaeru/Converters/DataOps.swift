import Foundation

/// Tables (CSV, TSV, XLSX, JSON), structured data (JSON, plist) and subtitles.
enum DataOps {
    // MARK: Tables

    static let tableTargets: [(ext: String, title: String)] = [
        ("xlsx", "XLSX"), ("ods", "ODS"), ("csv", "CSV"), ("tsv", "TSV"), ("json", "JSON"), ("html", "HTML"), ("md", "Markdown"), ("pdf", "PDF"),
    ]

    static func tableConvertOps() -> [FileOperation] {
        tableTargets.map { t in
            t.ext == "pdf" ? tablePDFOp() : .perFile("table.\(t.ext)", t.title, "tablecells", ext: t.ext) { url, _ in
                let out = Output.file(for: url, ext: t.ext)
                try await writeTable(try await readTable(url), to: out)
                return [out]
            }
        }
    }

    /// Spreadsheets → PDF go through Excel when it's installed, so the sheet looks exactly as it
    /// does there. Otherwise, or if Excel can't do it, Kaeru lays the table out itself and says so.
    private static func tablePDFOp() -> FileOperation {
        FileOperation(id: "table.pdf", title: "PDF", symbol: "tablecells", targetExt: "pdf") { inputs, progress in
            var result = OpResult()
            for (i, url) in inputs.enumerated() {
                let out = Output.file(for: url, ext: "pdf")
                var done = false
                if OfficeApps.hasExcel && ["xlsx", "xls", "xlsm", "ods", "csv"].contains(FileKind.normalizedExt(url.pathExtension)) {
                    do {
                        try await OfficeApps.spreadsheetToPDF(url, out)
                        done = true
                    } catch {
                        NSLog("Kaeru: Excel export failed, using the built-in renderer: \(error.localizedDescription)")
                        result.message = "Made without Excel, so colours and column widths may differ. Allow Kaeru to control Microsoft Excel in System Settings → Privacy & Security → Automation"
                    }
                }
                if !done { try await writeTable(try await readTable(url), to: out) }
                result.outputs.append(out)
                progress(Double(i + 1) / Double(inputs.count))
            }
            return result
        }
    }

    static func readTable(_ url: URL) async throws -> [[String]] {
        switch FileKind.normalizedExt(url.pathExtension) {
        case "xlsx": return try await XLSX.read(url)
        case "ods": return try await ODS.read(url)
        case "xls": return try await QuickLookOffice.table(url)
        case "json": return try jsonTable(Data(contentsOf: url))
        case "tsv": return parseDelimited(try String(contentsOf: url, encoding: .utf8), separator: "\t")
        default:
            let text = try readText(url)
            return parseDelimited(text, separator: sniffSeparator(text))
        }
    }

    static func writeTable(_ rows: [[String]], to url: URL) async throws {
        switch url.pathExtension.lowercased() {
        case "xlsx": try await XLSX.write(rows, to: url)
        case "ods": try await ODS.write(rows, to: url)
        case "csv": try delimited(rows, separator: ",").write(to: url, atomically: true, encoding: .utf8)
        case "tsv": try delimited(rows, separator: "\t").write(to: url, atomically: true, encoding: .utf8)
        case "json":
            // Written by hand so keys keep the spreadsheet's column order.
            guard let header = rows.first else { throw fail("Table is empty") }
            func quote(_ s: String) -> String {
                let data = try? JSONSerialization.data(withJSONObject: s, options: [.fragmentsAllowed, .withoutEscapingSlashes])
                return data.map { String(decoding: $0, as: UTF8.self) } ?? "\"\""
            }
            func value(_ s: String) -> String { XLSX.isNumber(s) ? s : quote(s) }
            let objects = rows.dropFirst().map { row in
                "  {\n" + header.enumerated().map { i, key in
                    "    \(quote(key)): \(value(i < row.count ? row[i] : ""))"
                }.joined(separator: ",\n") + "\n  }"
            }
            try ("[\n" + objects.joined(separator: ",\n") + "\n]\n").write(to: url, atomically: true, encoding: .utf8)
        case "md":
            guard let header = rows.first else { throw fail("Table is empty") }
            let width = header.count
            func line(_ r: [String]) -> String {
                "| " + (0..<width).map { $0 < r.count ? r[$0].replacingOccurrences(of: "|", with: "\\|") : "" }
                    .joined(separator: " | ") + " |"
            }
            let md = ([line(header), "|" + String(repeating: " --- |", count: width)] + rows.dropFirst().map(line))
                .joined(separator: "\n")
            try md.write(to: url, atomically: true, encoding: .utf8)
        case "html":
            try Markdown.wrap(Markdown.table(rows)).write(to: url, atomically: true, encoding: .utf8)
        case "pdf":
            // Wide tables go landscape; WebKit sizes columns to their content and shrinks to fit.
            let css = Markdown.css + """
            body { font-size: 8.5pt; line-height: 1.3; margin: 0; -webkit-print-color-adjust: exact; print-color-adjust: exact; }
            table { width: 100%; } th { background: #1f3864; color: white; text-align: left; }
            td, th { padding: 3px 5px; vertical-align: top; overflow-wrap: break-word; word-break: normal; hyphens: none; }
            tr:nth-child(even) td { background: #f4f6fa; } tr { break-inside: avoid; }
            thead { display: table-header-group; }
            """
            let html = "<!doctype html><html><head><meta charset=\"utf-8\"><style>\(css)</style></head><body>\(Markdown.table(rows))</body></html>"
            let wide = (rows.map(\.count).max() ?? 0) > 5
            try await WebPDF.render(html: html, to: url, landscape: wide)
        default: throw fail("Can't write .\(url.pathExtension) tables")
        }
    }

    /// Reads text as UTF-8, falling back to Latin-1 for spreadsheets exported by older tools.
    static func readText(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }

    static func sniffSeparator(_ text: String) -> Character {
        let firstLine = text.prefix { $0 != "\n" }
        let counts: [(Character, Int)] = [",", ";", "\t", "|"].map { c in (c, firstLine.filter { $0 == c }.count) }
        return counts.max { $0.1 < $1.1 }.flatMap { $0.1 > 0 ? $0.0 : nil } ?? ","
    }

    /// RFC 4180 parsing: quoted fields, escaped quotes, embedded newlines.
    static func parseDelimited(_ text: String, separator: Character) -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], field = ""
        var inQuotes = false
        var chars = text.makeIterator()
        var pending: Character? = nil
        while let c = pending ?? chars.next() {
            pending = nil
            if inQuotes {
                if c == "\"" {
                    if let next = chars.next() {
                        if next == "\"" { field.append("\"") } else { inQuotes = false; pending = next }
                    } else { inQuotes = false }
                } else { field.append(c) }
            } else if c == "\"" && field.isEmpty {
                inQuotes = true
            } else if c == separator {
                row.append(field); field = ""
            } else if c == "\n" || c == "\r\n" || c == "\r" {
                row.append(field); rows.append(row); row = []; field = ""
            } else {
                field.append(c)
            }
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        if rows.first?.first?.hasPrefix("\u{FEFF}") == true { rows[0][0].removeFirst() }
        return rows
    }

    static func delimited(_ rows: [[String]], separator: String) -> String {
        rows.map { row in
            row.map { f in
                f.contains(separator) || f.contains("\"") || f.contains("\n")
                    ? "\"" + f.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : f
            }.joined(separator: separator)
        }.joined(separator: "\n") + "\n"
    }

    /// Accepts an array of objects (keys become the header) or an array of arrays.
    static func jsonTable(_ data: Data) throws -> [[String]] {
        let json = try JSONSerialization.jsonObject(with: data)
        let array = (json as? [Any]) ?? (json as? [String: Any]).flatMap { obj in obj.values.first { $0 is [Any] } as? [Any] }
        guard let array else { throw fail("JSON isn't a list of rows") }
        if let objects = array as? [[String: Any]] {
            var header: [String] = []
            for obj in objects { for key in obj.keys.sorted() where !header.contains(key) { header.append(key) } }
            return [header] + objects.map { obj in header.map { cell(obj[$0]) } }
        }
        return array.map { ($0 as? [Any])?.map(cell) ?? [cell($0)] }
    }

    private static func cell(_ value: Any?) -> String {
        switch value {
        case nil, is NSNull: return ""
        case let s as String: return s
        case let n as NSNumber: return n.stringValue
        case let v?:
            let data = try? JSONSerialization.data(withJSONObject: v, options: [.fragmentsAllowed, .sortedKeys, .withoutEscapingSlashes])
            return data.map { String(decoding: $0, as: UTF8.self) } ?? "\(v)"
        }
    }

    // MARK: JSON & plist

    static func jsonConvertOps() -> [FileOperation] {
        tableTargets.filter { $0.ext != "json" }.map { t in
            .perFile("table.\(t.ext)", t.title, "tablecells", ext: t.ext) { url, _ in
                let out = Output.file(for: url, ext: t.ext)
                try await writeTable(try jsonTable(Data(contentsOf: url)), to: out)
                return [out]
            }
        } + [
            .perFile("json.plist", "PLIST", "list.bullet.indent", ext: "plist") { url, _ in
                let obj = replacingNulls(try JSONSerialization.jsonObject(with: Data(contentsOf: url)))
                let out = Output.file(for: url, ext: "plist")
                try PropertyListSerialization.data(fromPropertyList: obj, format: .xml, options: 0).write(to: out)
                return [out]
            },
        ]
    }

    static func plistConvertOps() -> [FileOperation] {
        [.perFile("plist.json", "JSON", "curlybraces", ext: "json") { url, _ in
            let obj = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil)
            let out = Output.file(for: url, ext: "json")
            try JSONSerialization.data(withJSONObject: jsonSafe(obj), options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]).write(to: out)
            return [out]
        }]
    }

    static func jsonToolOps() -> [FileOperation] {
        [
            .perFile("json.pretty", "Pretty Print", "text.alignleft") { url, _ in
                let text = try validJSON(url)
                let out = Output.file(for: url, ext: "json", suffix: "pretty")
                try reformatJSON(text, pretty: true).write(to: out, atomically: true, encoding: .utf8)
                return [out]
            },
            .shrinking("json.minify", "Minify", "arrow.down.right.and.arrow.up.left") { url, _ in
                let text = try validJSON(url)
                let out = Output.file(for: url, ext: "json", suffix: "min")
                try reformatJSON(text, pretty: false).write(to: out, atomically: true, encoding: .utf8)
                return [out]
            },
        ]
    }

    private static func validJSON(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        do { _ = try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) } catch {
            throw fail("\(url.lastPathComponent) isn't valid JSON: \((error as NSError).userInfo[NSDebugDescriptionErrorKey] ?? "")")
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// Re-indents JSON text without parsing it into dictionaries, so key order is preserved.
    static func reformatJSON(_ text: String, pretty: Bool) -> String {
        var out = "", depth = 0, inString = false, escaped = false
        func newline() { if pretty { out += "\n" + String(repeating: "  ", count: depth) } }
        for c in text {
            if inString {
                out.append(c)
                if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { inString = false }
                continue
            }
            switch c {
            case "\"": inString = true; out.append(c)
            case "{", "[": out.append(c); depth += 1; newline()
            case "}", "]":
                depth -= 1
                if let last = out.last(where: { !$0.isWhitespace }), last == "{" || last == "[" {
                    while out.last?.isWhitespace == true { out.removeLast() }
                } else { newline() }
                out.append(c)
            case ",": out.append(c); newline()
            case ":": out += pretty ? ": " : ":"
            case _ where c.isWhitespace: continue
            default: out.append(c)
            }
        }
        return out + (pretty ? "\n" : "")
    }

    private static func replacingNulls(_ obj: Any) -> Any {
        switch obj {
        case let d as [String: Any]: return d.compactMapValues { $0 is NSNull ? nil : replacingNulls($0) }
        case let a as [Any]: return a.map { $0 is NSNull ? "" : replacingNulls($0) }
        default: return obj
        }
    }

    private static func jsonSafe(_ obj: Any) -> Any {
        switch obj {
        case let d as [String: Any]: return d.mapValues(jsonSafe)
        case let a as [Any]: return a.map(jsonSafe)
        case let date as Date: return ISO8601DateFormatter().string(from: date)
        case let data as Data: return data.base64EncodedString()
        default: return obj
        }
    }

    // MARK: Subtitles

    static func subtitleConvertOps() -> [FileOperation] {
        [(ext: "srt", title: "SRT"), (ext: "vtt", title: "VTT"), (ext: "txt", title: "TXT")].map { t in
            .perFile("sub.\(t.ext)", t.title, "captions.bubble", ext: t.ext) { url, _ in
                let cues = parseSubtitles(try readText(url))
                let out = Output.file(for: url, ext: t.ext)
                try formatSubtitles(cues, as: t.ext).write(to: out, atomically: true, encoding: .utf8)
                return [out]
            }
        }
    }

    typealias Cue = (start: String, end: String, text: String)

    static func parseSubtitles(_ text: String) -> [Cue] {
        let blocks = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n\n")
        return blocks.compactMap { block in
            let lines = block.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            guard let timing = lines.firstIndex(where: { $0.contains("-->") }) else { return nil }
            let parts = lines[timing].components(separatedBy: "-->").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { return nil }
            let end = parts[1].split(separator: " ").first.map(String.init) ?? parts[1]  // drop VTT cue settings
            return (normalizeTime(parts[0]), normalizeTime(end), lines[(timing + 1)...].joined(separator: "\n"))
        }
    }

    /// "1:02.5" / "00:01:02,500" → "00:01:02.500"
    private static func normalizeTime(_ t: String) -> String {
        let s = t.replacingOccurrences(of: ",", with: ".")
        var parts = s.split(separator: ":").map(String.init)
        while parts.count < 3 { parts.insert("00", at: 0) }
        let secs = parts[2].split(separator: ".")
        let ms = secs.count > 1 ? String(secs[1].prefix(3)).padding(toLength: 3, withPad: "0", startingAt: 0) : "000"
        return String(format: "%02d:%02d:%02d.%@", Int(parts[0]) ?? 0, Int(parts[1]) ?? 0, Int(secs[0]) ?? 0, ms)
    }

    static func formatSubtitles(_ cues: [Cue], as ext: String) -> String {
        switch ext {
        case "vtt":
            return "WEBVTT\n\n" + cues.map { "\($0.start) --> \($0.end)\n\($0.text)" }.joined(separator: "\n\n") + "\n"
        case "srt":
            return cues.enumerated().map { i, c in
                "\(i + 1)\n\(c.start.replacingOccurrences(of: ".", with: ",")) --> \(c.end.replacingOccurrences(of: ".", with: ","))\n\(c.text)"
            }.joined(separator: "\n\n") + "\n"
        default:
            var lines: [String] = []
            for cue in cues {
                let text = cue.text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                if lines.last != text { lines.append(text) }
            }
            return lines.joined(separator: "\n") + "\n"
        }
    }
}
