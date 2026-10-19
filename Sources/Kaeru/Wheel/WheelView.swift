import AppKit

/// Draws the radial menu and turns drops, clicks and arrow keys into a chosen operation.
/// The frosted-glass backdrop is a separate NSVisualEffectView masked to the ring (see WheelController).
final class WheelView: NSView {
    private var items: [FileOperation] = []
    private var urls: [URL] = []
    private var mode: WheelMode = .convert
    private var interactive = false
    private var thumbnail: NSImage?
    /// Index of the highlighted slice; -1 is the centre (cancel), nil is nothing.
    private var hovered: Int?

    static let pop: CGFloat = 5
    /// Room under the disc for the caption capsule ("Convert photo.heic to PNG").
    static let captionHeight: CGFloat = 50
    /// Rim of base disc around the tiles, and the gap between neighbouring tiles.
    private static let rim: CGFloat = 9, gap: CGFloat = 7, corner: CGFloat = 16

    static func radii(forItems n: Int) -> (inner: CGFloat, mid: CGFloat, outer: CGFloat) {
        // ~92pt of arc per tile keeps two-word labels readable; the hole fits the centre pill.
        let mid = max(126, CGFloat(n) * 92 / (2 * .pi))
        return (mid - 54, mid, mid + 56)
    }

    static func diameter(forItems n: Int) -> CGFloat { (radii(forItems: n).outer + rim + pop) * 2 }

    /// Window size for a wheel whose busiest mode has `n` items; the disc sits above the caption.
    static func size(forItems n: Int) -> NSSize {
        let side = diameter(forItems: n) + 40
        return NSSize(width: side, height: side + captionHeight)
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    func configure(urls: [URL], mode: WheelMode, items: [FileOperation], interactive: Bool) {
        self.urls = urls
        self.mode = mode
        self.items = items
        self.interactive = interactive
        if let h = hovered, h >= items.count { hovered = nil }
        if interactive && hovered == nil && !items.isEmpty { hovered = 0 }
        needsDisplay = true
    }

    func setThumbnail(_ image: NSImage?) {
        thumbnail = image
        needsDisplay = true
    }

    /// Ring plus centre disc, used to mask the glass backdrop.
    func backdropMask() -> NSImage {
        let g = geometry
        return NSImage(size: bounds.size, flipped: false) { _ in
            NSColor.black.setFill()
            NSBezierPath(ovalIn: self.circle(g.outer + Self.rim)).fill()
            return true
        }
    }

    // MARK: Geometry

    /// Disc centre: the middle of the top square of the view, leaving the caption strip below.
    private var center: NSPoint { NSPoint(x: bounds.midX, y: Self.captionHeight + bounds.width / 2) }
    private var geometry: (inner: CGFloat, mid: CGFloat, outer: CGFloat) { Self.radii(forItems: items.count) }
    private var step: CGFloat { 2 * .pi / CGFloat(max(items.count, 1)) }
    private func startAngle(_ i: Int) -> CGFloat { .pi / 2 - CGFloat(i) * step }  // clockwise from 12 o'clock
    private func circle(_ r: CGFloat) -> NSRect { NSRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2) }

    private func slice(at point: NSPoint) -> Int? {
        let dx = point.x - center.x, dy = point.y - center.y
        let r = hypot(dx, dy)
        let g = geometry
        if r < g.inner { return -1 }
        guard r <= g.outer + 16, !items.isEmpty else { return nil }
        var theta = .pi / 2 - atan2(dy, dx)
        if theta < 0 { theta += 2 * .pi }
        return min(Int(theta / step), items.count - 1)
    }

    private func setHovered(_ value: Int?) {
        guard value != hovered else { return }
        hovered = value
        if value != nil && value != -1 { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
        needsDisplay = true
    }

    fileprivate func setHoveredForDebug(_ index: Int) { hovered = index; needsDisplay = true }

    private var isDark: Bool { effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }

    // MARK: Drawing

    private var accent: NSColor { [Theme.brand, Theme.Category.tool.color, Theme.Category.action.color][mode.rawValue] }

    override func draw(_ dirtyRect: NSRect) {
        let g = geometry
        drawBase(radius: g.outer + Self.rim)
        for i in items.indices where i != hovered { drawTile(i, highlighted: false) }
        if let h = hovered, items.indices.contains(h) { drawTile(h, highlighted: true) }
        drawCenter(radius: g.inner - Self.gap)
        drawCaption(below: g.outer + Self.rim)
    }

    /// The soft disc the tiles sit in: a pale, slightly translucent plate over the glass blur.
    private func drawBase(radius: CGFloat) {
        let disc = NSBezierPath(ovalIn: circle(radius))
        let top = isDark ? NSColor(white: 0.16, alpha: 0.82) : NSColor(white: 0.97, alpha: 0.82)
        let bottom = isDark ? NSColor(white: 0.1, alpha: 0.86) : NSColor(white: 0.91, alpha: 0.86)
        NSGradient(starting: top, ending: bottom)?.draw(in: disc, angle: -90)
        (isDark ? NSColor(white: 1, alpha: 0.08) : NSColor(white: 0, alpha: 0.07)).setStroke()
        disc.lineWidth = 1
        disc.stroke()
    }

    /// A rounded annular tile with parallel gaps to its neighbours, like a pillow on the plate.
    private func tilePath(_ i: Int, outer ro: CGFloat) -> NSBezierPath {
        let ri = geometry.inner
        let h = Self.gap / 2, rc = Self.corner
        let a0 = startAngle(i), a1 = startAngle(i + 1)  // clockwise: a0 > a1
        if items.count == 1 {
            let ring = NSBezierPath(ovalIn: circle(ro))
            ring.append(NSBezierPath(ovalIn: circle(ri)).reversed)
            return ring
        }
        // Corner angles, offset so each edge runs parallel to the radial line at distance h.
        let os = a0 - asin(h / ro), oe = a1 + asin(h / ro)
        let ins = a0 - asin(h / ri), ine = a1 + asin(h / ri)
        func p(_ r: CGFloat, _ a: CGFloat) -> CGPoint { CGPoint(x: center.x + r * cos(a), y: center.y + r * sin(a)) }
        // Direction of travel along a circle at angle a: clockwise (decreasing angle) or counter-clockwise.
        func along(_ q: CGPoint, _ a: CGFloat, clockwise: Bool, _ d: CGFloat) -> CGPoint {
            clockwise ? CGPoint(x: q.x + sin(a) * d, y: q.y - cos(a) * d) : CGPoint(x: q.x - sin(a) * d, y: q.y + cos(a) * d)
        }
        let path = CGMutablePath()
        let outerStart = p(ro, os), outerEnd = p(ro, oe), innerEnd = p(ri, ine), innerStart = p(ri, ins)
        let rci = rc * 0.75
        path.move(to: CGPoint(x: (outerStart.x + innerStart.x) / 2, y: (outerStart.y + innerStart.y) / 2))
        // Each corner is rounded against the true tangent of its circle, then the arc picks up where the rounding ends.
        path.addArc(tangent1End: outerStart, tangent2End: along(outerStart, os, clockwise: true, rc * 4), radius: rc)
        path.addArc(center: center, radius: ro, startAngle: os - rc / ro, endAngle: oe + rc / ro, clockwise: true)
        path.addArc(tangent1End: outerEnd, tangent2End: innerEnd, radius: rc)
        path.addArc(tangent1End: innerEnd, tangent2End: along(innerEnd, ine, clockwise: false, rci * 4), radius: rci)
        path.addArc(center: center, radius: ri, startAngle: ine + rci / ri, endAngle: ins - rci / ri, clockwise: false)
        path.addArc(tangent1End: innerStart, tangent2End: outerStart, radius: rci)
        path.closeSubpath()
        return NSBezierPath(path)
    }

    /// The colour a tile lights up in: its format's category on the Convert wheel, the mode's colour otherwise.
    private func tint(_ op: FileOperation) -> NSColor { Theme.color(for: op, mode: mode) }

    /// A format's category symbol for Convert tiles.
    private func symbol(for op: FileOperation) -> String {
        guard mode == .convert else { return op.symbol }
        switch Theme.category(forExt: op.targetExt ?? "") {
        case .image: return "photo"
        case .video: return "film"
        case .audio: return "waveform"
        case .pdf: return "doc.richtext"
        case .document: return "doc.text"
        case .spreadsheet: return "tablecells"
        case .slides: return "rectangle.on.rectangle"
        case .data: return "curlybraces"
        default: return "archivebox"
        }
    }

    private func drawTile(_ i: Int, highlighted: Bool) {
        let g = geometry
        let item = items[i]
        let color = tint(item)
        let path = tilePath(i, outer: highlighted ? g.outer + Self.pop : g.outer)
        let angle = startAngle(i) - step / 2
        let labelPoint = NSPoint(x: center.x + g.mid * cos(angle), y: center.y + g.mid * sin(angle))

        // Resting tiles are quiet glass; the hovered one fills with its own colour and glows.
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = highlighted ? color.withAlphaComponent(0.55) : NSColor.black.withAlphaComponent(isDark ? 0.25 : 0.05)
        shadow.shadowBlurRadius = highlighted ? 20 : 2
        shadow.shadowOffset = NSSize(width: 0, height: highlighted ? -3 : -1)
        shadow.set()
        (highlighted ? color : (isDark ? NSColor(white: 1, alpha: 0.06) : NSColor(white: 1, alpha: 0.78))).setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        if highlighted {
            let top = color.blended(withFraction: 0.22, of: .white)!, bottom = color.blended(withFraction: 0.18, of: .black)!
            NSGradient(starting: top, ending: bottom)?.draw(in: path, angle: -90)
        } else {
            // A faint sheen from the top, like light on glass.
            let sheen = NSColor(white: 1, alpha: isDark ? 0.05 : 0.5)
            NSGradient(starting: sheen, ending: NSColor(white: 1, alpha: 0))?.draw(in: path, angle: -90)
        }
        NSGraphicsContext.restoreGraphicsState()

        (highlighted ? NSColor(white: 1, alpha: 0.3) : (isDark ? NSColor(white: 1, alpha: 0.09) : NSColor(white: 0, alpha: 0.07))).setStroke()
        path.lineWidth = 1
        path.stroke()

        let ink = highlighted ? NSColor.white : NSColor.labelColor
        let soft = highlighted ? NSColor(white: 1, alpha: 0.8) : NSColor.secondaryLabelColor
        // Usable width: the chord across the tile at mid radius, minus the gaps and some padding.
        let width = min(2 * g.mid * sin(step / 2) - Self.gap - 14, 112)
        if mode == .convert {
            // Icon in the format's colour, the format name, and a few words on what it's good for.
            let caption = hint(for: item)
            let symbolHeight: CGFloat = 18, spacing: CGFloat = 4
            let nameSize: CGFloat = 15, captionSize: CGFloat = 9.5
            let block = symbolHeight + spacing + nameSize * 1.2 + (caption == nil ? 0 : captionSize * 1.3 + 1)
            let top = labelPoint.y + block / 2
            drawSymbol(symbol(for: item), at: NSPoint(x: labelPoint.x, y: top - symbolHeight / 2),
                       color: highlighted ? .white : color, size: 15)
            let nameY = top - symbolHeight - spacing - nameSize * 0.6
            drawFitted(item.title.uppercased(), centeredAt: NSPoint(x: labelPoint.x, y: nameY), maxWidth: width,
                       size: nameSize, minSize: 10.5, weight: .semibold, color: ink, kern: 0.6)
            if let caption {
                drawText(caption, at: NSPoint(x: labelPoint.x, y: nameY - nameSize * 0.6 - captionSize * 1.35 - 1), size: captionSize,
                         weight: .medium, color: soft, width: width + 6)
            }
        } else {
            let text = layoutFitted(item.title, maxWidth: width, size: 12, minSize: 9.5, weight: .semibold)
            let symbolHeight: CGFloat = 20, spacing: CGFloat = 5
            let blockTop = labelPoint.y + (symbolHeight + spacing + text.height) / 2
            drawSymbol(symbol(for: item), at: NSPoint(x: labelPoint.x, y: blockTop - symbolHeight / 2),
                       color: highlighted ? .white : color, size: 17)
            drawFitted(item.title, centeredAt: NSPoint(x: labelPoint.x, y: blockTop - symbolHeight - spacing - text.height / 2),
                       maxWidth: width, size: 12, minSize: 9.5, weight: .semibold, color: ink)
        }
    }

    /// How `text` will be set within `maxWidth`: one line, shrunk if needed, else two balanced lines.
    private func layoutFitted(_ text: String, maxWidth: CGFloat, size: CGFloat, minSize: CGFloat,
                              weight: NSFont.Weight, kern: CGFloat = 0) -> (lines: [String], size: CGFloat, height: CGFloat) {
        func width(_ s: String, _ pt: CGFloat) -> CGFloat {
            (s as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: pt, weight: weight), .kern: kern]).width
        }
        // Shrink a little on one line first: it reads best.
        var pt = size
        while pt > max(minSize, size * 0.85) && width(text, pt) > maxWidth { pt -= 0.5 }
        if width(text, pt) <= maxWidth { return ([text], pt, pt * 1.2) }
        // Otherwise wrap at the space that best balances the two lines.
        let words = text.split(separator: " ").map(String.init)
        if words.count > 1 {
            let splits = (1..<words.count).map { i in (words[..<i].joined(separator: " "), words[i...].joined(separator: " ")) }
            let best = splits.min { max(width($0.0, size), width($0.1, size)) < max(width($1.0, size), width($1.1, size)) }!
            pt = size
            while pt > minSize && max(width(best.0, pt), width(best.1, pt)) > maxWidth { pt -= 0.5 }
            return ([best.0, best.1], pt, pt * 2.3)
        }
        while pt > minSize && width(text, pt) > maxWidth { pt -= 0.5 }
        return ([text], pt, pt * 1.2)
    }

    private func drawFitted(_ text: String, centeredAt p: NSPoint, maxWidth: CGFloat, size: CGFloat, minSize: CGFloat,
                            weight: NSFont.Weight, color: NSColor, kern: CGFloat = 0) {
        let layout = layoutFitted(text, maxWidth: maxWidth, size: size, minSize: minSize, weight: weight, kern: kern)
        let lineHeight = layout.height / CGFloat(layout.lines.count)
        for (i, line) in layout.lines.enumerated() {
            let y = p.y + layout.height / 2 - lineHeight * CGFloat(i + 1)
            drawText(line, at: NSPoint(x: p.x, y: y), size: layout.size, weight: weight, color: color, width: maxWidth + 8, kern: kern)
        }
    }

    private func drawSymbol(_ name: String, at p: NSPoint, color: NSColor, size: CGFloat = 17) {
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: .medium).applying(.init(paletteColors: [color]))
        guard let symbol = (NSImage(systemSymbolName: name, accessibilityDescription: nil)
            ?? NSImage(systemSymbolName: "circle", accessibilityDescription: nil))?.withSymbolConfiguration(config) else { return }
        let s = symbol.size
        symbol.draw(in: NSRect(x: p.x - s.width / 2, y: p.y - s.height / 2, width: s.width, height: s.height))
    }

    private func drawText(_ text: String, at p: NSPoint, size: CGFloat, weight: NSFont.Weight, color: NSColor, width: CGFloat,
                          kern: CGFloat = 0) {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byTruncatingTail
        (text as NSString).draw(in: NSRect(x: p.x - width / 2, y: p.y, width: width, height: size + 6), withAttributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: style, .kern: kern,
        ])
    }

    /// The hole in the middle: a pill naming the current choice (or the file, at rest), and the
    /// three wheels as small icons, the current one lit.
    private func drawCenter(radius r: CGFloat) {
        let hoveredItem = hovered.flatMap { items.indices.contains($0) ? items[$0] : nil }
        let label: String
        var ink = NSColor.labelColor
        var leading: (symbol: String, color: NSColor)?
        var showThumb = false
        if hovered == -1 {
            label = "Cancel"; ink = .secondaryLabelColor; leading = ("xmark", .systemRed)
        } else if let op = hoveredItem {
            label = mode == .convert ? "to " + op.title.uppercased() : op.title
            leading = (symbol(for: op), tint(op))
        } else {
            label = items.isEmpty ? "Nothing here" : mode.title
            ink = .secondaryLabelColor
            showThumb = thumbnail != nil && !items.isEmpty
        }

        let font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        let iconWidth: CGFloat = (leading != nil || showThumb) ? 22 : 0
        let textWidth = (label as NSString).size(withAttributes: [.font: font]).width
        let pillWidth = min(max(textWidth + iconWidth + 32, 96), r * 2 - 12)
        let pill = NSRect(x: center.x - pillWidth / 2, y: center.y - 8, width: pillWidth, height: 34)
        let path = NSBezierPath(roundedRect: pill, xRadius: 17, yRadius: 17)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(isDark ? 0.4 : 0.1)
        shadow.shadowBlurRadius = 10
        shadow.shadowOffset = NSSize(width: 0, height: -2)
        shadow.set()
        (isDark ? NSColor(white: 0.2, alpha: 1) : .white).setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()
        (isDark ? NSColor(white: 1, alpha: 0.08) : NSColor(white: 0, alpha: 0.06)).setStroke()
        path.lineWidth = 1
        path.stroke()

        let fit = layoutFitted(label, maxWidth: pillWidth - 26 - iconWidth, size: 14, minSize: 10, weight: .semibold)
        let one = fit.lines.count == 1 ? fit.lines[0] : label
        let size = fit.lines.count == 1 ? fit.size : 10
        let drawnWidth = (one as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: .semibold)]).width
        let contentWidth = min(drawnWidth, pillWidth - 26 - iconWidth) + iconWidth
        let startX = center.x - contentWidth / 2
        if let leading {
            drawSymbol(leading.symbol, at: NSPoint(x: startX + 8, y: pill.midY), color: leading.color, size: 13)
        } else if showThumb, let thumbnail {
            thumbnail.draw(in: NSRect(x: startX, y: pill.midY - 9, width: 18, height: 18), from: .zero, operation: .sourceOver, fraction: 1)
        }
        drawText(one, at: NSPoint(x: startX + iconWidth + drawnWidth / 2, y: pill.midY - size * 0.62), size: size,
                 weight: .semibold, color: ink, width: drawnWidth + 8)

        // The three wheels as icons under the pill; the key that opens each is shown when interactive.
        let modes = WheelMode.allCases
        let w: CGFloat = 28, h: CGFloat = 22, spacing: CGFloat = 4
        let total = CGFloat(modes.count) * w + CGFloat(modes.count - 1) * spacing
        for (i, m) in modes.enumerated() {
            let rect = NSRect(x: center.x - total / 2 + CGFloat(i) * (w + spacing), y: pill.minY - 30, width: w, height: h)
            let modeColor = [Theme.brand, Theme.Category.tool.color, Theme.Category.action.color][m.rawValue]
            if m == mode {
                modeColor.withAlphaComponent(isDark ? 0.22 : 0.15).setFill()
                NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7).fill()
            }
            drawSymbol(m.symbol, at: NSPoint(x: rect.midX, y: rect.midY), color: m == mode ? modeColor : .tertiaryLabelColor, size: 12)
        }
        let hint = interactive ? "1 · 2 · 3 to switch" : modes.map { Settings.modifier(for: $0).glyph }.joined(separator: "  ")
        drawText(hint, at: NSPoint(x: center.x, y: pill.minY - 48), size: 9, weight: .medium, color: .tertiaryLabelColor, width: r * 2 - 20)
    }

    /// "Convert photo.heic to PNG" in a small capsule under the disc, with the file's thumbnail.
    private func drawCaption(below radius: CGFloat) {
        let hoveredItem = hovered.flatMap { items.indices.contains($0) ? items[$0] : nil }
        let name = urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) items"
        let text: String
        if hovered == -1 { text = "Drop here to cancel" }
        else if let op = hoveredItem {
            switch mode {
            case .convert: text = "Convert \(name) to \(op.title.uppercased())"
            case .tools, .actions: text = "\(op.title) · \(name)"
            }
        } else { text = name }

        let font = NSFont.systemFont(ofSize: 12, weight: .medium)
        let textWidth = min((text as NSString).size(withAttributes: [.font: font]).width, bounds.width - 80)
        let thumb: CGFloat = thumbnail == nil ? 0 : 20
        let width = textWidth + thumb + (thumb > 0 ? 8 : 0) + 26
        let rect = NSRect(x: center.x - width / 2, y: center.y - radius - Self.pop - 38, width: width, height: 30)
        let capsule = NSBezierPath(roundedRect: rect, xRadius: 15, yRadius: 15)
        (isDark ? NSColor(white: 0.14, alpha: 0.92) : NSColor(white: 1, alpha: 0.92)).setFill()
        capsule.fill()
        (isDark ? NSColor(white: 1, alpha: 0.08) : NSColor(white: 0, alpha: 0.08)).setStroke()
        capsule.lineWidth = 1
        capsule.stroke()
        if let thumbnail, thumb > 0 {
            thumbnail.draw(in: NSRect(x: rect.minX + 11, y: rect.midY - thumb / 2, width: thumb, height: thumb),
                           from: .zero, operation: .sourceOver, fraction: 1)
        }
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingMiddle
        (text as NSString).draw(in: NSRect(x: rect.minX + 13 + thumb + (thumb > 0 ? 6 : 0), y: rect.minY + 7, width: textWidth + 2, height: 17),
                                withAttributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: style])
    }

    private func hint(for op: FileOperation) -> String? {
        guard let ext = op.targetExt else { return nil }
        let hints = ["jpg": "universal", "png": "lossless", "heic": "small, Apple", "webp": "small, web",
                     "avif": "smallest", "pdf": "document", "mp4": "universal", "mov": "Apple devices", "gif": "animated",
                     "mp3": "universal", "wav": "lossless", "flac": "lossless", "docx": "Word", "md": "plain text",
                     "xlsx": "Excel", "pptx": "PowerPoint", "epub": "e-book", "zip": "archive", "ico": "Windows icon", "icns": "macOS icon",
                     "txt": "just text", "html": "web page", "rtf": "rich text", "odt": "LibreOffice", "ods": "LibreOffice",
                     "bmp": "uncompressed", "tiff": "print quality", "csv": "any app", "tsv": "tab separated", "json": "data",
                     "m4a": "Apple audio", "aac": "small audio", "ogg": "open audio", "opus": "small, speech", "aiff": "lossless",
                     "webm": "web video", "mkv": "any player", "avi": "older players", "pages": "Pages", "plist": "Apple data",
                     "srt": "subtitles", "vtt": "web subtitles"]
        return hints[ext]
    }

    // MARK: Drag and drop

    private func operation(for info: NSDraggingInfo) -> NSDragOperation {
        let mask = info.draggingSourceOperationMask
        return [NSDragOperation.copy, .generic, .link, .move].first { mask.contains($0) } ?? .copy
    }

    override func draggingEntered(_ info: NSDraggingInfo) -> NSDragOperation {
        setHovered(slice(at: convert(info.draggingLocation, from: nil)))
        return operation(for: info)
    }

    override func draggingUpdated(_ info: NSDraggingInfo) -> NSDragOperation {
        setHovered(slice(at: convert(info.draggingLocation, from: nil)))
        return operation(for: info)
    }

    override func draggingExited(_ info: NSDraggingInfo?) { setHovered(nil) }

    override func prepareForDragOperation(_ info: NSDraggingInfo) -> Bool { true }

    override func performDragOperation(_ info: NSDraggingInfo) -> Bool {
        let index = slice(at: convert(info.draggingLocation, from: nil))
        guard let index, items.indices.contains(index) else {
            Task { @MainActor in WheelController.shared.hide() }
            return false
        }
        let dropped = info.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                                          options: [.urlReadingFileURLsOnly: true]) as? [URL]
        let op = items[index]
        // Let the drag session finish before running, so Finder isn't left waiting.
        DispatchQueue.main.async { WheelController.shared.perform(op, on: dropped) }
        return true
    }

    // MARK: Mouse and keyboard (interactive mode)

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        guard interactive else { return }
        if let s = slice(at: convert(event.locationInWindow, from: nil)) { setHovered(s) }
    }

    override func mouseDown(with event: NSEvent) {
        let s = slice(at: convert(event.locationInWindow, from: nil))
        if let s, items.indices.contains(s) {
            WheelController.shared.perform(items[s])
        } else {
            WheelController.shared.hide()
        }
    }

    override func rightMouseDown(with event: NSEvent) { WheelController.shared.hide() }

    override func keyDown(with event: NSEvent) {
        let wheel = WheelController.shared
        switch event.keyCode {
        case 53: wheel.hide()                                         // esc
        case 36, 76:                                                  // return, enter
            if let h = hovered, items.indices.contains(h) { wheel.perform(items[h]) }
        case 123, 126: moveHover(by: -1)                              // left, up
        case 124, 125: moveHover(by: 1)                               // right, down
        case 48: wheel.cycleMode(by: event.modifierFlags.contains(.shift) ? -1 : 1)  // tab
        default:
            if let n = Int(event.charactersIgnoringModifiers ?? ""), let m = WheelMode(rawValue: n - 1) {
                wheel.setMode(m)
            } else {
                super.keyDown(with: event)
            }
        }
    }

    private func moveHover(by delta: Int) {
        guard !items.isEmpty else { return }
        let current = hovered.flatMap { $0 >= 0 ? $0 : nil } ?? (delta > 0 ? -1 : 0)
        setHovered((current + delta + items.count) % items.count)
    }
}

extension WheelView {
    /// For `--render-wheel` design checks: highlight a slice without a mouse.
    func debugHover(_ index: Int) { setHoveredForDebug(index) }
}

private extension NSBezierPath {
    /// NSBezierPath(cgPath:) needs macOS 14; this copies the elements on any version.
    convenience init(_ cgPath: CGPath) {
        self.init()
        cgPath.applyWithBlock { element in
            let p = element.pointee.points
            switch element.pointee.type {
            case .moveToPoint: move(to: p[0])
            case .addLineToPoint: line(to: p[0])
            case .addQuadCurveToPoint:
                let start = currentPoint
                curve(to: p[1], controlPoint1: CGPoint(x: start.x + 2 / 3 * (p[0].x - start.x), y: start.y + 2 / 3 * (p[0].y - start.y)),
                      controlPoint2: CGPoint(x: p[1].x + 2 / 3 * (p[0].x - p[1].x), y: p[1].y + 2 / 3 * (p[0].y - p[1].y)))
            case .addCurveToPoint: curve(to: p[2], controlPoint1: p[0], controlPoint2: p[1])
            case .closeSubpath: close()
            @unknown default: break
            }
        }
    }
}
