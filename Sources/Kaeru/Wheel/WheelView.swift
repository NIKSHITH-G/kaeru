import AppKit

/// Kaeru's picker, in the style of sumi-e ink painting: a disc of rice paper with a soft pool of
/// ink under each choice. Aiming at one makes its ink spread and bloom into the format's colour.
/// The file sits in a brushed ring in the middle. Turns drops, clicks and arrow keys into the
/// chosen operation.
/// The frosted-glass backdrop is a separate NSVisualEffectView masked to the disc (see WheelController).
final class WheelView: NSView {
    private var items: [FileOperation] = []
    private var urls: [URL] = []
    private var mode: WheelMode = .convert
    private var interactive = false
    private var thumbnail: NSImage?
    /// Index of the highlighted choice; -1 is the middle (cancel), nil is nothing.
    private var hovered: Int?
    /// The pointer starts in the middle, which means "cancel". Until the person has aimed at
    /// something, the middle shows the file instead of a cancel prompt.
    private var hasAimed = false
    /// The choice last made for this kind of file in this mode, marked with a small red dot.
    private var lastUsed: String?

    // Animation: you are a drop of ink. It flows out of the file toward whatever you aim at,
    // gliding around the disc from choice to choice with a tapering trail, then soaks into that
    // choice's pool, which fills with colour from the bottom like a vessel filling with ink.
    private var dropAngle: CGFloat = .pi / 2
    private var dropRadius: CGFloat = 0
    private var dropColor = NSColor.gray
    private var trail: [NSPoint] = []
    /// Fill level of each choice's pool, 0…1.
    private var fill: [CGFloat] = []
    private var wave: CGFloat = 0
    private var lastTick = Date()
    private var timer: Timer?
    /// For `--render-wheel` stills: how far the drop has travelled from the file (KAERU_TRAVEL=0.6).
    private let frozenTravel = ProcessInfo.processInfo.environment["KAERU_TRAVEL"].flatMap(Double.init).map { CGFloat($0) }

    static let pop: CGFloat = 6
    /// Room under the disc for the caption ("Convert photo.heic to PNG").
    static let captionHeight: CGFloat = 50
    private static let rim: CGFloat = 10

    static func radii(forItems n: Int) -> (inner: CGFloat, mid: CGFloat, outer: CGFloat) {
        // ~76pt of arc per choice keeps labels readable while the disc stays compact.
        let mid = max(100, CGFloat(n) * 76 / (2 * .pi))
        return (mid - 44, mid, mid + 44)
    }

    static func diameter(forItems n: Int) -> CGFloat { (radii(forItems: n).outer + rim + pop) * 2 }

    /// Window size for a disc whose busiest mode has `n` items; the disc sits above the caption.
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
        if urls != self.urls { hasAimed = false; hovered = nil; dropRadius = 0; trail = [] }
        if items.count != fill.count || mode != self.mode { fill = Array(repeating: 0, count: items.count); trail = [] }
        self.urls = urls
        self.mode = mode
        self.items = items
        self.interactive = interactive
        lastUsed = Recents.last(for: urls, mode: mode)
        if let h = hovered, h >= items.count { hovered = nil }
        if interactive && (hovered == nil || hovered == -1) && !items.isEmpty {
            // Keyboard use starts on the last choice for this kind of file.
            hovered = items.firstIndex { $0.id == lastUsed } ?? 0
            hasAimed = true
        }
        needsDisplay = true
    }

    func setThumbnail(_ image: NSImage?) {
        thumbnail = image
        needsDisplay = true
    }

    /// The disc, used to mask the glass backdrop.
    func backdropMask() -> NSImage {
        let r = geometry.outer + Self.rim
        return NSImage(size: bounds.size, flipped: false) { _ in
            NSColor.black.setFill()
            NSBezierPath(ovalIn: self.circle(r)).fill()
            return true
        }
    }

    // MARK: Geometry

    /// Disc centre: the middle of the top square of the view, leaving the caption strip below.
    private var center: NSPoint { NSPoint(x: bounds.midX, y: Self.captionHeight + bounds.width / 2) }
    private var geometry: (inner: CGFloat, mid: CGFloat, outer: CGFloat) { Self.radii(forItems: items.count) }
    private var step: CGFloat { 2 * .pi / CGFloat(max(items.count, 1)) }
    private func startAngle(_ i: Int) -> CGFloat { .pi / 2 - CGFloat(i) * step }  // clockwise from 12 o'clock
    private func circle(_ r: CGFloat, at c: NSPoint? = nil) -> NSRect {
        let c = c ?? center
        return NSRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
    }
    private func point(_ r: CGFloat, _ a: CGFloat) -> NSPoint { NSPoint(x: center.x + r * cos(a), y: center.y + r * sin(a)) }
    private func spot(_ i: Int) -> NSPoint { point(geometry.mid, startAngle(i) - step / 2) }

    /// Aiming is by direction: anywhere in a choice's slice of the disc (and a little beyond) picks it.
    private func slice(at p: NSPoint) -> Int? {
        let dx = p.x - center.x, dy = p.y - center.y
        let r = hypot(dx, dy)
        let g = geometry
        if r < g.inner { return -1 }
        guard r <= g.outer + 24, !items.isEmpty else { return nil }
        var theta = .pi / 2 - atan2(dy, dx)
        if theta < 0 { theta += 2 * .pi }
        return min(Int(theta / step), items.count - 1)
    }

    private func setHovered(_ value: Int?) {
        guard value != hovered else { return }
        hovered = value
        if let value, value >= 0 {
            hasAimed = true
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        startAnimating()
        needsDisplay = true
    }

    fileprivate func setHoveredForDebug(_ index: Int) {
        if index >= 0 { hasAimed = true }
        hovered = index
        startAnimating()
        needsDisplay = true
    }

    /// Runs the ink at display rate until it settles. Added for all run-loop modes, because a
    /// drag keeps the run loop in event-tracking mode.
    private func startAnimating() {
        guard frozenTravel == nil else { return }
        if timer == nil { lastTick = Date() }
        guard timer == nil else { return }
        let t = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private var dropPoint: NSPoint { point(dropRadius, dropAngle) }
    private static let poolRadius: CGFloat = 32

    /// How close the drop is to a choice's pool: 1 on top of it, 0 a pool's width away.
    private func closeness(_ i: Int) -> CGFloat {
        let d = hypot(dropPoint.x - spot(i).x, dropPoint.y - spot(i).y)
        let t = max(0, min(1, 1 - (d - Self.poolRadius * 0.25) / (Self.poolRadius * 1.5)))
        return t * t * (3 - 2 * t)
    }

    /// The level each pool is heading for: full for the aimed choice once the drop arrives, a
    /// faint tint for any the drop is passing over.
    private func targetFill(_ i: Int) -> CGFloat {
        i == hovered ? closeness(i) : closeness(i) * 0.3
    }

    private func tick() {
        let now = Date()
        let dt = CGFloat(min(0.05, now.timeIntervalSince(lastTick)))
        lastTick = now
        let k = 1 - exp(-dt * 13)

        // Where the drop is heading: the aimed choice, or home to the file.
        var targetAngle = dropAngle, targetRadius = dropRadius
        if let h = hovered, items.indices.contains(h) {
            targetAngle = startAngle(h) - step / 2
            targetRadius = geometry.mid
            dropColor = dropColor.blended(withFraction: min(1, k * 1.4), of: tint(items[h])) ?? dropColor
        } else if hovered == -1 {
            targetRadius = 0
        }
        // Coming out of the file it heads straight out; on the ring it glides the short way round.
        if dropRadius < geometry.inner * 0.6 { dropAngle = targetAngle }
        var dA = (targetAngle - dropAngle).truncatingRemainder(dividingBy: 2 * .pi)
        if dA > .pi { dA -= 2 * .pi } else if dA < -.pi { dA += 2 * .pi }
        dropAngle += dA * k
        let dR = targetRadius - dropRadius
        dropRadius += dR * k

        // The trail follows the drop and shortens once it stops moving.
        let head = dropPoint
        if dropRadius > geometry.inner * 0.7, trail.last.map({ hypot($0.x - head.x, $0.y - head.y) > 1.5 }) ?? true {
            trail.append(head)
            if trail.count > 16 { trail.removeFirst() }
        } else if !trail.isEmpty {
            trail.removeFirst()
        }

        // Pools fill slowly, like ink soaking in, and drain a little faster.
        var settledFill = true
        for i in fill.indices {
            let target = targetFill(i)
            let rate: CGFloat = target > fill[i] ? 6 : 9
            fill[i] += (target - fill[i]) * (1 - exp(-dt * rate))
            if abs(target - fill[i]) > 0.003 { settledFill = false }
        }
        wave += dt * 5

        needsDisplay = true
        if abs(dA) < 0.002, abs(dR) < 0.3, trail.isEmpty, settledFill {
            timer?.invalidate()
            timer = nil
        }
    }

    /// For stills: place the drop part-way along its journey and fill the pools to match.
    private func freezeForStill(_ travel: CGFloat) {
        guard let h = hovered, items.indices.contains(h) else { return }
        dropAngle = startAngle(h) - step / 2
        let start = geometry.inner * 0.7
        dropRadius = start + (geometry.mid - start) * travel
        dropColor = tint(items[h])
        trail = (0..<12).map { k in point(start + (dropRadius - start) * CGFloat(k) / 11, dropAngle) }
        if travel >= 1 { trail = [] }
        fill = items.indices.map { targetFill($0) }
        wave = 1.3
    }

    private var isDark: Bool { effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }

    // MARK: Palette

    /// Rice paper, or dark sumi paper in Dark Mode.
    private var paper: NSColor {
        isDark ? NSColor(srgbRed: 0.10, green: 0.095, blue: 0.09, alpha: 0.97) : NSColor(srgbRed: 0.97, green: 0.95, blue: 0.90, alpha: 0.97)
    }
    /// Ink: near black on light paper, warm off-white on dark.
    private var ink: NSColor {
        isDark ? NSColor(srgbRed: 0.93, green: 0.90, blue: 0.84, alpha: 1) : NSColor(srgbRed: 0.09, green: 0.09, blue: 0.10, alpha: 1)
    }
    private static let vermilion = NSColor(srgbRed: 0.82, green: 0.20, blue: 0.14, alpha: 1)

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        if let travel = frozenTravel { freezeForStill(travel) }
        if fill.count != items.count { fill = Array(repeating: 0, count: items.count) }
        drawPaper()
        // Pools, then the drop flowing over them, then the labels on top so nothing hides them.
        for i in items.indices { drawChoice(i, amount: fill[i], labels: false) }
        drawDrop()
        for i in items.indices { drawChoice(i, amount: fill[i], labels: true) }
        drawHub()
        drawCaption()
    }

    /// The traveller: a tapering liquid trail and a glistening drop at its head, which fades as it
    /// soaks into the pool it reaches and disappears back into the file.
    private func drawDrop() {
        let head = dropPoint
        var alpha: CGFloat = min(1, max(0, (dropRadius - geometry.inner * 0.75) / 14))
        if let h = hovered, items.indices.contains(h) {
            let d = hypot(head.x - spot(h).x, head.y - spot(h).y)
            alpha *= min(1, max(0, d / (Self.poolRadius * 0.9)))  // soaking in
        }
        guard alpha > 0.01 else { return }
        NSGraphicsContext.saveGraphicsState()
        let glow = NSShadow()
        glow.shadowColor = dropColor.withAlphaComponent(0.5 * alpha)
        glow.shadowBlurRadius = 10
        glow.set()
        let points = trail + [head]
        for k in 1..<max(1, points.count) {
            let t = CGFloat(k) / CGFloat(points.count)
            let seg = NSBezierPath()
            seg.move(to: points[k - 1])
            seg.line(to: points[k])
            seg.lineWidth = 2 + 9 * t
            seg.lineCapStyle = .round
            dropColor.withAlphaComponent((0.15 + 0.7 * t) * alpha).setStroke()
            seg.stroke()
        }
        dropColor.withAlphaComponent(0.95 * alpha).setFill()
        pool(at: head, radius: 7.5, seed: wave * 0.6).fill()
        NSGraphicsContext.restoreGraphicsState()
        // A glint, so it reads as liquid.
        NSColor(white: 1, alpha: 0.55 * alpha).setFill()
        NSBezierPath(ovalIn: NSRect(x: head.x - 3.5, y: head.y + 1, width: 3, height: 2.4)).fill()
    }

    /// The disc of paper, a little darker toward its edge, with a faint brushed rim.
    private func drawPaper() {
        let g = geometry
        let r = g.outer + Self.rim
        let disc = NSBezierPath(ovalIn: circle(r))
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(isDark ? 0.5 : 0.2)
        shadow.shadowBlurRadius = 18
        shadow.shadowOffset = NSSize(width: 0, height: -5)
        shadow.set()
        paper.setFill()
        disc.fill()
        NSGraphicsContext.restoreGraphicsState()
        // Vignette: the paper deepens slightly toward the edge.
        NSGradient(starting: paper.withAlphaComponent(0), ending: ink.withAlphaComponent(isDark ? 0.05 : 0.06))?
            .draw(fromCenter: center, radius: r * 0.55, toCenter: center, radius: r, options: [])
        disc.lineWidth = 1
        ink.withAlphaComponent(0.12).setStroke()
        disc.stroke()
    }

    /// Deterministic wobble for hand-made edges, so every pool keeps its shape between frames.
    private func wobble(_ x: CGFloat, _ seed: CGFloat) -> CGFloat {
        sin(x * 3.1 + seed) * 0.5 + sin(x * 7.3 + seed * 1.7) * 0.3 + sin(x * 13.7 + seed * 0.3) * 0.2
    }

    /// An irregular pool of ink around `p`.
    private func pool(at p: NSPoint, radius: CGFloat, seed: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        for k in 0...56 {
            let t = CGFloat(k) / 56 * 2 * .pi
            let rr = radius * (1 + wobble(t * 1.3, seed) * 0.2)
            let q = NSPoint(x: p.x + rr * cos(t), y: p.y + rr * sin(t))
            k == 0 ? path.move(to: q) : path.line(to: q)
        }
        path.close()
        return path
    }

    /// One choice: its ink pool (blooming into colour by `amount`), icon, name and hint.
    private func drawChoice(_ i: Int, amount: CGFloat, labels: Bool) {
        let item = items[i]
        let color = tint(item)
        let p = spot(i)
        let seed = CGFloat(i) * 2.1 + 0.7
        let base = Self.poolRadius
        if labels { drawLabels(i, amount: amount); return }

        // The resting wash: a soft grey pool, lighter at its heart.
        NSGradient(starting: ink.withAlphaComponent(isDark ? 0.17 : 0.12), ending: ink.withAlphaComponent(0.02))?
            .draw(in: pool(at: p, radius: base, seed: seed), relativeCenterPosition: NSPoint(x: -0.2, y: 0.2))

        // Colour rising inside the pool from the bottom, with a gently moving surface.
        if amount > 0.01 {
            let shape = pool(at: p, radius: base * 1.05, seed: seed)
            if amount > 0.5 {
                NSGraphicsContext.saveGraphicsState()
                let glow = NSShadow()
                glow.shadowColor = color.withAlphaComponent(0.5 * (amount - 0.5) * 2)
                glow.shadowBlurRadius = 16
                glow.set()
                color.withAlphaComponent(0.2).setFill()
                shape.fill()
                NSGraphicsContext.restoreGraphicsState()
            }
            NSGraphicsContext.saveGraphicsState()
            shape.addClip()
            let bottom = p.y - base * 1.3, top = p.y + base * 1.3
            let level = bottom + (top - bottom) * amount
            let surface = NSBezierPath()
            surface.move(to: NSPoint(x: p.x - base * 1.6, y: bottom - 4))
            var x = p.x - base * 1.6
            while x <= p.x + base * 1.6 {
                surface.line(to: NSPoint(x: x, y: level + sin(x * 0.13 + wave + CGFloat(i)) * 2.4 * (1.2 - amount)))
                x += 3
            }
            surface.line(to: NSPoint(x: p.x + base * 1.6, y: bottom - 4))
            surface.close()
            NSGradient(starting: color.blended(withFraction: 0.18, of: .white)!.withAlphaComponent(0.95),
                       ending: color.blended(withFraction: 0.2, of: .black)!.withAlphaComponent(0.95))?.draw(in: surface, angle: -90)
            NSGraphicsContext.restoreGraphicsState()
        }

        // The last choice for this kind of file: a small vermilion dot, like a seal mark.
        if item.id == lastUsed {
            let a = startAngle(i) - step / 2
            let dot = NSPoint(x: p.x + cos(a + 0.9) * base * 0.95, y: p.y + sin(a + 0.9) * base * 0.95)
            Self.vermilion.withAlphaComponent(0.85).setFill()
            NSBezierPath(ovalIn: circle(3.5, at: dot)).fill()
        }
    }

    private func drawLabels(_ i: Int, amount: CGFloat) {
        let item = items[i]
        let color = tint(item)
        let p = spot(i)
        let lit = amount > 0.55
        let text = lit ? NSColor.white : ink
        // Names fit inside their pool: long ones ("MARKDOWN") shrink rather than spill out.
        let width = Self.poolRadius * 1.85
        if mode == .convert {
            let hint = self.hint(for: item)
            let nameSize: CGFloat = 12.5
            let block: CGFloat = 14 + 2 + nameSize * 1.2 + (hint == nil ? 0 : 11)
            let top = p.y + block / 2
            drawSymbol(symbol(for: item), at: NSPoint(x: p.x, y: top - 7), color: lit ? .white : color, size: 11.5)
            let nameY = top - 14 - 2 - nameSize * 0.6
            label(item.title.uppercased(), at: NSPoint(x: p.x, y: nameY), size: nameSize, color: text, width: width)
            if let hint {
                label(hint, at: NSPoint(x: p.x, y: nameY - 13), size: 8, color: text.withAlphaComponent(0.7), width: width + 6, bold: false)
            }
        } else {
            // Tool and action names can be two words ("Remove Background"): wrap rather than cut them off.
            let lines = Self.wrap(item.title, width: width, size: 10.5)
            let lineHeight: CGFloat = 11.5
            let top = p.y + (15 + 3 + lineHeight * CGFloat(lines.count)) / 2
            drawSymbol(symbol(for: item), at: NSPoint(x: p.x, y: top - 7), color: lit ? .white : color, size: 13)
            for (k, line) in lines.enumerated() {
                label(line, at: NSPoint(x: p.x, y: top - 18 - lineHeight * (CGFloat(k) + 0.5)), size: 10.5, color: text, width: width)
            }
        }
    }

    /// The middle: a brushed ring holding the file, the pending action, and the three modes.
    private func drawHub() {
        let r = geometry.inner - 8
        // A light brushed ring, heavier at the start and thinning out like a quick ensō.
        let start: CGFloat = .pi * 0.62, sweep: CGFloat = .pi * 1.85
        for k in 0..<160 {
            let t = CGFloat(k) / 160
            let a = start + sweep * t
            let w = (1 - t * 0.6) * 4 + wobble(t * 9, 1) * 0.6
            let rr = r + wobble(t * 4, 3) * 1.2
            ink.withAlphaComponent(0.5).setFill()
            NSBezierPath(ovalIn: NSRect(x: center.x + rr * cos(a) - w / 2, y: center.y + rr * sin(a) - w / 2, width: w, height: w)).fill()
        }

        let aimed = hovered.flatMap { items.indices.contains($0) ? items[$0] : nil }
        let cancelling = hovered == -1 && hasAimed

        let side: CGFloat = 26
        let thumb = NSRect(x: center.x - side / 2, y: center.y + 4, width: side, height: side)
        if let thumbnail {
            thumbnail.draw(in: thumb, from: .zero, operation: .sourceOver, fraction: cancelling ? 0.3 : 1)
        } else {
            drawSymbol("doc", at: NSPoint(x: thumb.midX, y: thumb.midY), color: ink.withAlphaComponent(0.5), size: 20)
        }

        let text: String
        var color = ink
        var size: CGFloat = 11.5
        if cancelling {
            text = "Cancel"; color = Self.vermilion
        } else if let op = aimed {
            text = mode == .convert ? op.title.uppercased() : op.title
            color = tint(op)
        } else if items.isEmpty {
            text = "Nothing here"; color = ink.withAlphaComponent(0.6)
        } else {
            text = urls.count == 1 ? urls[0].deletingPathExtension().lastPathComponent : "\(urls.count) items"
            color = ink.withAlphaComponent(0.6); size = 9.5
        }
        label(text, at: NSPoint(x: center.x, y: center.y - 7), size: size, color: color, width: r * 2 - 18, middle: true)

        // The three modes as small marks; the current one in its colour.
        let modes = WheelMode.allCases
        let spacing: CGFloat = 18
        for (k, m) in modes.enumerated() {
            let x = center.x + CGFloat(k - 1) * spacing
            let current = m == mode
            let tone = [Theme.brand, Theme.Category.tool.color, Theme.Category.action.color][m.rawValue]
            drawSymbol(m.symbol, at: NSPoint(x: x, y: center.y - 25), color: current ? tone : ink.withAlphaComponent(0.25), size: current ? 9.5 : 8.5)
        }
    }

    /// What letting go will do, on a slip of paper under the disc.
    private func drawCaption() {
        let aimed = hovered.flatMap { items.indices.contains($0) ? items[$0] : nil }
        let name = urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) items"
        let text: String
        if hovered == -1 && hasAimed { text = "Let go in the middle to cancel" }
        else if let op = aimed {
            let last = op.id == lastUsed ? " · last used" : ""
            switch mode {
            case .convert: text = "Convert \(name) to \(op.title.uppercased())" + last
            case .tools, .actions: text = "\(op.title) · \(name)" + last
            }
        } else if items.isEmpty { text = name }
        else { text = interactive ? "Arrow keys to choose · Tab for more" : "Move toward a choice and let go" }

        let font = Self.mincho(11, bold: false)
        let textWidth = min((text as NSString).size(withAttributes: [.font: font]).width, bounds.width - 80)
        let width = textWidth + 28
        let rect = NSRect(x: center.x - width / 2, y: center.y - geometry.outer - Self.rim - Self.pop - 32, width: width, height: 25)
        let slip = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
        paper.withAlphaComponent(0.96).setFill()
        slip.fill()
        ink.withAlphaComponent(0.15).setStroke()
        slip.lineWidth = 1
        slip.stroke()
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingMiddle
        style.alignment = .center
        (text as NSString).draw(in: NSRect(x: rect.minX + 14, y: rect.minY + 5, width: textWidth + 2, height: 16),
                                withAttributes: [.font: font, .foregroundColor: ink.withAlphaComponent(0.75), .paragraphStyle: style])
    }

    // MARK: Text and symbols

    /// Hiragino Mincho, the Japanese serif that ships with macOS, gives the labels a brushed feel.
    private static func mincho(_ size: CGFloat, bold: Bool) -> NSFont {
        // KAERU_FONT="Bold-Name,Regular-Name" tries another typeface in `--render-wheel` comparisons.
        let names = ProcessInfo.processInfo.environment["KAERU_FONT"]?.split(separator: ",").map(String.init) ?? ["HiraMinProN-W6", "HiraMinProN-W3"]
        return NSFont(name: bold ? names[0] : (names.count > 1 ? names[1] : names[0]), size: size)
            ?? .systemFont(ofSize: size, weight: bold ? .semibold : .regular)
    }

    /// One line if `text` fits at a readable size, otherwise two lines split at the most balanced space.
    private static func wrap(_ text: String, width: CGFloat, size: CGFloat) -> [String] {
        func w(_ s: String) -> CGFloat { (s as NSString).size(withAttributes: [.font: mincho(size * 0.9, bold: true), .kern: 0.4]).width }
        let words = text.split(separator: " ").map(String.init)
        guard w(text) > width, words.count > 1 else { return [text] }
        let splits = (1..<words.count).map { (words[..<$0].joined(separator: " "), words[$0...].joined(separator: " ")) }
        let best = splits.min { max(w($0.0), w($0.1)) < max(w($1.0), w($1.1)) }!
        return [best.0, best.1]
    }

    private func label(_ text: String, at p: NSPoint, size: CGFloat, color: NSColor, width: CGFloat, bold: Bool = true, middle: Bool = false) {
        var pt = size
        let font = { Self.mincho(pt, bold: bold) }
        while pt > 7 && (text as NSString).size(withAttributes: [.font: font(), .kern: 0.4]).width > width { pt -= 0.5 }
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = middle ? .byTruncatingMiddle : .byTruncatingTail
        (text as NSString).draw(in: NSRect(x: p.x - width / 2, y: p.y - pt * 0.62, width: width, height: pt * 1.5),
                                withAttributes: [.font: font(), .foregroundColor: color, .paragraphStyle: style, .kern: 0.4])
    }

    private func drawSymbol(_ name: String, at p: NSPoint, color: NSColor, size: CGFloat) {
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: .medium).applying(.init(paletteColors: [color]))
        guard let symbol = (NSImage(systemSymbolName: name, accessibilityDescription: nil)
            ?? NSImage(systemSymbolName: "circle", accessibilityDescription: nil))?.withSymbolConfiguration(config) else { return }
        let s = symbol.size
        symbol.draw(in: NSRect(x: p.x - s.width / 2, y: p.y - s.height / 2, width: s.width, height: s.height))
    }

    /// The colour a choice blooms into: its format's category on the Convert disc, the mode's colour otherwise.
    private func tint(_ op: FileOperation) -> NSColor { Theme.color(for: op, mode: mode) }

    /// A format's category symbol for Convert choices.
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
    /// For `--render-wheel` design checks and the onboarding preview: aim at a choice without a mouse.
    func debugHover(_ index: Int) { setHoveredForDebug(index) }
}

/// The choice last made for each kind of file in each mode, so the picker can point it out.
enum Recents {
    private static func key(for urls: [URL], mode: WheelMode) -> String? {
        guard let first = urls.first else { return nil }
        let ext = FileKind.normalizedExt(first.pathExtension)
        return "lastChoice.\(mode.rawValue).\(ext.isEmpty ? "folder" : ext)"
    }

    static func last(for urls: [URL], mode: WheelMode) -> String? {
        key(for: urls, mode: mode).flatMap { UserDefaults.standard.string(forKey: $0) }
    }

    static func record(_ op: FileOperation, for urls: [URL], mode: WheelMode) {
        guard let key = key(for: urls, mode: mode) else { return }
        UserDefaults.standard.set(op.id, forKey: key)
    }
}
