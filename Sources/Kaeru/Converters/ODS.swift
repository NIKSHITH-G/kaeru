import Foundation

/// OpenDocument spreadsheets: first sheet in, one sheet out.
enum ODS {
    static func write(_ rows: [[String]], to url: URL) async throws {
        var table = ""
        for row in rows {
            table += "<table:table-row>"
            for cell in row {
                let text = "<text:p>\(ZipPackage.xmlEscape(cell))</text:p>"
                if XLSX.isNumber(cell) {
                    table += "<table:table-cell office:value-type=\"float\" office:value=\"\(cell)\">\(text)</table:table-cell>"
                } else if cell.isEmpty {
                    table += "<table:table-cell/>"
                } else {
                    table += "<table:table-cell office:value-type=\"string\">\(text)</table:table-cell>"
                }
            }
            table += "</table:table-row>"
        }
        let content = """
        <?xml version="1.0" encoding="UTF-8"?>
        <office:document-content xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" \
        xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0" \
        xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0" office:version="1.2">\
        <office:body><office:spreadsheet><table:table table:name="Sheet1">\(table)</table:table></office:spreadsheet></office:body>\
        </office:document-content>
        """
        let manifest = """
        <?xml version="1.0" encoding="UTF-8"?>
        <manifest:manifest xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0" manifest:version="1.2">
         <manifest:file-entry manifest:full-path="/" manifest:version="1.2" manifest:media-type="application/vnd.oasis.opendocument.spreadsheet"/>
         <manifest:file-entry manifest:full-path="content.xml" manifest:media-type="text/xml"/>
        </manifest:manifest>
        """
        try await ZipPackage.write(["content.xml": content, "META-INF/manifest.xml": manifest], to: url,
                                   mimetype: "application/vnd.oasis.opendocument.spreadsheet")
    }

    static func read(_ url: URL) async throws -> [[String]] {
        let parser = ODSParser()
        parser.parse(Data(try await ZipPackage.read(url, entry: "content.xml").utf8))
        return parser.rows
    }
}

private final class ODSParser: NSObject, XMLParserDelegate {
    var rows: [[String]] = []
    private var row: [String] = []
    private var rowRepeat = 1, cellRepeat = 1
    private var cellText = "", paragraphs: [String] = []
    private var cellValue: String?
    private var inParagraph = false, tableDepth = 0, done = false
    /// Empty rows are held back so the millions of blank rows ODS files often declare aren't materialised.
    private var pendingEmptyRows = 0

    func parse(_ data: Data) {
        let p = XMLParser(data: data); p.delegate = self; p.parse()
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        guard !done else { return }
        switch name {
        case "table:table": tableDepth += 1
        case "table:table-row":
            row = []
            rowRepeat = Int(attributes["table:number-rows-repeated"] ?? "") ?? 1
        case "table:table-cell", "table:covered-table-cell":
            cellRepeat = Int(attributes["table:number-columns-repeated"] ?? "") ?? 1
            paragraphs = []
            let type = attributes["office:value-type"]
            cellValue = type == "float" || type == "percentage" || type == "currency" ? attributes["office:value"]
                : type == "boolean" ? attributes["office:boolean-value"]?.uppercased()
                : type == "date" ? attributes["office:date-value"] : nil
        case "text:p": inParagraph = true; cellText = ""
        case "text:s": if inParagraph { cellText += String(repeating: " ", count: Int(attributes["text:c"] ?? "") ?? 1) }
        case "text:tab": if inParagraph { cellText += "\t" }
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { if inParagraph { cellText += string } }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        guard !done else { return }
        switch name {
        case "text:p": inParagraph = false; paragraphs.append(cellText)
        case "table:table-cell", "table:covered-table-cell":
            let value = cellValue ?? paragraphs.joined(separator: "\n")
            row += Array(repeating: value, count: value.isEmpty ? min(cellRepeat, 1024) : min(cellRepeat, 256))
        case "table:table-row":
            while row.last == "" { row.removeLast() }
            if row.isEmpty {
                pendingEmptyRows += rowRepeat
            } else {
                rows += Array(repeating: [], count: min(pendingEmptyRows, 10_000))
                pendingEmptyRows = 0
                rows += Array(repeating: row, count: min(rowRepeat, 10_000))
            }
        case "table:table":
            tableDepth -= 1
            if tableDepth == 0 { done = true }  // first sheet only
        default: break
        }
    }
}
