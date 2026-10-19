import Foundation

/// PowerPoint and Keynote decks → PDF / PNG / JPG.
enum PresentationOps {
    static func convertOps() -> [FileOperation] {
        [(ext: "pdf", title: "PDF"), (ext: "png", title: "PNG"), (ext: "jpg", title: "JPG")].map { t in
            FileOperation(id: "slides.\(t.ext)", title: t.title, symbol: "rectangle.on.rectangle", targetExt: t.ext) { urls, progress in
                var outputs: [URL] = []
                var notes = Set<String>()
                for (i, url) in urls.enumerated() {
                    let (pdf, note) = try await toPDF(url)
                    if let note { notes.insert(note) }
                    if t.ext == "pdf" {
                        let out = Output.file(for: url, ext: "pdf")
                        try FileManager.default.moveItem(at: pdf, to: out)
                        outputs.append(out)
                    } else {
                        defer { try? FileManager.default.removeItem(at: pdf) }
                        outputs += try PDFOps.toImages(pdf, ext: t.ext, naming: url) { p in
                            progress((Double(i) + p) / Double(urls.count))
                        }
                    }
                    progress(Double(i + 1) / Double(urls.count))
                }
                return OpResult(outputs: outputs, message: notes.first)
            }
        }
    }

    /// Exports through PowerPoint or Keynote when available; otherwise renders QuickLook's preview.
    /// Returns a temporary PDF and an optional note about reduced fidelity.
    static func toPDF(_ url: URL) async throws -> (URL, String?) {
        let tmp = Output.temp(ext: "pdf")
        let isKeynote = url.pathExtension.lowercased() == "key"
        if OfficeApps.hasPowerPoint || OfficeApps.hasKeynote {
            do {
                try await OfficeApps.presentationToPDF(url, tmp)
                return (tmp, nil)
            } catch {
                if isKeynote { throw error }
                NSLog("Kaeru: app export failed, using QuickLook: \(error.localizedDescription)")
            }
        } else if isKeynote {
            throw fail("Keynote files need Keynote installed")
        }
        let slides = try await QuickLookOffice.slides(url)
        try ImageOps.makePDF(images: slides, to: tmp)
        return (tmp, "Rendered with QuickLook — install Keynote or PowerPoint to include pictures")
    }
}

/// Pages documents. Full conversion scripts the Pages app; without it, the preview embedded in
/// every .pages file still gives a PDF or JPG of the first page.
enum PagesOps {
    static func convertOps() -> [FileOperation] {
        if OfficeApps.hasPages {
            return [("pdf", "PDF"), ("docx", "DOCX"), ("epub", "EPUB"), ("rtf", "RTF"), ("txt", "TXT")].map { t in
                .perFile("pages.\(t.0)", t.1, "doc.richtext", ext: t.0) { url, _ in
                    let out = Output.file(for: url, ext: t.0)
                    try await OfficeApps.pagesExport(url, out)
                    return [out]
                }
            }
        }
        return [("pdf", "PDF"), ("jpg", "JPG")].map { t in
            .perFile("pages.preview.\(t.0)", "\(t.1) (preview)", "doc.richtext", ext: t.0) { url, _ in
                try await fromEmbeddedPreview(url, ext: t.0)
            }
        }
    }

    private static func fromEmbeddedPreview(_ url: URL, ext: String) async throws -> [URL] {
        var root = url
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        var temp: URL?
        if !isDir.boolValue {
            let dir = try Output.tempDirectory()
            try await Shell.run("/usr/bin/ditto", ["-x", "-k", url.path, dir.path])
            root = dir
            temp = dir
        }
        defer { if let temp { try? FileManager.default.removeItem(at: temp) } }

        let out = Output.file(for: url, ext: ext)
        let pdf = root.appendingPathComponent("QuickLook/Preview.pdf")
        if FileManager.default.fileExists(atPath: pdf.path) {
            if ext == "pdf" { try FileManager.default.copyItem(at: pdf, to: out); return [out] }
            return try PDFOps.toImages(pdf, ext: ext, naming: url) { _ in }
        }
        for candidate in ["preview.jpg", "QuickLook/Thumbnail.jpg", "preview-web.jpg"] {
            let image = root.appendingPathComponent(candidate)
            guard FileManager.default.fileExists(atPath: image.path) else { continue }
            let (img, _) = try ImageOps.load(image)
            try await ImageOps.write(img, to: out, quality: 0.92)
            return [out]
        }
        throw fail("This Pages file has no preview — install Pages to convert it")
    }
}
