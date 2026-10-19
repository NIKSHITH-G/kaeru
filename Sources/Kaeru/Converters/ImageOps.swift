import AppKit
import CoreImage
import ImageIO
import PDFKit
import UniformTypeIdentifiers

enum ImageOps {
    static let targets: [(ext: String, title: String)] = [
        ("jpg", "JPG"), ("png", "PNG"), ("heic", "HEIC"), ("webp", "WebP"), ("avif", "AVIF"), ("tiff", "TIFF"),
        ("gif", "GIF"), ("bmp", "BMP"), ("pdf", "PDF"), ("ico", "ICO"), ("icns", "ICNS"),
    ]

    static func convertOps(svg: Bool) -> [FileOperation] {
        let list = svg ? targets.filter { ["png", "jpg", "heic", "webp", "tiff", "pdf"].contains($0.ext) } : targets
        return list.map { t in
            .perFile("image.\(t.ext)", t.title, "photo", ext: t.ext) { url, _ in
                [try await convert(url, to: t.ext)]
            }
        }
    }

    static func toolOps() -> [FileOperation] {
        var ops: [FileOperation] = [
            .shrinking("image.compress", "Compress", "arrow.down.right.and.arrow.up.left") { url, _ in
                [try await compress(url)]
            },
            .perFile("image.half", "Half Size", "square.resize.down") { url, _ in
                let out = Output.file(for: url, ext: writableExt(url), suffix: "half")
                let (full, _) = try load(url)
                let (img, meta) = try load(url, maxPixel: max(full.width, full.height) / 2)
                try await write(img, to: out, quality: 0.92, metadata: meta)
                return [out]
            },
            .perFile("image.fit1920", "Fit 1920px", "rectangle.compress.vertical") { url, _ in
                let out = Output.file(for: url, ext: writableExt(url), suffix: "1920px")
                let (img, meta) = try load(url, maxPixel: 1920)
                try await write(img, to: out, metadata: meta)
                return [out]
            },
            .perFile("image.rotate", "Rotate Right", "rotate.right") { url, _ in
                [try await redrawn(url, suffix: "rotated", rotateRight)]
            },
            .perFile("image.flip", "Flip", "arrow.left.and.right.righttriangle.left.righttriangle.right") { url, _ in
                [try await redrawn(url, suffix: "flipped", flipHorizontal)]
            },
            .perFile("image.gray", "Grayscale", "circle.lefthalf.filled") { url, _ in
                [try await redrawn(url, suffix: "grayscale", grayscale)]
            },
            .perFile("image.strip", "Remove Metadata", "eye.slash") { url, _ in
                let out = Output.file(for: url, ext: writableExt(url), suffix: "clean")
                let (img, _) = try load(url)
                try await write(img, to: out, metadata: [:])
                return [out]
            },
            .perFile("image.ocr", "Extract Text", "text.viewfinder") { url, _ in
                [try VisionOps.ocrImage(url)]
            },
        ]
        if #available(macOS 14.0, *) {
            ops.insert(.perFile("image.removebg", "Remove Background", "person.crop.rectangle") { url, _ in
                [try VisionOps.removeBackground(url)]
            }, at: 1)
        }
        return ops
    }

    // MARK: Loading

    /// Loads an image with EXIF orientation applied, optionally downscaled so its longest side is `maxPixel`.
    static func load(_ url: URL, maxPixel: Int? = nil) throws -> (CGImage, [CFString: Any]) {
        if let src = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(src) > 0 {
            let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] ?? [:]
            let orientation = props[kCGImagePropertyOrientation] as? Int ?? 1
            let w = props[kCGImagePropertyPixelWidth] as? Int ?? 0
            let h = props[kCGImagePropertyPixelHeight] as? Int ?? 0
            let image: CGImage?
            if orientation == 1 && (maxPixel == nil || maxPixel! >= max(w, h)) {
                image = CGImageSourceCreateImageAtIndex(src, 0, nil)
            } else {
                let opts: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceShouldCacheImmediately: true,
                    kCGImageSourceThumbnailMaxPixelSize: min(maxPixel ?? Int.max, max(w, h, 1)),
                ]
                image = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
            }
            if let image { return (image, metadata(from: props)) }
        }
        // SVG and other formats ImageIO can't read, but AppKit can.
        if let ns = NSImage(contentsOf: url), let img = rasterize(ns, maxSide: CGFloat(maxPixel ?? 2048)) {
            return (img, [:])
        }
        throw fail("Couldn't read \(url.lastPathComponent) as an image")
    }

    private static func metadata(from props: [CFString: Any]) -> [CFString: Any] {
        var meta: [CFString: Any] = [:]
        for key in [kCGImagePropertyExifDictionary, kCGImagePropertyGPSDictionary, kCGImagePropertyIPTCDictionary,
                    kCGImagePropertyDPIWidth, kCGImagePropertyDPIHeight] {
            if let v = props[key] { meta[key] = v }
        }
        if var tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            tiff[kCGImagePropertyTIFFOrientation] = 1
            meta[kCGImagePropertyTIFFDictionary] = tiff
        }
        meta[kCGImagePropertyOrientation] = 1
        return meta
    }

    static func rasterize(_ image: NSImage, maxSide: CGFloat) -> CGImage? {
        var size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = maxSide / max(size.width, size.height)
        size = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        return draw(width: Int(size.width), height: Int(size.height), opaque: false) { ctx in
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            image.draw(in: CGRect(origin: .zero, size: size))
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    // MARK: Writing

    /// Formats ImageIO can write directly; others go through special paths below.
    private static let utiForExt: [String: String] = [
        "jpg": "public.jpeg", "png": "public.png", "heic": "public.heic", "avif": "public.avif",
        "tiff": "public.tiff", "gif": "com.compuserve.gif", "bmp": "com.microsoft.bmp",
        "ico": "com.microsoft.ico", "icns": "com.apple.icns", "jp2": "public.jpeg-2000",
    ]

    /// The output extension for in-place tools: same format when writable, otherwise PNG.
    static func writableExt(_ url: URL) -> String {
        let ext = FileKind.normalizedExt(url.pathExtension)
        return utiForExt[ext] != nil || ext == "webp" ? ext : "png"
    }

    static func write(_ image: CGImage, to url: URL, quality: Double? = nil, metadata: [CFString: Any] = [:]) async throws {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "pdf":
            try makePDF(images: [image], to: url)
            return
        case "webp":
            try await writeWebP(image, to: url, quality: quality ?? 0.85)
            return
        case "icns":
            try await writeICNS(image, to: url)
            return
        default: break
        }
        guard let uti = utiForExt[ext] else { throw fail("Can't write .\(ext) images") }
        var img = image
        if ext == "jpg" || ext == "bmp" { img = flatten(img) }
        if ext == "ico" { img = squared(img, side: min(256, max(img.width, img.height))) }

        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, uti as CFString, 1, nil) else {
            throw fail("Couldn't create \(url.lastPathComponent)")
        }
        var props = metadata
        if let quality { props[kCGImageDestinationLossyCompressionQuality] = quality }
        CGImageDestinationAddImage(dest, img, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            try? FileManager.default.removeItem(at: url)
            throw fail("Couldn't encode \(ext.uppercased())")
        }
    }

    /// Neither ImageIO nor the stock Homebrew ffmpeg can encode WebP, so use cwebp from libwebp.
    private static func writeWebP(_ image: CGImage, to url: URL, quality: Double) async throws {
        let cwebp = try Tools.require("cwebp", hint: "WebP export needs libwebp: brew install webp")
        let tmp = Output.temp(ext: "png")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try await write(image, to: tmp)
        try await Shell.run(cwebp, ["-quiet", "-q", String(Int(quality * 100)), "-alpha_q", "100", tmp.path, "-o", url.path])
    }

    /// Builds a full .iconset (16–1024 px, 1x and 2x) and packs it with iconutil.
    private static func writeICNS(_ image: CGImage, to url: URL) async throws {
        let set = try Output.tempDirectory().appendingPathComponent("icon.iconset")
        defer { try? FileManager.default.removeItem(at: set.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
        for size in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
                try await write(squared(image, side: size * scale), to: set.appendingPathComponent(name))
            }
        }
        try await Shell.run("/usr/bin/iconutil", ["-c", "icns", set.path, "-o", url.path])
    }

    static func makePDF(images: [CGImage], to url: URL) throws {
        let doc = PDFDocument()
        for img in images {
            // Fit pages to A4 height so a 4000px photo doesn't become a 55-inch page; pixels are kept.
            let scale = min(1, 842 / CGFloat(max(img.width, img.height)))
            let size = NSSize(width: CGFloat(img.width) * scale, height: CGFloat(img.height) * scale)
            if let page = PDFPage(image: NSImage(cgImage: img, size: size)) {
                doc.insert(page, at: doc.pageCount)
            }
        }
        guard doc.pageCount > 0, doc.write(to: url) else { throw fail("Couldn't create PDF") }
    }

    static func convert(_ url: URL, to ext: String) async throws -> URL {
        let out = Output.file(for: url, ext: ext)
        let (img, meta) = try load(url)
        let quality: Double? = ["jpg", "heic", "avif", "webp"].contains(ext) ? 0.9 : nil
        try await write(img, to: out, quality: quality, metadata: meta)
        return out
    }

    static func compress(_ url: URL) async throws -> URL {
        let ext = FileKind.normalizedExt(url.pathExtension)
        if ext == "png", let ffmpeg = Tools.path("ffmpeg") {
            // Palette quantization, similar to pngquant: usually 60-80% smaller with alpha intact.
            let out = Output.file(for: url, ext: "png", suffix: "compressed")
            try await Shell.run(ffmpeg, ["-hide_banner", "-loglevel", "error", "-y", "-i", url.path, "-vf",
                                         "split[a][b];[a]palettegen=reserve_transparent=1:max_colors=256[p];[b][p]paletteuse=dither=sierra2_4a",
                                         out.path])
            return out
        }
        let target = ["jpg", "heic", "avif", "webp"].contains(ext) ? ext : "jpg"
        let out = Output.file(for: url, ext: target, suffix: "compressed")
        let (img, meta) = try load(url)
        try await write(img, to: out, quality: 0.6, metadata: meta)
        return out
    }

    // MARK: Pixel transforms

    private static func redrawn(_ url: URL, suffix: String, _ body: (CGImage) -> CGImage) async throws -> URL {
        let out = Output.file(for: url, ext: writableExt(url), suffix: suffix)
        let (img, meta) = try load(url)
        try await write(body(img), to: out, quality: 0.92, metadata: meta)
        return out
    }

    static func draw(width: Int, height: Int, opaque: Bool, _ body: (CGContext) -> Void) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: opaque ? CGImageAlphaInfo.noneSkipLast.rawValue
                                                     : CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        if opaque {
            ctx.setFillColor(.white)
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        ctx.interpolationQuality = .high
        body(ctx)
        return ctx.makeImage()
    }

    static func flatten(_ img: CGImage) -> CGImage {
        switch img.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return img
        default:
            return draw(width: img.width, height: img.height, opaque: true) {
                $0.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
            } ?? img
        }
    }

    static func squared(_ img: CGImage, side: Int) -> CGImage {
        draw(width: side, height: side, opaque: false) { ctx in
            let scale = CGFloat(side) / CGFloat(max(img.width, img.height))
            let w = CGFloat(img.width) * scale, h = CGFloat(img.height) * scale
            ctx.draw(img, in: CGRect(x: (CGFloat(side) - w) / 2, y: (CGFloat(side) - h) / 2, width: w, height: h))
        } ?? img
    }

    static func rotateRight(_ img: CGImage) -> CGImage {
        let w = img.width, h = img.height
        return draw(width: h, height: w, opaque: false) { ctx in
            ctx.translateBy(x: 0, y: CGFloat(w))
            ctx.rotate(by: -.pi / 2)
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        } ?? img
    }

    static func flipHorizontal(_ img: CGImage) -> CGImage {
        draw(width: img.width, height: img.height, opaque: false) { ctx in
            ctx.translateBy(x: CGFloat(img.width), y: 0)
            ctx.scaleBy(x: -1, y: 1)
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
        } ?? img
    }

    static func grayscale(_ img: CGImage) -> CGImage {
        let ci = CIImage(cgImage: img).applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
        return CIContext().createCGImage(ci, from: ci.extent) ?? img
    }
}
