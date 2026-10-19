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

    static let pop: CGFloat = 7

    static func radii(forItems n: Int) -> (inner: CGFloat, mid: CGFloat, outer: CGFloat) {
        let mid = max(112, CGFloat(n) * 72 / (2 * .pi))
        return (mid - 52, mid, mid + 52)
    }

    static func diameter(forItems n: Int) -> CGFloat { (radii(forItems: n).outer + pop) * 2 }

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
            NSBezierPath(ovalIn: self.circle(g.outer)).fill()
            return true
        }
    }

    // MARK: Geometry

    private var center: NSPoint { NSPoint(x: bounds.midX, y: bounds.midY) }
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

    private var isDark: Bool { effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        let g = geometry
        // A light tint over the glass keeps labels readable on busy wallpapers.
        (isDark ? NSColor(white: 0.08, alpha: 0.55) : NSColor(white: 1, alpha: 0.55)).setFill()
        NSBezierPath(ovalIn: circle(g.outer)).fill()

        for i in items.indices where i != hovered { drawSlice(i, highlighted: false) }
        if let h = hovered, items.indices.contains(h) { drawSlice(h, highlighted: true) }

        NSColor.separatorColor.withAlphaComponent(0.6).setStroke()
        let rim = NSBezierPath(ovalIn: circle(g.outer).insetBy(dx: 0.5, dy: 0.5))
        rim.lineWidth = 1
        rim.stroke()

        drawCenter(radius: g.inner - 6)
    }

    private func slicePath(_ i: Int, outer: CGFloat) -> NSBezierPath {
        let g = geometry
        let gap: CGFloat = items.count > 1 ? 0.012 : 0
        let a0 = (startAngle(i) - gap) * 180 / .pi, a1 = (startAngle(i + 1) + gap) * 180 / .pi
        let path = NSBezierPath()
        if items.count == 1 {
            path.appendOval(in: circle(outer))
            path.appendOval(in: circle(g.inner))
            path.windingRule = .evenOdd
            return path
        }
        path.appendArc(withCenter: center, radius: outer, startAngle: a0, endAngle: a1, clockwise: true)
        path.appendArc(withCenter: center, radius: g.inner + 2, startAngle: a1, endAngle: a0, clockwise: false)
        path.close()
        return path
    }

    private func drawSlice(_ i: Int, highlighted: Bool) {
        let g = geometry
        let item = items[i]
        let tint = Theme.color(for: item, mode: mode)
        let path = slicePath(i, outer: highlighted ? g.outer + Self.pop : g.outer - 2)
        if highlighted {
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = tint.withAlphaComponent(0.55)
            shadow.shadowBlurRadius = 14
            shadow.set()
            tint.setFill()
            path.fill()
            NSGraphicsContext.restoreGraphicsState()
        } else {
            (isDark ? NSColor(white: 1, alpha: 0.04) : NSColor(white: 0, alpha: 0.025)).setFill()
            path.fill()
        }

        let angle = startAngle(i) - step / 2
        let r = g.mid + (highlighted ? Self.pop / 2 : 0)
        let p = NSPoint(x: center.x + r * cos(angle), y: center.y + r * sin(angle))
        if mode == .convert {
            drawBadge(item.title, at: NSPoint(x: p.x, y: p.y + 6), tint: tint, inverted: highlighted)
            if let sub = subtitle(for: item) {
                drawText(sub, at: NSPoint(x: p.x, y: p.y - 18), size: 9.5, weight: .medium,
                         color: highlighted ? .white.withAlphaComponent(0.85) : .secondaryLabelColor, width: 80)
            }
        } else {
            drawSymbol(item.symbol, at: NSPoint(x: p.x, y: p.y + 9), tint: tint, inverted: highlighted)
            drawText(item.title, at: NSPoint(x: p.x, y: p.y - 21), size: 10.5, weight: .semibold,
                     color: highlighted ? .white : .labelColor, width: min(2 * r * sin(step / 2) * 0.92, 94))
        }
    }

    /// A short hint under format badges, e.g. "Smaller" for WebP.
    private func subtitle(for op: FileOperation) -> String? {
        guard let ext = op.targetExt else { return nil }
        let hints = ["jpg": "Universal", "png": "Lossless", "heic": "Apple", "webp": "Web", "avif": "Smallest",
                     "pdf": "Document", "mp4": "Universal", "mov": "Apple", "gif": "Animated", "mp3": "Audio",
                     "m4a": "Audio", "wav": "Lossless", "flac": "Lossless", "docx": "Word", "md": "Text",
                     "xlsx": "Excel", "csv": "Plain", "zip": "Archive", "pptx": "Slides", "epub": "E-book"]
        return hints[ext]
    }

    private func drawBadge(_ text: String, at p: NSPoint, tint: NSColor, inverted: Bool) {
        let font = NSFont.systemFont(ofSize: text.count > 5 ? 10.5 : 12.5, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: inverted ? tint : NSColor.white]
        let size = (text as NSString).size(withAttributes: attrs)
        let rect = NSRect(x: p.x - size.width / 2 - 9, y: p.y - 11, width: size.width + 18, height: 22)
        (inverted ? NSColor.white : tint).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7).fill()
        (text as NSString).draw(at: NSPoint(x: rect.minX + 9, y: rect.midY - size.height / 2), withAttributes: attrs)
    }

    private func drawSymbol(_ name: String, at p: NSPoint, tint: NSColor, inverted: Bool) {
        let disc = NSRect(x: p.x - 16, y: p.y - 16, width: 32, height: 32)
        (inverted ? NSColor.white : tint).setFill()
        NSBezierPath(ovalIn: disc).fill()
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
            .applying(.init(paletteColors: [inverted ? tint : .white]))
        guard let symbol = (NSImage(systemSymbolName: name, accessibilityDescription: nil)
            ?? NSImage(systemSymbolName: "circle", accessibilityDescription: nil))?.withSymbolConfiguration(config) else { return }
        let s = symbol.size
        symbol.draw(in: NSRect(x: p.x - s.width / 2, y: p.y - s.height / 2, width: s.width, height: s.height))
    }

    private func drawText(_ text: String, at p: NSPoint, size: CGFloat, weight: NSFont.Weight, color: NSColor, width: CGFloat) {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byTruncatingTail
        (text as NSString).draw(in: NSRect(x: p.x - width / 2, y: p.y, width: width, height: size + 5), withAttributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: style,
        ])
    }

    private func drawCenter(radius r: CGFloat) {
        let disc = NSBezierPath(ovalIn: circle(r))
        (isDark ? NSColor(white: 0.13, alpha: 0.92) : NSColor(white: 1, alpha: 0.92)).setFill()
        disc.fill()
        if hovered == -1 {
            NSColor.systemRed.withAlphaComponent(0.12).setFill()
            disc.fill()
        }
        NSColor.separatorColor.setStroke()
        disc.lineWidth = 1
        disc.stroke()

        // File thumbnail.
        let thumbSize: CGFloat = 34
        if let thumbnail {
            thumbnail.draw(in: NSRect(x: center.x - thumbSize / 2, y: center.y + 12, width: thumbSize, height: thumbSize),
                           from: .zero, operation: .sourceOver, fraction: 1)
        }

        let textWidth = r * 2 - 22
        let name = urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) items"
        let hoveredItem = hovered.flatMap { items.indices.contains($0) ? items[$0] : nil }
        if hovered == -1 {
            drawText("Cancel", at: NSPoint(x: center.x, y: center.y - 6), size: 13, weight: .semibold, color: .systemRed, width: textWidth)
        } else if let op = hoveredItem {
            drawText(op.title, at: NSPoint(x: center.x, y: center.y - 6), size: 13, weight: .semibold, color: .labelColor, width: textWidth)
            drawText(preview(for: op), at: NSPoint(x: center.x, y: center.y - 21), size: 9.5, weight: .regular,
                     color: .secondaryLabelColor, width: textWidth)
        } else {
            drawText(items.isEmpty ? "Nothing here" : mode.title, at: NSPoint(x: center.x, y: center.y - 6), size: 13,
                     weight: .semibold, color: .labelColor, width: textWidth)
            drawText(name, at: NSPoint(x: center.x, y: center.y - 21), size: 9.5, weight: .regular,
                     color: .secondaryLabelColor, width: textWidth)
        }
        drawModeSwitcher(y: center.y - r + 12)
    }

    /// "photo.jpg" — what the result will be called.
    private func preview(for op: FileOperation) -> String {
        guard let ext = op.targetExt, urls.count == 1 else { return urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) items" }
        return "→ " + urls[0].deletingPathExtension().lastPathComponent + "." + ext
    }

    private func drawModeSwitcher(y: CGFloat) {
        let modes = WheelMode.allCases
        let w: CGFloat = 20, gap: CGFloat = 4
        let total = CGFloat(modes.count) * w + CGFloat(modes.count - 1) * gap
        for (i, m) in modes.enumerated() {
            let rect = NSRect(x: center.x - total / 2 + CGFloat(i) * (w + gap), y: y, width: w, height: 16)
            let active = m == mode
            if active {
                [Theme.brand, Theme.Category.tool.color, Theme.Category.action.color][m.rawValue].setFill()
                NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
            }
            let glyph = interactive ? "\(i + 1)" : Settings.modifier(for: m).glyph
            drawText(glyph, at: NSPoint(x: rect.midX, y: rect.minY + 1), size: 10, weight: .bold,
                     color: active ? .white : .tertiaryLabelColor, width: w)
        }
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
