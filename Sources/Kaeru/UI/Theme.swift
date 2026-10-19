import AppKit
import SwiftUI

/// Brand and category colours shared by the wheel, HUD, windows and icons.
enum Theme {
    static let brand = NSColor(srgbRed: 0.13, green: 0.77, blue: 0.47, alpha: 1)       // #22C578
    static let brandDeep = NSColor(srgbRed: 0.02, green: 0.52, blue: 0.38, alpha: 1)   // #058561

    enum Category {
        case image, video, audio, document, pdf, spreadsheet, slides, data, archive, tool, action

        var color: NSColor {
            switch self {
            case .image: return NSColor(srgbRed: 0.66, green: 0.33, blue: 0.97, alpha: 1)
            case .video: return NSColor(srgbRed: 0.96, green: 0.25, blue: 0.37, alpha: 1)
            case .audio: return NSColor(srgbRed: 0.98, green: 0.60, blue: 0.09, alpha: 1)
            case .document: return NSColor(srgbRed: 0.23, green: 0.51, blue: 0.96, alpha: 1)
            case .pdf: return NSColor(srgbRed: 0.94, green: 0.27, blue: 0.27, alpha: 1)
            case .spreadsheet: return NSColor(srgbRed: 0.06, green: 0.73, blue: 0.51, alpha: 1)
            case .slides: return NSColor(srgbRed: 0.98, green: 0.45, blue: 0.09, alpha: 1)
            case .data: return NSColor(srgbRed: 0.39, green: 0.45, blue: 0.55, alpha: 1)
            case .archive: return NSColor(srgbRed: 0.79, green: 0.54, blue: 0.02, alpha: 1)
            case .tool: return NSColor(srgbRed: 0.39, green: 0.40, blue: 0.95, alpha: 1)
            case .action: return NSColor(srgbRed: 0.02, green: 0.71, blue: 0.83, alpha: 1)
            }
        }
    }

    static func category(forExt ext: String) -> Category {
        switch ext.lowercased() {
        case "jpg", "jpeg", "png", "heic", "heif", "webp", "avif", "tiff", "tif", "gif", "bmp", "ico", "icns", "svg", "psd",
             "dng", "cr2", "cr3", "nef", "arw", "raf": return .image
        case "mp4", "mov", "mkv", "webm", "avi", "wmv": return .video
        case "mp3", "m4a", "wav", "flac", "ogg", "opus", "aiff", "wma": return .audio
        case "pdf": return .pdf
        case "docx", "doc", "odt", "rtf", "txt", "md", "html", "epub", "pages": return .document
        case "xlsx", "xls", "ods", "csv", "tsv": return .spreadsheet
        case "pptx", "ppt", "key": return .slides
        case "json", "plist", "srt", "vtt": return .data
        default: return .archive
        }
    }

    /// The colour for a wheel slice.
    static func color(for op: FileOperation, mode: WheelMode) -> NSColor {
        switch mode {
        case .convert: return category(forExt: op.targetExt ?? "").color
        case .tools: return Category.tool.color
        case .actions: return Category.action.color
        }
    }
}

extension NSColor {
    var swiftUI: Color { Color(nsColor: self) }
}

/// Vector artwork drawn in code, so there are no image assets to manage.
enum Artwork {
    /// Kaeru's frog: a rounded head with two eyes on top. Drawn into the current graphics context.
    static func frog(in rect: CGRect, head: NSColor, eye: NSColor, pupil: NSColor?) {
        let s = rect.width
        let headRect = CGRect(x: rect.minX, y: rect.minY, width: s, height: s * 0.62)
        let eyeSize = s * 0.36
        let eyeY = rect.minY + s * 0.42
        head.setFill()
        NSBezierPath(roundedRect: headRect, xRadius: s * 0.3, yRadius: s * 0.3).fill()
        for x in [rect.minX + s * 0.06, rect.maxX - s * 0.06 - eyeSize] {
            let outer = CGRect(x: x, y: eyeY, width: eyeSize, height: eyeSize)
            head.setFill()
            NSBezierPath(ovalIn: outer).fill()
            eye.setFill()
            NSBezierPath(ovalIn: outer.insetBy(dx: eyeSize * 0.18, dy: eyeSize * 0.18)).fill()
            if let pupil {
                pupil.setFill()
                NSBezierPath(ovalIn: outer.insetBy(dx: eyeSize * 0.33, dy: eyeSize * 0.33).offsetBy(dx: 0, dy: -eyeSize * 0.04)).fill()
            }
        }
    }

    /// Template image for the menu bar: frog silhouette with see-through eyes.
    static var menuBarIcon: NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            frog(in: rect.insetBy(dx: 1, dy: 2), head: .black, eye: .clear, pupil: .black)
            // Punch the eye whites out so the template shows them as holes.
            NSGraphicsContext.current?.compositingOperation = .clear
            let s = rect.insetBy(dx: 1, dy: 2).width, eye = s * 0.36
            for x in [1 + s * 0.06, rect.maxX - 1 - s * 0.06 - eye] {
                let outer = CGRect(x: x, y: 2 + s * 0.42, width: eye, height: eye)
                NSBezierPath(ovalIn: outer.insetBy(dx: eye * 0.2, dy: eye * 0.2)).fill()
            }
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            NSColor.black.setFill()
            for x in [1 + s * 0.06, rect.maxX - 1 - s * 0.06 - eye] {
                let outer = CGRect(x: x, y: 2 + s * 0.42, width: eye, height: eye)
                NSBezierPath(ovalIn: outer.insetBy(dx: eye * 0.36, dy: eye * 0.36)).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    /// The menu bar frog with a small dot, shown while an update is ready to install.
    static var menuBarIconWithBadge: NSImage {
        let base = menuBarIcon
        let image = NSImage(size: base.size, flipped: false) { rect in
            base.draw(in: rect)
            NSColor.black.setFill()
            NSBezierPath(ovalIn: NSRect(x: rect.maxX - 6.5, y: rect.maxY - 6.5, width: 6.5, height: 6.5)).fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    /// The app mark at any size; the same artwork as the app icon (scripts/make-icon.swift uses this too).
    static func appMark(size: CGFloat, inset: Bool = false) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            let ctx = NSGraphicsContext.current!.cgContext
            // Artwork is laid out on the 824pt squircle of a 1024pt icon canvas.
            let canvas: CGFloat = inset ? 1024 : 824
            ctx.scaleBy(x: size / canvas, y: size / canvas)
            if !inset { ctx.translateBy(x: -100, y: -100) }
            drawIcon(shadow: inset)
            return true
        }
    }

    static func drawIcon(shadow: Bool) {
        let ink = NSColor(srgbRed: 0.05, green: 0.16, blue: 0.12, alpha: 1)
        let shape = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 186, yRadius: 186)
        if shadow {
            NSGraphicsContext.saveGraphicsState()
            let s = NSShadow()
            s.shadowColor = NSColor.black.withAlphaComponent(0.28)
            s.shadowBlurRadius = 28
            s.shadowOffset = NSSize(width: 0, height: -14)
            s.set()
            NSColor.black.setFill()
            shape.fill()
            NSGraphicsContext.restoreGraphicsState()
        }
        NSGradient(colors: [Theme.brand, Theme.brandDeep])!.draw(in: shape, angle: -70)
        NSColor.white.setFill()
        NSBezierPath(roundedRect: NSRect(x: 222, y: 250, width: 580, height: 400), xRadius: 200, yRadius: 200).fill()
        for x: CGFloat in [232, 572] {
            let eye = NSRect(x: x, y: 520, width: 220, height: 220)
            NSColor.white.setFill(); NSBezierPath(ovalIn: eye).fill()
            ink.setFill(); NSBezierPath(ovalIn: eye.insetBy(dx: 62, dy: 62).offsetBy(dx: 8, dy: -6)).fill()
            NSColor.white.setFill(); NSBezierPath(ovalIn: NSRect(x: eye.midX - 6, y: eye.midY + 10, width: 26, height: 26)).fill()
        }
        let config = NSImage.SymbolConfiguration(pointSize: 210, weight: .bold).applying(.init(paletteColors: [Theme.brandDeep]))
        if let arrows = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil)?
            .withSymbolConfiguration(config) {
            let s = arrows.size
            arrows.draw(in: NSRect(x: 512 - s.width / 2, y: 395 - s.height / 2, width: s.width, height: s.height))
        }
    }
}
