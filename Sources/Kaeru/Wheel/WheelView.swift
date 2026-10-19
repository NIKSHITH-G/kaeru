import AppKit

/// Kaeru's picker: the file sits on a pad in the middle of a little pond, and each choice is a lily
/// pad floating around it. Turns drops, clicks and arrow keys into the chosen operation.
/// The frosted-glass backdrop is a separate NSVisualEffectView masked to the pads (see WheelController).
final class WheelView: NSView {
    private var items: [FileOperation] = []
    private var urls: [URL] = []
    private var mode: WheelMode = .convert
    private var interactive = false
    private var thumbnail: NSImage?
    /// Index of the highlighted slice; -1 is the centre (cancel), nil is nothing.
    private var hovered: Int?

    /// Room around the ring for an aimed pad to swell and ripple.
    static let pop: CGFloat = 18
    /// Room under the pond for the caption capsule ("Convert photo.heic to PNG").
    static let captionHeight: CGFloat = 50
    /// Radius of the file's pad in the middle.
    private static let hub: CGFloat = 62

    /// Pad size and ring radius for `n` pads: pads stay apart, with water between them.
    static func pads(forItems n: Int) -> (pad: CGFloat, ring: CGFloat) {
        let pad: CGFloat = n <= 8 ? 44 : (n <= 11 ? 40 : 36)
        let spacing = pad * 2 + 14
        let ring = max(hub + pad + 22, spacing / (2 * sin(.pi / CGFloat(max(n, 3)))))
        return (pad, ring)
    }

    /// inner: the hub (aiming there cancels); mid: the ring of pad centres; outer: the far edge of the pads.
    static func radii(forItems n: Int) -> (inner: CGFloat, mid: CGFloat, outer: CGFloat) {
        let p = pads(forItems: n)
        return (hub + 6, p.ring, p.ring + p.pad)
    }

    static func diameter(forItems n: Int) -> CGFloat { (radii(forItems: n).outer + pop) * 2 }

    /// Window size for a pond whose busiest mode has `n` items; the pond sits above the caption.
    static func size(forItems n: Int) -> NSSize {
        let side = diameter(forItems: n) + 24
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

    /// The pads and the hub, used to mask the glass backdrop so only they are frosted.
    func backdropMask() -> NSImage {
        NSImage(size: bounds.size, flipped: false) { _ in
            NSColor.black.setFill()
            NSBezierPath(ovalIn: self.circle(Self.hub)).fill()
            for i in self.items.indices { self.padPath(i, scale: 1).fill() }
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
        guard r <= g.outer + Self.pop + 10, !items.isEmpty else { return nil }
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
        drawWater()
        for i in items.indices where i != hovered { drawPad(i, highlighted: false) }
        if let h = hovered, items.indices.contains(h) { drawPad(h, highlighted: true) }
        drawCenter(radius: Self.hub)
        drawCaption(below: g.outer)
    }

    /// A faint ring of water joining the pads, so they read as one pond rather than loose buttons.
    private func drawWater() {
        let g = geometry
        let water = NSBezierPath(ovalIn: circle(g.mid))
        water.lineWidth = 2 * Self.pads(forItems: items.count).pad * 0.55
        (isDark ? NSColor(srgbRed: 0.35, green: 0.85, blue: 0.65, alpha: 0.05) : NSColor(srgbRed: 0.1, green: 0.55, blue: 0.4, alpha: 0.05)).setStroke()
        water.stroke()
    }

    private func padCenter(_ i: Int) -> NSPoint {
        let angle = startAngle(i) - step / 2
        return NSPoint(x: center.x + geometry.mid * cos(angle), y: center.y + geometry.mid * sin(angle))
    }

    /// A lily pad: a circle with the little wedge real pads have, its notch facing the file.
    private func padPath(_ i: Int, scale: CGFloat) -> NSBezierPath {
        let c = padCenter(i)
        let r = Self.pads(forItems: items.count).pad * scale
        let toward = atan2(center.y - c.y, center.x - c.x) * 180 / .pi  // degrees, pointing at the hub
        let half: CGFloat = 9
        let path = NSBezierPath()
        let tip = NSPoint(x: c.x + cos(toward * .pi / 180) * r * 0.68, y: c.y + sin(toward * .pi / 180) * r * 0.68)
        path.move(to: tip)
        path.appendArc(withCenter: c, radius: r, startAngle: toward + half, endAngle: toward - half + 360, clockwise: false)
        path.close()
        return path
    }

    private func drawPad(_ i: Int, highlighted: Bool) {
        let item = items[i]
        let color = tint(item)
        let r = Self.pads(forItems: items.count).pad
        let scale: CGFloat = highlighted ? 1.16 : 1
        let path = padPath(i, scale: scale)
        let c = padCenter(i)

        // Ripples spreading from the aimed pad.
        if highlighted {
            for (k, alpha) in [(1, 0.35), (2, 0.16)] {
                let rr = r * scale + CGFloat(k) * 7
                let ring = NSBezierPath(ovalIn: NSRect(x: c.x - rr, y: c.y - rr, width: rr * 2, height: rr * 2))
                ring.lineWidth = 1.5
                color.withAlphaComponent(CGFloat(alpha)).setStroke()
                ring.stroke()
            }
        }

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = highlighted ? color.withAlphaComponent(0.5) : NSColor.black.withAlphaComponent(isDark ? 0.35 : 0.1)
        shadow.shadowBlurRadius = highlighted ? 18 : 6
        shadow.shadowOffset = NSSize(width: 0, height: -2)
        shadow.set()
        (highlighted ? color : (isDark ? NSColor(white: 0.13, alpha: 0.78) : NSColor(white: 1, alpha: 0.86))).setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        if highlighted {
            NSGradient(starting: color.blended(withFraction: 0.25, of: .white)!, ending: color.blended(withFraction: 0.15, of: .black)!)?
                .draw(in: path, angle: -90)
        } else {
            // A green tint toward the rim, like the edge of a leaf, and light from above.
            let leaf = NSColor(srgbRed: 0.2, green: 0.75, blue: 0.5, alpha: isDark ? 0.14 : 0.1)
            NSGradient(colors: [NSColor(white: 1, alpha: 0), leaf], atLocations: [0.55, 1], colorSpace: .sRGB)?
                .draw(fromCenter: c, radius: 0, toCenter: c, radius: r, options: .drawsAfterEndingLocation)
            NSGradient(starting: NSColor(white: 1, alpha: isDark ? 0.06 : 0.45), ending: NSColor(white: 1, alpha: 0))?.draw(in: path, angle: -90)
        }
        NSGraphicsContext.restoreGraphicsState()

        let rim = highlighted ? NSColor(white: 1, alpha: 0.35)
            : NSColor(srgbRed: 0.2, green: 0.75, blue: 0.5, alpha: isDark ? 0.35 : 0.3)
        rim.setStroke()
        path.lineWidth = 1
        path.stroke()

        // Contents sit a little away from the notch, in the fuller part of the pad.
        let away = atan2(c.y - center.y, c.x - center.x)
        let p = NSPoint(x: c.x + cos(away) * r * 0.1, y: c.y + sin(away) * r * 0.1)
        let ink = highlighted ? NSColor.white : NSColor.labelColor
        let soft = highlighted ? NSColor(white: 1, alpha: 0.85) : NSColor.secondaryLabelColor
        let width = r * scale * 1.55
        if mode == .convert {
            let caption = hint(for: item)
            let nameSize: CGFloat = r >= 42 ? 14 : 12.5, captionSize: CGFloat = 8.5, symbolHeight: CGFloat = 15, spacing: CGFloat = 3
            let block = symbolHeight + spacing + nameSize * 1.15 + (caption == nil ? 0 : captionSize * 1.3)
            let top = p.y + block / 2
            drawSymbol(symbol(for: item), at: NSPoint(x: p.x, y: top - symbolHeight / 2), color: highlighted ? .white : color, size: 13)
            let nameY = top - symbolHeight - spacing - nameSize * 0.58
            drawFitted(item.title.uppercased(), centeredAt: NSPoint(x: p.x, y: nameY), maxWidth: width, size: nameSize, minSize: 9.5,
                       weight: .semibold, color: ink, kern: 0.5)
            if let caption {
                drawText(caption, at: NSPoint(x: p.x, y: nameY - nameSize * 0.58 - captionSize * 1.35), size: captionSize,
                         weight: .medium, color: soft, width: width + 4)
            }
        } else {
            let text = layoutFitted(item.title, maxWidth: width, size: 11, minSize: 8.5, weight: .semibold)
            let symbolHeight: CGFloat = 18, spacing: CGFloat = 4
            let blockTop = p.y + (symbolHeight + spacing + text.height) / 2
            drawSymbol(symbol(for: item), at: NSPoint(x: p.x, y: blockTop - symbolHeight / 2), color: highlighted ? .white : color, size: 15)
            drawFitted(item.title, centeredAt: NSPoint(x: p.x, y: blockTop - symbolHeight - spacing - text.height / 2),
                       maxWidth: width, size: 11, minSize: 8.5, weight: .semibold, color: ink)
        }
    }

    /// The colour a pad lights up in: its format's category on the Convert pond, the mode's colour otherwise.
    private func tint(_ op: FileOperation) -> NSColor { Theme.color(for: op, mode: mode) }

    /// A format's category symbol for Convert pads.
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

    /// The file's own pad in the middle: its thumbnail, what's being aimed at (or Cancel), and the
    /// three modes as small icons with the current one lit.
    private func drawCenter(radius r: CGFloat) {
        let hub = NSBezierPath(ovalIn: circle(r))
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(isDark ? 0.4 : 0.12)
        shadow.shadowBlurRadius = 12
        shadow.shadowOffset = NSSize(width: 0, height: -3)
        shadow.set()
        (isDark ? NSColor(white: 0.17, alpha: 0.92) : NSColor(white: 1, alpha: 0.95)).setFill()
        hub.fill()
        NSGraphicsContext.restoreGraphicsState()
        let cancelling = hovered == -1
        (cancelling ? NSColor.systemRed.withAlphaComponent(0.55) : NSColor(srgbRed: 0.2, green: 0.75, blue: 0.5, alpha: 0.45)).setStroke()
        hub.lineWidth = cancelling ? 2 : 1.5
        hub.stroke()

        let hoveredItem = hovered.flatMap { items.indices.contains($0) ? items[$0] : nil }
        // Top: the file (or a cross while cancelling).
        let iconCenter = NSPoint(x: center.x, y: center.y + 22)
        if cancelling {
            drawSymbol("xmark", at: iconCenter, color: .systemRed, size: 20)
        } else if let thumbnail {
            let side: CGFloat = 30
            thumbnail.draw(in: NSRect(x: iconCenter.x - side / 2, y: iconCenter.y - side / 2, width: side, height: side),
                           from: .zero, operation: .sourceOver, fraction: 1)
        } else {
            drawSymbol("doc", at: iconCenter, color: .secondaryLabelColor, size: 20)
        }

        // Middle: what letting go will do.
        let label: String
        var ink = NSColor.labelColor
        if cancelling { label = "Cancel"; ink = .systemRed }
        else if let op = hoveredItem { label = mode == .convert ? "to " + op.title.uppercased() : op.title }
        else { label = items.isEmpty ? "Nothing here" : mode.title; ink = .secondaryLabelColor }
        let fit = layoutFitted(label, maxWidth: r * 2 - 22, size: 13, minSize: 9.5, weight: .semibold)
        drawText(fit.lines.count == 1 ? fit.lines[0] : label, at: NSPoint(x: center.x, y: center.y - 9), size: fit.lines.count == 1 ? fit.size : 9.5,
                 weight: .semibold, color: ink, width: r * 2 - 16)

        // Bottom: the three modes.
        let modes = WheelMode.allCases
        let w: CGFloat = 22, h: CGFloat = 18, spacing: CGFloat = 3
        let total = CGFloat(modes.count) * w + CGFloat(modes.count - 1) * spacing
        for (i, m) in modes.enumerated() {
            let rect = NSRect(x: center.x - total / 2 + CGFloat(i) * (w + spacing), y: center.y - 36, width: w, height: h)
            let modeColor = [Theme.brand, Theme.Category.tool.color, Theme.Category.action.color][m.rawValue]
            if m == mode {
                modeColor.withAlphaComponent(isDark ? 0.24 : 0.16).setFill()
                NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
            }
            drawSymbol(m.symbol, at: NSPoint(x: rect.midX, y: rect.midY), color: m == mode ? modeColor : .tertiaryLabelColor, size: 10.5)
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
