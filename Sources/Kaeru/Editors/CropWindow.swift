import AppKit

/// Lets the user draw a crop rectangle over an image (or a video frame).
/// Returns the rectangle in pixels with a top-left origin, as CGImage cropping and ffmpeg expect.
@MainActor
final class CropWindow: NSWindow, NSWindowDelegate {
    private let cropView: CropView
    private let sizeLabel = NSTextField(labelWithString: "")
    private var continuation: CheckedContinuation<CGRect?, Never>?

    private static let aspects: [(String, CGFloat?)] = [
        ("Free", nil), ("Original", -1), ("Square", 1), ("4:3", 4.0 / 3), ("3:2", 1.5), ("16:9", 16.0 / 9),
        ("9:16", 9.0 / 16), ("4:5", 0.8),
    ]

    static func ask(image: CGImage, title: String) async -> CGRect? {
        let window = CropWindow(image: image, title: title)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        return await withCheckedContinuation { window.continuation = $0 }
    }

    private init(image: CGImage, title: String) {
        cropView = CropView(image: image)
        let fit = min(900 / CGFloat(image.width), 620 / CGFloat(image.height), 1)
        let size = NSSize(width: max(480, CGFloat(image.width) * fit + 40), height: CGFloat(image.height) * fit + 40 + 52)
        super.init(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .resizable],
                   backing: .buffered, defer: false)
        self.title = "Crop — \(title)"
        isReleasedWhenClosed = false
        delegate = self
        minSize = NSSize(width: 480, height: 360)

        let aspect = NSPopUpButton(frame: .zero, pullsDown: false)
        aspect.addItems(withTitles: Self.aspects.map(\.0))
        aspect.target = self
        aspect.action = #selector(aspectChanged(_:))
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelTapped))
        cancel.keyEquivalent = "\u{1b}"
        let crop = NSButton(title: "Crop", target: self, action: #selector(cropTapped))
        crop.keyEquivalent = "\r"
        sizeLabel.textColor = .secondaryLabelColor
        sizeLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)

        let bar = NSStackView(views: [aspect, sizeLabel, NSView(), cancel, crop])
        bar.edgeInsets = NSEdgeInsets(top: 10, left: 14, bottom: 12, right: 14)
        let root = NSStackView(views: [cropView, bar])
        root.orientation = .vertical
        root.spacing = 0
        cropView.setContentHuggingPriority(.defaultLow, for: .vertical)
        contentView = root
        cropView.onChange = { [weak self] rect in
            self?.sizeLabel.stringValue = "\(Int(rect.width)) × \(Int(rect.height)) px"
        }
        cropView.onChange?(cropView.crop)
        center()
    }

    @objc private func aspectChanged(_ sender: NSPopUpButton) {
        var ratio = Self.aspects[sender.indexOfSelectedItem].1
        if ratio == -1 { ratio = CGFloat(cropView.image.width) / CGFloat(cropView.image.height) }
        cropView.setAspect(ratio)
    }

    @objc private func cancelTapped() { finish(nil) }
    @objc private func cropTapped() { finish(cropView.crop.integral) }

    private func finish(_ rect: CGRect?) {
        continuation?.resume(returning: rect)
        continuation = nil
        orderOut(nil)
    }

    func windowWillClose(_ notification: Notification) { finish(nil) }
}

private final class CropView: NSView {
    let image: CGImage
    /// Pixel coordinates, top-left origin.
    private(set) var crop: CGRect
    var onChange: ((CGRect) -> Void)?
    private var aspect: CGFloat?
    private var drag: (mode: Mode, startPoint: CGPoint, startCrop: CGRect)?
    private lazy var nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))

    private enum Mode { case move, resize(anchor: CGPoint) }

    init(image: CGImage) {
        self.image = image
        let w = CGFloat(image.width), h = CGFloat(image.height)
        crop = CGRect(x: w * 0.1, y: h * 0.1, width: w * 0.8, height: h * 0.8)
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    private var bounds01: CGRect { CGRect(x: 0, y: 0, width: image.width, height: image.height) }

    private var imageRect: CGRect {
        let area = bounds.insetBy(dx: 20, dy: 20)
        let scale = min(area.width / CGFloat(image.width), area.height / CGFloat(image.height))
        let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        return CGRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2, width: size.width, height: size.height)
    }

    private var scale: CGFloat { imageRect.width / CGFloat(image.width) }

    private func toView(_ r: CGRect) -> CGRect {
        CGRect(x: imageRect.minX + r.minX * scale, y: imageRect.minY + r.minY * scale, width: r.width * scale, height: r.height * scale)
    }

    private func toPixels(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max((p.x - imageRect.minX) / scale, 0), CGFloat(image.width)),
                y: min(max((p.y - imageRect.minY) / scale, 0), CGFloat(image.height)))
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 0.12, alpha: 1).setFill()
        bounds.fill()
        nsImage.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)

        let cropRect = toView(crop)
        let shade = NSBezierPath(rect: imageRect)
        shade.append(NSBezierPath(rect: cropRect))
        shade.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.55).setFill()
        shade.fill()

        NSColor.white.withAlphaComponent(0.35).setStroke()
        for i in 1...2 {
            let t = CGFloat(i) / 3
            let v = NSBezierPath(), h = NSBezierPath()
            v.move(to: CGPoint(x: cropRect.minX + cropRect.width * t, y: cropRect.minY))
            v.line(to: CGPoint(x: cropRect.minX + cropRect.width * t, y: cropRect.maxY))
            h.move(to: CGPoint(x: cropRect.minX, y: cropRect.minY + cropRect.height * t))
            h.line(to: CGPoint(x: cropRect.maxX, y: cropRect.minY + cropRect.height * t))
            v.stroke(); h.stroke()
        }
        NSColor.white.setStroke()
        let border = NSBezierPath(rect: cropRect)
        border.lineWidth = 1.5
        border.stroke()
        NSColor.white.setFill()
        for corner in corners(of: cropRect) {
            NSBezierPath(rect: CGRect(x: corner.x - 5, y: corner.y - 5, width: 10, height: 10)).fill()
        }
    }

    private func corners(of r: CGRect) -> [CGPoint] {
        [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY)]
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let pixel = toPixels(p)
        let viewCrop = toView(crop)
        let pixelCorners = corners(of: crop)
        if let i = corners(of: viewCrop).firstIndex(where: { hypot($0.x - p.x, $0.y - p.y) < 14 }) {
            drag = (.resize(anchor: pixelCorners[3 - i]), pixel, crop)  // opposite corner stays put
        } else if viewCrop.contains(p) {
            drag = (.move, pixel, crop)
        } else {
            drag = (.resize(anchor: pixel), pixel, crop)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let drag else { return }
        let p = toPixels(convert(event.locationInWindow, from: nil))
        switch drag.mode {
        case .move:
            var r = drag.startCrop.offsetBy(dx: p.x - drag.startPoint.x, dy: p.y - drag.startPoint.y)
            r.origin.x = min(max(r.minX, 0), CGFloat(image.width) - r.width)
            r.origin.y = min(max(r.minY, 0), CGFloat(image.height) - r.height)
            update(r)
        case .resize(let anchor):
            update(rect(from: anchor, to: p))
        }
    }

    override func mouseUp(with event: NSEvent) { drag = nil }

    /// A rectangle from a fixed corner towards the cursor, honouring the aspect ratio and image bounds.
    private func rect(from anchor: CGPoint, to p: CGPoint) -> CGRect {
        let dx = p.x - anchor.x, dy = p.y - anchor.y
        let maxW = dx >= 0 ? CGFloat(image.width) - anchor.x : anchor.x
        let maxH = dy >= 0 ? CGFloat(image.height) - anchor.y : anchor.y
        var w = min(abs(dx), maxW), h = min(abs(dy), maxH)
        if let aspect {
            if w / max(h, 1) > aspect { w = h * aspect } else { h = w / aspect }
            if w > maxW { w = maxW; h = w / aspect }
            if h > maxH { h = maxH; w = h * aspect }
        }
        w = max(w, 8); h = max(h, 8)
        return CGRect(x: dx >= 0 ? anchor.x : anchor.x - w, y: dy >= 0 ? anchor.y : anchor.y - h, width: w, height: h)
            .intersection(bounds01)
    }

    func setAspect(_ ratio: CGFloat?) {
        aspect = ratio
        guard let ratio else { return }
        // Largest rectangle of the new ratio that fits the image, centred on the current crop.
        var w = CGFloat(image.width), h = w / ratio
        if h > CGFloat(image.height) { h = CGFloat(image.height); w = h * ratio }
        w *= 0.9; h *= 0.9
        var r = CGRect(x: crop.midX - w / 2, y: crop.midY - h / 2, width: w, height: h)
        r.origin.x = min(max(r.minX, 0), CGFloat(image.width) - w)
        r.origin.y = min(max(r.minY, 0), CGFloat(image.height) - h)
        update(r)
    }

    private func update(_ r: CGRect) {
        crop = r
        onChange?(r)
        needsDisplay = true
    }
}
