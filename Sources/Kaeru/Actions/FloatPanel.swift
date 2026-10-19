import AppKit
import QuickLookThumbnailing

/// A small always-on-top shelf holding files, so you can drag them out later from any Space.
final class FloatPanel: NSPanel {
    private static var open: [FloatPanel] = []

    static func show(_ urls: [URL]) {
        let panel = FloatPanel(urls: urls)
        open.append(panel)
        panel.orderFrontRegardless()
    }

    private init(urls: [URL]) {
        let size = NSSize(width: 132, height: 150)
        let mouse = NSEvent.mouseLocation
        super.init(contentRect: NSRect(x: mouse.x - size.width / 2, y: mouse.y - size.height / 2, width: size.width, height: size.height),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = true
        backgroundColor = .clear
        hasShadow = true

        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        effect.material = .hudWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 16
        effect.layer?.masksToBounds = true
        let view = FloatView(frame: effect.bounds, urls: urls) { [weak self] in self?.dismiss() }
        view.autoresizingMask = [.width, .height]
        effect.addSubview(view)
        contentView = effect
    }

    func dismiss() {
        orderOut(nil)
        FloatPanel.open.removeAll { $0 === self }
    }
}

private final class FloatView: NSView, NSDraggingSource {
    let urls: [URL]
    let onClose: () -> Void
    private var icon: NSImage
    private var mouseDownEvent: NSEvent?

    init(frame: NSRect, urls: [URL], onClose: @escaping () -> Void) {
        self.urls = urls
        self.onClose = onClose
        self.icon = NSWorkspace.shared.icon(forFile: urls[0].path)
        super.init(frame: frame)

        let close = NSButton(image: NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close")!,
                             target: self, action: #selector(closeTapped))
        close.isBordered = false
        close.contentTintColor = .secondaryLabelColor
        close.frame = NSRect(x: 6, y: frame.height - 26, width: 20, height: 20)
        close.autoresizingMask = [.maxXMargin, .minYMargin]
        addSubview(close)

        let request = QLThumbnailGenerator.Request(fileAt: urls[0], size: CGSize(width: 88, height: 88),
                                                   scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] rep, _ in
            guard let rep else { return }
            DispatchQueue.main.async { self?.icon = rep.nsImage; self?.needsDisplay = true }
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func closeTapped() { onClose() }

    override func draw(_ dirtyRect: NSRect) {
        let iconRect = NSRect(x: (bounds.width - 80) / 2, y: 44, width: 80, height: 80)
        icon.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1)
        if urls.count > 1 {
            let badge = NSRect(x: iconRect.maxX - 18, y: iconRect.maxY - 18, width: 24, height: 24)
            NSColor.systemRed.setFill()
            NSBezierPath(ovalIn: badge).fill()
            draw("\(urls.count)", in: badge.insetBy(dx: 0, dy: 5), size: 11, color: .white, bold: true)
        }
        let name = urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) items"
        draw(name, in: NSRect(x: 8, y: 14, width: bounds.width - 16, height: 24), size: 11, color: .labelColor, bold: false)
    }

    private func draw(_ text: String, in rect: NSRect, size: CGFloat, color: NSColor, bold: Bool) {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byTruncatingMiddle
        (text as NSString).draw(in: rect, withAttributes: [
            .font: bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size),
            .foregroundColor: color, .paragraphStyle: style,
        ])
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
        if event.clickCount == 2 { urls.forEach { NSWorkspace.shared.open($0) } }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownEvent else { return }
        let items = urls.map { url -> NSDraggingItem in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let origin = convert(start.locationInWindow, from: nil)
            item.setDraggingFrame(NSRect(x: origin.x - 32, y: origin.y - 32, width: 64, height: 64), contents: icon)
            return item
        }
        beginDraggingSession(with: items, event: start, source: self)
        mouseDownEvent = nil
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? [.copy, .move, .link, .generic] : [.copy, .generic]
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        // A move means the files left their original location, so the shelf has nothing left to hold.
        if operation == .move { onClose() }
    }
}
