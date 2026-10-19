import CoreImage
import Foundation
import PDFKit
import Vision

/// On-device machine learning: background removal and text recognition.
enum VisionOps {
    @available(macOS 14.0, *)
    static func removeBackground(_ url: URL) throws -> URL {
        let (img, _) = try ImageOps.load(url)
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: img)
        try handler.perform([request])
        guard let result = request.results?.first else { throw fail("No subject found in \(url.lastPathComponent)") }
        let buffer = try result.generateMaskedImage(ofInstances: result.allInstances, from: handler,
                                                    croppedToInstancesExtent: false)
        let ci = CIImage(cvPixelBuffer: buffer)
        guard let cut = CIContext().createCGImage(ci, from: ci.extent) else { throw fail("Couldn't render cutout") }
        let out = Output.file(for: url, ext: "png", suffix: "no background")
        guard let dest = CGImageDestinationCreateWithURL(out as CFURL, "public.png" as CFString, 1, nil) else {
            throw fail("Couldn't create \(out.lastPathComponent)")
        }
        CGImageDestinationAddImage(dest, cut, nil)
        guard CGImageDestinationFinalize(dest) else { throw fail("Couldn't write PNG") }
        return out
    }

    static func recognizeText(_ image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    static func ocrImage(_ url: URL) throws -> URL {
        let (img, _) = try ImageOps.load(url)
        let text = try recognizeText(img)
        guard !text.isEmpty else { throw fail("No text found in \(url.lastPathComponent)") }
        let out = Output.file(for: url, ext: "txt")
        try text.write(to: out, atomically: true, encoding: .utf8)
        return out
    }

    /// OCR for scanned PDFs that have no text layer: renders each page and recognizes it.
    static func ocrPDF(_ url: URL, progress: ProgressHandler) throws -> URL {
        let out = Output.file(for: url, ext: "txt", suffix: "OCR")
        try recognizePDF(url, progress: progress).write(to: out, atomically: true, encoding: .utf8)
        return out
    }

    /// Reads every page of a PDF with OCR, pages separated by blank lines.
    static func recognizePDF(_ url: URL, progress: ProgressHandler = { _ in }) throws -> String {
        let doc = try PDFOps.open(url)
        var pages: [String] = []
        for i in 0..<doc.pageCount {
            if let page = doc.page(at: i), let img = PDFOps.render(page, dpi: 200) {
                pages.append(try recognizeText(img))
            }
            progress(Double(i + 1) / Double(doc.pageCount))
        }
        return pages.joined(separator: "\n\n")
    }
}
