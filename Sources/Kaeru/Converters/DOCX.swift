import AppKit

/// Writes styled text as a Word document. The system's own DOCX export flattens tables into loose
/// paragraphs, so Kaeru writes the parts itself: paragraphs and runs with their formatting, real
/// heading styles, links, bullet lists, tables with cell shading, and embedded pictures.
enum DOCX {
    static func write(_ text: NSAttributedString, to url: URL) async throws {
        let files = await MainActor.run { Builder(text).package() }
        try await ZipPackage.write(files, to: url)
    }

    /// The main document part on its own, for the self-test.
    @MainActor
    static func documentXML(_ text: NSAttributedString) -> String {
        String(decoding: Builder(text).package()["word/document.xml"] ?? Data(), as: UTF8.self)
    }

    @MainActor
    private final class Builder {
        let text: NSAttributedString
        let base: CGFloat
        var links: [String] = []
        var images: [Data] = []
        var landscape = false

        init(_ text: NSAttributedString) {
            self.text = text
            var weights: [CGFloat: Int] = [:]
            text.enumerateAttribute(.font, in: NSRange(location: 0, length: text.length)) { value, range, _ in
                if let f = value as? NSFont { weights[f.pointSize.rounded(), default: 0] += range.length }
            }
            let top = weights.values.max() ?? 0
            base = weights.filter { Double($0.value) >= Double(top) * 0.4 }.keys.max() ?? 12
        }

        func package() -> [String: Data] {
            let body = bodyXML()
            let w = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
            let r = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
            let header = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
            var rels = "<Relationship Id=\"rIdStyles\" Type=\"\(r)/styles\" Target=\"styles.xml\"/>"
            for (i, link) in links.enumerated() {
                rels += "<Relationship Id=\"rIdLink\(i)\" Type=\"\(r)/hyperlink\" Target=\"\(esc(link))\" TargetMode=\"External\"/>"
            }
            for i in images.indices {
                rels += "<Relationship Id=\"rIdImg\(i)\" Type=\"\(r)/image\" Target=\"media/image\(i + 1).png\"/>"
            }
            var files: [String: Data] = [
                "[Content_Types].xml": Data((header + """
                <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Default Extension="png" ContentType="image/png"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/></Types>
                """).utf8),
                "_rels/.rels": Data((header + """
                <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="\(r)/officeDocument" Target="word/document.xml"/></Relationships>
                """).utf8),
                "word/_rels/document.xml.rels": Data((header + "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">\(rels)</Relationships>").utf8),
                "word/styles.xml": Data((header + styles(w)).utf8),
                "word/document.xml": Data((header + """
                <w:document xmlns:w="\(w)" xmlns:r="\(r)" xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"><w:body>\(body)<w:sectPr>\(landscape ? "<w:pgSz w:w=\"16838\" w:h=\"11906\" w:orient=\"landscape\"/>" : "<w:pgSz w:w=\"11906\" w:h=\"16838\"/>")<w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="708" w:footer="708" w:gutter="0"/></w:sectPr></w:body></w:document>
                """).utf8),
            ]
            for (i, data) in images.enumerated() { files["word/media/image\(i + 1).png"] = data }
            return files
        }

        private func styles(_ w: String) -> String {
            func heading(_ level: Int, _ size: Int) -> String {
                "<w:style w:type=\"paragraph\" w:styleId=\"Heading\(level)\"><w:name w:val=\"heading \(level)\"/><w:basedOn w:val=\"Normal\"/><w:next w:val=\"Normal\"/><w:qFormat/><w:pPr><w:keepNext/><w:spacing w:before=\"240\" w:after=\"80\"/><w:outlineLvl w:val=\"\(level - 1)\"/></w:pPr><w:rPr><w:b/><w:sz w:val=\"\(size)\"/></w:rPr></w:style>"
            }
            return "<w:styles xmlns:w=\"\(w)\"><w:docDefaults><w:rPrDefault><w:rPr><w:sz w:val=\"\(Int(base * 2))\"/></w:rPr></w:rPrDefault><w:pPrDefault><w:pPr><w:spacing w:after=\"120\"/></w:pPr></w:pPrDefault></w:docDefaults><w:style w:type=\"paragraph\" w:default=\"1\" w:styleId=\"Normal\"><w:name w:val=\"Normal\"/><w:qFormat/></w:style>"
                + heading(1, 32) + heading(2, 28) + heading(3, 24)
                + "<w:style w:type=\"table\" w:styleId=\"Grid\"><w:name w:val=\"Table Grid\"/><w:tblPr><w:tblBorders><w:top w:val=\"single\" w:sz=\"4\" w:color=\"BFBFBF\"/><w:left w:val=\"single\" w:sz=\"4\" w:color=\"BFBFBF\"/><w:bottom w:val=\"single\" w:sz=\"4\" w:color=\"BFBFBF\"/><w:right w:val=\"single\" w:sz=\"4\" w:color=\"BFBFBF\"/><w:insideH w:val=\"single\" w:sz=\"4\" w:color=\"BFBFBF\"/><w:insideV w:val=\"single\" w:sz=\"4\" w:color=\"BFBFBF\"/></w:tblBorders><w:tblCellMar><w:left w:w=\"80\" w:type=\"dxa\"/><w:right w:w=\"80\" w:type=\"dxa\"/></w:tblCellMar></w:tblPr></w:style></w:styles>"
        }

        // MARK: Body

        private func bodyXML() -> String {
            var out = ""
            var table: (id: ObjectIdentifier, block: NSTextTable, cells: [[String: (NSTextTableBlock, String)]])?
            func flush() {
                if let t = table { out += tableXML(t.block, t.cells) }
                table = nil
            }
            let ns = text.string as NSString
            ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .byParagraphs) { _, range, _, _ in
                let style = range.length > 0 ? self.text.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle : nil
                if let cell = style?.textBlocks.compactMap({ $0 as? NSTextTableBlock }).first {
                    let id = ObjectIdentifier(cell.table)
                    if table?.id != id { flush(); table = (id, cell.table, []) }
                    while table!.cells.count <= cell.startingRow { table!.cells.append([:]) }
                    let existing = table!.cells[cell.startingRow][String(cell.startingColumn)]?.1 ?? ""
                    table!.cells[cell.startingRow][String(cell.startingColumn)] = (cell, existing + self.paragraphXML(range, style: style, inTable: true))
                    return
                }
                // Blank lines between rows would otherwise split one table into many.
                if table != nil && ns.substring(with: range).trimmingCharacters(in: .whitespaces).isEmpty { return }
                flush()
                out += self.paragraphXML(range, style: style, inTable: false)
            }
            flush()
            return out
        }

        private func tableXML(_ table: NSTextTable, _ rows: [[String: (NSTextTableBlock, String)]]) -> String {
            let columns = max(table.numberOfColumns, rows.map { $0.keys.compactMap(Int.init).max().map { $0 + 1 } ?? 0 }.max() ?? 1)
            // Wide tables get a landscape page, and columns share the width by how much they hold.
            if columns >= 7 { landscape = true }
            let total = columns >= 7 ? 13958 : 9026
            // First every column gets room for its longest word, then the rest of the width goes to
            // the columns holding the most text.
            // Wide tables are set in 9 pt, as spreadsheets usually are, so they fit across the page.
            let wide = columns >= 7
            let charWidth = Double(wide ? 9 : base) * 0.55 * 20  // twentieths of a point per character, roughly
            func fit(_ xml: String) -> String {
                guard wide, let re = try? NSRegularExpression(pattern: "<w:sz w:val=\"(\\d+)\"/>") else { return xml }
                var out = xml
                for m in re.matches(in: xml, range: NSRange(xml.startIndex..., in: xml)).reversed() {
                    if let r = Range(m.range(at: 1), in: xml), Int(xml[r]) ?? 0 > 18, let whole = Range(m.range, in: out) {
                        out.replaceSubrange(whole, with: "<w:sz w:val=\"18\"/>")
                    }
                }
                return xml.contains("<w:sz ") ? out : out.replacingOccurrences(of: "<w:r>", with: "<w:r><w:rPr><w:sz w:val=\"18\"/></w:rPr>")
            }
            var minimum = Array(repeating: 300.0, count: columns), wanted = Array(repeating: 300.0, count: columns)
            for row in rows {
                for (key, cell) in row {
                    guard let c = Int(key), c < columns, cell.0.columnSpan <= 1 else { continue }
                    let plain = cell.1.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                    let longestWord = plain.split(whereSeparator: { $0 == " " }).map(\.count).max() ?? 0
                    minimum[c] = max(minimum[c], Double(min(longestWord, 22)) * charWidth + 200)
                    wanted[c] = max(wanted[c], Double(min(plain.count, 45)) * charWidth + 200)
                }
            }
            var widths: [Int]
            let floor = minimum.reduce(0, +)
            if floor >= Double(total) {
                widths = minimum.map { Int($0 * Double(total) / floor) }
            } else {
                let extra = zip(wanted, minimum).map { max(0, $0 - $1) }
                let extraSum = max(1, extra.reduce(0, +))
                widths = minimum.indices.map { Int(minimum[$0] + (Double(total) - floor) * extra[$0] / extraSum) }
            }
            func span(_ c: Int, _ n: Int) -> Int { widths[c..<min(columns, c + n)].reduce(0, +) }
            let border = "w:val=\"single\" w:sz=\"4\" w:space=\"0\" w:color=\"BFBFBF\""
            var xml = "<w:tbl><w:tblPr><w:tblStyle w:val=\"Grid\"/><w:tblW w:w=\"\(total)\" w:type=\"dxa\"/><w:tblBorders>"
                + ["top", "left", "bottom", "right", "insideH", "insideV"].map { "<w:\($0) \(border)/>" }.joined()
                + "</w:tblBorders><w:tblLayout w:type=\"fixed\"/><w:tblCellMar><w:left w:w=\"80\" w:type=\"dxa\"/><w:right w:w=\"80\" w:type=\"dxa\"/></w:tblCellMar></w:tblPr><w:tblGrid>"
            xml += widths.map { "<w:gridCol w:w=\"\($0)\"/>" }.joined() + "</w:tblGrid>"
            for row in rows {
                xml += "<w:tr>"
                var c = 0
                while c < columns {
                    if let (block, content) = row[String(c)] {
                        let n = max(1, block.columnSpan)
                        var tcPr = "<w:tcW w:w=\"\(span(c, n))\" w:type=\"dxa\"/>"
                        if n > 1 { tcPr += "<w:gridSpan w:val=\"\(n)\"/>" }
                        if let bg = block.backgroundColor, let hex = hex(bg) { tcPr += "<w:shd w:val=\"clear\" w:color=\"auto\" w:fill=\"\(hex)\"/>" }
                        xml += "<w:tc><w:tcPr>\(tcPr)</w:tcPr>\(content.isEmpty ? "<w:p/>" : fit(content))</w:tc>"
                        c += n
                    } else {
                        xml += "<w:tc><w:tcPr><w:tcW w:w=\"\(widths[c])\" w:type=\"dxa\"/></w:tcPr><w:p/></w:tc>"
                        c += 1
                    }
                }
                xml += "</w:tr>"
            }
            return xml + "</w:tbl><w:p/>"
        }

        private func paragraphXML(_ range: NSRange, style: NSParagraphStyle?, inTable: Bool) -> String {
            let para = text.attributedSubstring(from: range)
            let plain = para.string.trimmingCharacters(in: .whitespaces)
            var pPr = ""
            let size = (para.length > 0 ? para.attribute(.font, at: 0, effectiveRange: nil) as? NSFont : nil)?.pointSize ?? base
            if !inTable, !plain.isEmpty, plain.count <= 120 {
                if size >= base * 1.6 { pPr += "<w:pStyle w:val=\"Heading1\"/>" }
                else if size >= base * 1.3 { pPr += "<w:pStyle w:val=\"Heading2\"/>" }
                else if size >= base * 1.12 { pPr += "<w:pStyle w:val=\"Heading3\"/>" }
            }
            switch style?.alignment {
            case .center: pPr += "<w:jc w:val=\"center\"/>"
            case .right: pPr += "<w:jc w:val=\"right\"/>"
            case .justified: pPr += "<w:jc w:val=\"both\"/>"
            default: break
            }
            if inTable { pPr += "<w:spacing w:after=\"0\"/>" }
            var runs = ""
            if let list = style?.textLists.last, !plain.isEmpty {
                let depth = max(0, (style?.textLists.count ?? 1) - 1)
                pPr += "<w:ind w:left=\"\(360 * (depth + 1))\" w:hanging=\"260\"/>"
                // Imported lists usually carry their marker as text already ("\t•\t"); add one only if not.
                let hasMarker = plain.trimmingCharacters(in: .whitespacesAndNewlines).range(of: "^([•◦▪‣⁃–-]|\\d+[.)])", options: .regularExpression) != nil
                if !hasMarker && !list.markerFormat.rawValue.contains("decimal") { runs += "<w:r><w:t xml:space=\"preserve\">•\t</w:t></w:r>" }
            }
            para.enumerateAttributes(in: NSRange(location: 0, length: para.length)) { attrs, r, _ in
                runs += self.runXML((para.string as NSString).substring(with: r), attrs)
            }
            return "<w:p>\(pPr.isEmpty ? "" : "<w:pPr>\(pPr)</w:pPr>")\(runs)</w:p>"
        }

        private func runXML(_ string: String, _ attrs: [NSAttributedString.Key: Any]) -> String {
            if let attachment = attrs[.attachment] as? NSTextAttachment, let drawing = drawingXML(attachment) {
                return "<w:r>\(drawing)</w:r>"
            }
            let clean = string.replacingOccurrences(of: "\u{FFFC}", with: "").replacingOccurrences(of: "\n", with: "")
            guard !clean.isEmpty else { return "" }
            var rPr = ""
            if let font = attrs[.font] as? NSFont {
                let traits = font.fontDescriptor.symbolicTraits
                if let family = font.familyName { rPr += "<w:rFonts w:ascii=\"\(esc(family))\" w:hAnsi=\"\(esc(family))\" w:cs=\"\(esc(family))\"/>" }
                if traits.contains(.bold) { rPr += "<w:b/>" }
                if traits.contains(.italic) { rPr += "<w:i/>" }
                rPr += "<w:sz w:val=\"\(Int((font.pointSize * 2).rounded()))\"/>"
            }
            if let color = attrs[.foregroundColor] as? NSColor, let hex = hex(color), hex != "000000" { rPr += "<w:color w:val=\"\(hex)\"/>" }
            if let u = attrs[.underlineStyle] as? Int, u != 0 { rPr += "<w:u w:val=\"single\"/>" }
            if let s = attrs[.strikethroughStyle] as? Int, s != 0 { rPr += "<w:strike/>" }
            let parts = clean.components(separatedBy: "\t").map { "<w:t xml:space=\"preserve\">\(esc($0))</w:t>" }
            let run = "<w:r>\(rPr.isEmpty ? "" : "<w:rPr>\(rPr)</w:rPr>")\(parts.joined(separator: "<w:tab/>"))</w:r>"
            let link = (attrs[.link] as? URL)?.absoluteString ?? attrs[.link] as? String
            if let link, link.hasPrefix("http") || link.hasPrefix("mailto:") {
                links.append(link)
                return "<w:hyperlink r:id=\"rIdLink\(links.count - 1)\">\(run)</w:hyperlink>"
            }
            return run
        }

        private func drawingXML(_ attachment: NSTextAttachment) -> String? {
            // Only real picture data: a reader that couldn't load an image leaves a "missing" placeholder.
            guard let data = attachment.fileWrapper?.regularFileContents, let image = NSImage(data: data), let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { return nil }
            images.append(png)
            let n = images.count
            var size = attachment.bounds.size.width > 0 ? attachment.bounds.size : image.size
            if size.width > 451 { size = CGSize(width: 451, height: size.height * 451 / size.width) }  // fit the text column
            let cx = Int(size.width * 12700), cy = Int(size.height * 12700)
            return """
            <w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0"><wp:extent cx="\(cx)" cy="\(cy)"/><wp:docPr id="\(n)" name="Picture \(n)"/><a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:pic><pic:nvPicPr><pic:cNvPr id="\(n)" name="image\(n).png"/><pic:cNvPicPr/></pic:nvPicPr><pic:blipFill><a:blip r:embed="rIdImg\(n - 1)"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill><pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="\(cx)" cy="\(cy)"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing>
            """
        }

        private func hex(_ color: NSColor) -> String? {
            guard let c = color.usingColorSpace(.sRGB), c.alphaComponent > 0.05 else { return nil }
            return String(format: "%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
        }

        private func esc(_ s: String) -> String { ZipPackage.xmlEscape(s) }
    }
}
