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
        let top = isDark ? NSColor(white: 0.17, alpha: 0.9) : NSColor(white: 0.955, alpha: 0.9)
        let bottom = isDark ? NSColor(white: 0.12, alpha: 0.9) : NSColor(white: 0.9, alpha: 0.9)
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

    private func drawTile(_ i: Int, highlighted: Bool) {
        let g = geometry
        let item = items[i]
        let path = tilePath(i, outer: highlighted ? g.outer + Self.pop : g.outer)
        let angle = startAngle(i) - step / 2
        let labelPoint = NSPoint(x: center.x + g.mid * cos(angle), y: center.y + g.mid * sin(angle))

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = highlighted ? accent.withAlphaComponent(0.45) : NSColor.black.withAlphaComponent(isDark ? 0.35 : 0.07)
        shadow.shadowBlurRadius = highlighted ? 16 : 3
        shadow.shadowOffset = NSSize(width: 0, height: highlighted ? -4 : -1)
        shadow.set()
        (highlighted ? accent : (isDark ? NSColor(white: 0.2, alpha: 1) : .white)).setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()

        // Pillow shading: a soft highlight in the middle of the tile fading to its edges.
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        let light = highlighted ? accent.blended(withFraction: 0.25, of: .white)! : (isDark ? NSColor(white: 0.25, alpha: 1) : .white)
        let edge = highlighted ? accent.blended(withFraction: 0.12, of: .black)! : (isDark ? NSColor(white: 0.17, alpha: 1) : NSColor(white: 0.93, alpha: 1))
        NSGradient(starting: light, ending: edge)?.draw(fromCenter: labelPoint, radius: 0, toCenter: labelPoint, radius: 78, options: .drawsAfterEndingLocation)
        NSGraphicsContext.restoreGraphicsState()

        (highlighted ? NSColor(white: 1, alpha: 0.25) : (isDark ? NSColor(white: 1, alpha: 0.07) : NSColor(white: 0, alpha: 0.09))).setStroke()
        path.lineWidth = 1
        path.stroke()

        let ink = highlighted ? NSColor.white : NSColor.labelColor
        // Usable width: the chord across the tile at mid radius, minus the gaps and some padding.
        let width = min(2 * g.mid * sin(step / 2) - Self.gap - 14, 112)
        if mode == .convert {
            drawFitted(item.title.uppercased(), centeredAt: labelPoint, maxWidth: width, size: 16, minSize: 11, weight: .bold,
                       color: ink, kern: 0.4)
        } else {
            let text = layoutFitted(item.title, maxWidth: width, size: 12, minSize: 9.5, weight: .semibold)
            let symbolHeight: CGFloat = 20, spacing: CGFloat = 5
            let blockTop = labelPoint.y + (symbolHeight + spacing + text.height) / 2
            drawSymbol(item.symbol, at: NSPoint(x: labelPoint.x, y: blockTop - symbolHeight / 2),
                       color: highlighted ? .white : .secondaryLabelColor)
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

    private func drawSymbol(_ name: String, at p: NSPoint, color: NSColor) {
        let config = NSImage.SymbolConfiguration(pointSize: 17, weight: .medium).applying(.init(paletteColors: [color]))
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

    /// The hole in the middle holds a floating pill naming the current choice, and the mode keys.
    private func drawCenter(radius r: CGFloat) {
        let hoveredItem = hovered.flatMap { items.indices.contains($0) ? items[$0] : nil }
        let label: String
        let ink: NSColor
        if hovered == -1 { label = "Cancel"; ink = .systemRed }
        else if let op = hoveredItem { label = mode == .convert ? op.title.uppercased() : op.title; ink = .labelColor }
        else { label = items.isEmpty ? "Nothing here" : mode.title; ink = .secondaryLabelColor }

        let font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        let textWidth = (label as NSString).size(withAttributes: [.font: font]).width
        let pillWidth = min(max(textWidth + 36, 92), r * 2 - 8)
        let pill = NSRect(x: center.x - pillWidth / 2, y: center.y - 13, width: pillWidth, height: 40)
        let path = NSBezierPath(roundedRect: pill, xRadius: 20, yRadius: 20)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(isDark ? 0.45 : 0.1)
        shadow.shadowBlurRadius = 12
        shadow.shadowOffset = NSSize(width: 0, height: -3)
        shadow.set()
        (isDark ? NSColor(white: 0.22, alpha: 1) : .white).setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()
        let fit = layoutFitted(label, maxWidth: pillWidth - 22, size: 15, minSize: 10.5, weight: .semibold)
        let one = fit.lines.count == 1 ? fit.lines[0] : label
        drawText(one, at: NSPoint(x: center.x, y: pill.midY - fit.size * 0.62), size: fit.lines.count == 1 ? fit.size : 10.5,
                 weight: .semibold, color: ink, width: pillWidth - 14)

        // Mode keys, small and quiet, under the pill.
        let modes = WheelMode.allCases
        let w: CGFloat = 19, spacing: CGFloat = 5
        let total = CGFloat(modes.count) * w + CGFloat(modes.count - 1) * spacing
        for (i, m) in modes.enumerated() {
            let rect = NSRect(x: center.x - total / 2 + CGFloat(i) * (w + spacing), y: pill.minY - 26, width: w, height: 16)
            if m == mode {
                accent.withAlphaComponent(0.16).setFill()
                NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
            }
            let glyph = interactive ? "\(i + 1)" : Settings.modifier(for: m).glyph
            drawText(glyph, at: NSPoint(x: rect.midX, y: rect.minY + 1), size: 10, weight: .bold,
                     color: m == mode ? accent : .tertiaryLabelColor, width: w)
        }
    }

    /// "Convert photo.heic to PNG" in a small capsule under the disc, with the file's thumbnail.
    private func drawCaption(below radius: CGFloat) {
        let hoveredItem = hovered.flatMap { items.indices.contains($0) ? items[$0] : nil }
        let name = urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) items"
        let text: String
        if hovered == -1 { text = "Drop here to cancel" }
        else if let op = hoveredItem {
            switch mode {
            case .convert: text = "Convert \(name) to \(op.title.uppercased())" + (hint(for: op).map { " · \($0)" } ?? "")
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
        let hints = ["jpg": "works everywhere", "png": "lossless", "heic": "small, Apple devices", "webp": "small, for the web",
                     "avif": "smallest", "pdf": "document", "mp4": "plays everywhere", "mov": "Apple devices", "gif": "animated",
                     "mp3": "plays everywhere", "wav": "lossless", "flac": "lossless", "docx": "Word", "md": "plain text",
                     "xlsx": "Excel", "pptx": "PowerPoint", "epub": "e-book", "zip": "archive", "ico": "Windows icon", "icns": "macOS icon"]
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
