import Foundation

/// Just enough of the Office Open XML spreadsheet format to read the first sheet and write one sheet.
enum XLSX {
    static func write(_ rows: [[String]], to url: URL) async throws {
        let dir = try Output.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let ns = "http://schemas.openxmlformats.org"
        let header = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
        var sheet = header + "<worksheet xmlns=\"\(ns)/spreadsheetml/2006/main\">"
        sheet += "<sheetViews><sheetView workbookViewId=\"0\"><pane ySplit=\"1\" topLeftCell=\"A2\" activePane=\"bottomLeft\" state=\"frozen\"/></sheetView></sheetViews><sheetData>"
        for (r, row) in rows.enumerated() {
            sheet += "<row r=\"\(r + 1)\">"
            for (c, value) in row.enumerated() where !value.isEmpty {
                let ref = column(c) + "\(r + 1)"
                let style = r == 0 ? " s=\"1\"" : ""
                if r > 0, isNumber(value) {
                    sheet += "<c r=\"\(ref)\"><v>\(value)</v></c>"
                } else {
                    sheet += "<c r=\"\(ref)\" t=\"inlineStr\"\(style)><is><t xml:space=\"preserve\">\(escape(value))</t></is></c>"
                }
            }
            sheet += "</row>"
        }
        sheet += "</sheetData></worksheet>"

        let files: [String: String] = [
            "[Content_Types].xml": header + """
            <Types xmlns="\(ns)/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>
            """,
            "_rels/.rels": header + """
            <Relationships xmlns="\(ns)/package/2006/relationships"><Relationship Id="rId1" Type="\(ns)/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>
            """,
            "xl/workbook.xml": header + """
            <workbook xmlns="\(ns)/spreadsheetml/2006/main" xmlns:r="\(ns)/officeDocument/2006/relationships"><sheets><sheet name="Sheet1" sheetId="1" r:id="rId1"/></sheets></workbook>
            """,
            "xl/_rels/workbook.xml.rels": header + """
            <Relationships xmlns="\(ns)/package/2006/relationships"><Relationship Id="rId1" Type="\(ns)/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="\(ns)/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>
            """,
            "xl/styles.xml": header + """
            <styleSheet xmlns="\(ns)/spreadsheetml/2006/main"><fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts><fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills><borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/></cellXfs></styleSheet>
            """,
            "xl/worksheets/sheet1.xml": sheet,
        ]
        for (path, content) in files {
            let file = dir.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.write(to: file, atomically: true, encoding: .utf8)
        }
        try await Shell.run("/usr/bin/zip", ["-X", "-r", "-q", url.path, "[Content_Types].xml", "_rels", "xl"], cwd: dir)
    }

    static func read(_ url: URL) async throws -> [[String]] {
        let unzip = "/usr/bin/unzip"
        let entries = try await Shell.run(unzip, ["-Z1", url.path]).split(separator: "\n").map(String.init)
        guard let sheetPath = entries.filter({ $0.hasPrefix("xl/worksheets/sheet") && $0.hasSuffix(".xml") })
            .sorted(by: { $0.localizedStandardCompare($1) == .orderedAscending }).first
        else { throw fail("\(url.lastPathComponent) has no worksheets") }

        var shared: [String] = []
        if entries.contains("xl/sharedStrings.xml") {
            let xml = try await Shell.run(unzip, ["-p", url.path, "xl/sharedStrings.xml"])
            let parser = SharedStringsParser()
            parser.parse(Data(xml.utf8))
            shared = parser.strings
        }
        let parser = SheetParser(shared: shared)
        parser.parse(Data(try await Shell.run(unzip, ["-p", url.path, sheetPath]).utf8))
        return parser.rows
    }

    static func column(_ index: Int) -> String {
        var n = index + 1, s = ""
        while n > 0 { let r = (n - 1) % 26; s = String(UnicodeScalar(65 + r)!) + s; n = (n - 1) / 26 }
        return s
    }

    static func columnIndex(_ ref: String) -> Int {
        ref.prefix { $0.isLetter }.uppercased().unicodeScalars.reduce(0) { $0 * 26 + Int($1.value) - 64 } - 1
    }

    /// Plain decimals only; "007" or "1e5" stay text so nothing is silently reformatted.
    static func isNumber(_ s: String) -> Bool {
        s.range(of: "^-?(0|[1-9]\\d{0,14})(\\.\\d+)?$", options: .regularExpression) != nil
    }

    private static func escape(_ s: String) -> String {
        let cleaned = String(s.unicodeScalars.filter { $0.value >= 0x20 || $0 == "\t" || $0 == "\n" || $0 == "\r" })
        return cleaned.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

private final class SharedStringsParser: NSObject, XMLParserDelegate {
    var strings: [String] = []
    private var current = "", inText = false

    func parse(_ data: Data) {
        let p = XMLParser(data: data); p.delegate = self; p.parse()
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        if name == "si" { current = "" }
        if name == "t" { inText = true }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { if inText { current += string } }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if name == "t" { inText = false }
        if name == "si" { strings.append(current) }
    }
}

private final class SheetParser: NSObject, XMLParserDelegate {
    var rows: [[String]] = []
    private let shared: [String]
    private var row: [Int: String] = [:]
    private var cellRef = "", cellType = "", value = "", capturing = false

    init(shared: [String]) { self.shared = shared }

    func parse(_ data: Data) {
        let p = XMLParser(data: data); p.delegate = self; p.parse()
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        switch name {
        case "row":
            row = [:]
            if let r = attributes["r"].flatMap(Int.init) { while rows.count < r - 1 { rows.append([]) } }
        case "c": cellRef = attributes["r"] ?? ""; cellType = attributes["t"] ?? ""; value = ""
        case "v", "t": capturing = true
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { if capturing { value += string } }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        switch name {
        case "v", "t": capturing = false
        case "c":
            var text = value
            if cellType == "s", let i = Int(value), i < shared.count { text = shared[i] }
            if cellType == "b" { text = value == "1" ? "TRUE" : "FALSE" }
            let col = cellRef.isEmpty ? row.count : XLSX.columnIndex(cellRef)
            row[col] = text
        case "row":
            let width = (row.keys.max() ?? -1) + 1
            rows.append((0..<width).map { row[$0] ?? "" })
        default: break
        }
    }
}
