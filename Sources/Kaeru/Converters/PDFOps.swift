import AppKit
import PDFKit
import Quartz

enum PDFOps {
    static func open(_ url: URL) throws -> PDFDocument {
        guard let doc = PDFDocument(url: url) else { throw fail("Couldn't open \(url.lastPathComponent)") }
        if doc.isLocked { throw fail("\(url.lastPathComponent) is password protected") }
        return doc
    }

    static func convertOps() -> [FileOperation] {
        var ops: [FileOperation] = ["png", "jpg"].map { ext in
            .perFile("pdf.\(ext)", ext.uppercased(), "photo.on.rectangle", ext: ext) { url, p in
                try toImages(url, ext: ext, progress: p)
            }
        }
        ops.append(.perFile("pdf.txt", "TXT", "doc.plaintext", ext: "txt") { url, _ in
            let out = Output.file(for: url, ext: "txt")
            try plainText(url).write(to: out, atomically: true, encoding: .utf8)
            return [out]
        })
        for (ext, title) in [("md", "Markdown"), ("docx", "DOCX"), ("rtf", "RTF"), ("html", "HTML")] {
            ops.append(FileOperation(id: "pdf.\(ext)", title: title, symbol: "doc.richtext", targetExt: ext) { inputs, progress in
                var result = OpResult()
                for (i, url) in inputs.enumerated() {
                    let out = Output.file(for: url, ext: ext)
                    // Word rebuilds a PDF as a real document, with pictures, tables and styles.
                    var done = false
                    if ["docx", "rtf"].contains(ext) && OfficeApps.hasWord && hasTextLayer(url) {
                        do {
                            try await OfficeApps.pdfToWord(url, out)
                            done = true
                        } catch {
                            NSLog("Kaeru: Word PDF conversion failed, using text extraction: \(error.localizedDescription)")
                            result.message = "Made without Word, so pictures and layout are left out. Allow Kaeru to control Microsoft Word in System Settings → Privacy & Security → Automation"
                        }
                    }
                    if !done {
                        let text = try await attributedText(url)
                        try await DocumentOps.save(text, to: out)
                    }
                    result.outputs.append(out)
                    progress(Double(i + 1) / Double(inputs.count))
                }
                return result
            })
        }
        ops.append(.perFile("pdf.pptx", "PPTX", "rectangle.on.rectangle", ext: "pptx") { url, p in
            let doc = try open(url)
            guard let first = doc.page(at: 0) else { throw fail("\(url.lastPathComponent) has no pages") }
            let box = first.bounds(for: .mediaBox)
            let size = first.rotation % 180 == 0 ? box.size : CGSize(width: box.height, height: box.width)
            var slides: [CGImage] = []
            for i in 0..<doc.pageCount {
                if let page = doc.page(at: i), let img = render(page, dpi: 200) { slides.append(img) }
                p(Double(i + 1) / Double(doc.pageCount) * 0.8)
            }
            let out = Output.file(for: url, ext: "pptx")
            try await PPTX.write(images: slides, slideSize: size, to: out)
            return [out]
        })
        ops.append(.perFile("pdf.epub", "EPUB", "book", ext: "epub") { url, _ in
            let out = Output.file(for: url, ext: "epub")
            let text = try await attributedText(url)
            let markdown = await MainActor.run { Markdown.fromAttributed(text) }
            try await EPUB.write(title: url.deletingPathExtension().lastPathComponent, markdown: markdown, to: out)
            return [out]
        })
        return ops
    }

    static func toolOps() -> [FileOperation] {
        [
            .shrinking("pdf.compress", "Compress", "arrow.down.right.and.arrow.up.left") { url, _ in
                let out = Output.file(for: url, ext: "pdf", suffix: "compressed")
                let options: [PDFDocumentWriteOption: Any]
                if #available(macOS 13.4, *) {
                    options = [.saveImagesAsJPEGOption: true, .optimizeImagesForScreenOption: true]
                } else {
                    // Older systems: the "Reduce File Size" Quartz filter that Preview uses.
                    let filter = QuartzFilter(url: URL(fileURLWithPath: "/System/Library/Filters/Reduce File Size.qfilter"))
                    options = [PDFDocumentWriteOption(rawValue: "QuartzFilter"): filter as Any]
                }
                guard try open(url).write(to: out, withOptions: options) else { throw fail("Couldn't write compressed PDF") }
                return [out]
            },
            .perFile("pdf.searchable", "Make Searchable", "doc.text.magnifyingglass") { url, _ in
                let out = Output.file(for: url, ext: "pdf", suffix: "searchable")
                guard try open(url).write(to: out, withOptions: [.saveTextFromOCROption: true]) else {
                    throw fail("Couldn't write searchable PDF")
                }
                return [out]
            },
            .perFile("pdf.ocr", "Extract Text", "text.viewfinder") { url, p in
                [try VisionOps.ocrPDF(url, progress: p)]
            },
            .perFile("pdf.split", "Split Pages", "square.split.2x1") { url, _ in
                let doc = try open(url)
                guard doc.pageCount > 1 else { throw fail("\(url.lastPathComponent) has only one page") }
                let folder = try Output.folder(for: url, suffix: "pages")
                let base = url.deletingPathExtension().lastPathComponent
                for i in 0..<doc.pageCount {
                    let single = PDFDocument()
                    if let page = doc.page(at: i)?.copy() as? PDFPage { single.insert(page, at: 0) }
                    single.write(to: folder.appendingPathComponent(String(format: "%@ %03d.pdf", base, i + 1)))
                }
                return [folder]
            },
            .perFile("pdf.rotate", "Rotate Right", "rotate.right") { url, _ in
                let doc = try open(url)
                for i in 0..<doc.pageCount { doc.page(at: i)?.rotation += 90 }
                let out = Output.file(for: url, ext: "pdf", suffix: "rotated")
                guard doc.write(to: out) else { throw fail("Couldn't write rotated PDF") }
                return [out]
            },
        ]
    }

    /// Combines PDFs and images, in the order given, into one PDF.
    static let combineOp = FileOperation(id: "pdf.combine", title: "Combine PDF", symbol: "doc.on.doc") { urls, progress in
        let result = PDFDocument()
        for (i, url) in urls.enumerated() {
            if FileKind.of(url) == .pdf {
                let doc = try open(url)
                for p in 0..<doc.pageCount {
                    if let page = doc.page(at: p)?.copy() as? PDFPage { result.insert(page, at: result.pageCount) }
                }
            } else {
                let tmp = Output.temp(ext: "pdf")
                defer { try? FileManager.default.removeItem(at: tmp) }
                try ImageOps.makePDF(images: [try ImageOps.load(url).0], to: tmp)
                if let page = PDFDocument(url: tmp)?.page(at: 0) { result.insert(page, at: result.pageCount) }
            }
            progress(Double(i + 1) / Double(urls.count))
        }
        let out = Output.file(named: "Combined.pdf", near: urls[0])
        guard result.write(to: out) else { throw fail("Couldn't write combined PDF") }
        return OpResult(outputs: [out], message: "\(result.pageCount) pages")
    }

    /// Renders a page at the given DPI, honouring its rotation.
    static func render(_ page: PDFPage, dpi: CGFloat) -> CGImage? {
        let box = page.bounds(for: .mediaBox)
        let scale = dpi / 72
        let rotated = page.rotation % 180 != 0
        let w = Int(((rotated ? box.height : box.width) * scale).rounded())
        let h = Int(((rotated ? box.width : box.height) * scale).rounded())
        return ImageOps.draw(width: w, height: h, opaque: true) { ctx in
            ctx.scaleBy(x: scale, y: scale)
            page.transform(ctx, for: .mediaBox)
            if let ref = page.pageRef { ctx.drawPDFPage(ref) }
        }
    }

    /// Every page at 300 DPI; multi-page documents go into a folder.
    /// `naming` is the file outputs are named after, when `url` is an intermediate temp PDF.
    static func toImages(_ url: URL, ext: String, naming: URL? = nil, progress: ProgressHandler) throws -> [URL] {
        let doc = try open(url)
        let source = naming ?? url
        let base = source.deletingPathExtension().lastPathComponent
        let folder = doc.pageCount > 1 ? try Output.folder(for: source, suffix: ext.uppercased()) : nil
        let uti = ext == "png" ? "public.png" : "public.jpeg"
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i), let img = render(page, dpi: 300) else { continue }
            let out = folder?.appendingPathComponent(String(format: "%@ %03d.%@", base, i + 1, ext))
                ?? Output.file(for: source, ext: ext)
            guard let dest = CGImageDestinationCreateWithURL(out as CFURL, uti as CFString, 1, nil) else { continue }
            CGImageDestinationAddImage(dest, img, [kCGImageDestinationLossyCompressionQuality: 0.92,
                                                   kCGImagePropertyDPIWidth: 300, kCGImagePropertyDPIHeight: 300] as CFDictionary)
            CGImageDestinationFinalize(dest)
            progress(Double(i + 1) / Double(doc.pageCount))
            if folder == nil { return [out] }
        }
        return folder.map { [$0] } ?? []
    }

    /// PDFs store each printed line separately. Rejoins lines that continue the same sentence in the
    /// same type size, so paragraphs and long headings come out whole.
    static func joiningWrappedLines(_ text: NSAttributedString) -> NSAttributedString {
        let out = NSMutableAttributedString(attributedString: text)
        let ns = text.string as NSString
        let lines = ns.components(separatedBy: "\n")
        func size(at i: Int) -> CGFloat {
            guard i >= 0, i < text.length else { return 0 }
            return ((text.attribute(.font, at: i, effectiveRange: nil) as? NSFont)?.pointSize ?? 0).rounded()
        }
        var offset = 0
        var joins: [Int] = []
        for (n, line) in lines.enumerated() where n + 1 < lines.count {
            let len = (line as NSString).length
            let newline = offset + len
            offset = newline + 1
            let current = line.trimmingCharacters(in: .whitespaces)
            let next = lines[n + 1].trimmingCharacters(in: .whitespaces)
            guard let last = current.last, let first = next.first, len > 0,
                  size(at: newline - 1) == size(at: newline + 1) else { continue }
            let ends = ".!?:;".contains(last)
            if !ends && first.isLowercase { joins.append(newline) }
        }
        for i in joins.reversed() { out.replaceCharacters(in: NSRange(location: i, length: 1), with: " ") }
        return out
    }

    static func hasTextLayer(_ url: URL) -> Bool {
        !((try? open(url).string) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The PDF's own text, or OCR when it's a scan with no text layer.
    static func plainText(_ url: URL) throws -> String {
        if hasTextLayer(url) {
            let doc = try open(url)
            return (0..<doc.pageCount).compactMap { i -> String? in
                guard let page = doc.page(at: i) else { return nil }
                if let grid = PDFLayout.table(page) { return grid.map { $0.joined(separator: "\t") }.joined(separator: "\n") }
                return page.string
            }.joined(separator: "\n\n")
        }
        let text = try VisionOps.recognizePDF(url)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw fail("No text found in \(url.lastPathComponent)") }
        return text
    }

    /// Styled text from the PDF; scans with no text layer are read with OCR instead.
    static func attributedText(_ url: URL) async throws -> NSAttributedString {
        if !hasTextLayer(url) {
            let text = try plainText(url)
            return await MainActor.run {
                NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 12)])
            }
        }
        return try await MainActor.run { try styledText(url) }
    }

    @MainActor
    private static func styledText(_ url: URL) throws -> NSAttributedString {
        let doc = try open(url)
        let result = NSMutableAttributedString()
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            if result.length > 0 { result.append(NSAttributedString(string: "\n\n")) }
            // Pages that are mostly a table become a real table rather than one column after another.
            if let grid = PDFLayout.table(page) {
                result.append(try DocumentOps.html(Markdown.wrap(Markdown.table(grid))))
            } else if let text = page.attributedString {
                result.append(joiningWrappedLines(text))
            }
        }
        guard result.length > 0 else { throw fail("\(url.lastPathComponent) has no text layer. Try Tools → Extract Text") }
        return result
    }
}
