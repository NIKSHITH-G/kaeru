import AppKit
import QuickLookThumbnailing
import SwiftUI

/// A file you can drag out of a SwiftUI view, exactly like a file in Finder. Used by the tutorial.
struct DraggableFile: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> DraggableFileView { DraggableFileView(url: url) }
    func updateNSView(_ view: DraggableFileView, context: Context) {}
}

final class DraggableFileView: NSView, NSDraggingSource {
    let url: URL
    private var icon: NSImage
    private var downEvent: NSEvent?

    init(url: URL) {
        self.url = url
        icon = NSWorkspace.shared.icon(forFile: url.path)
        super.init(frame: .zero)
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 120, height: 120),
                                                   scale: 2, representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] rep, _ in
            guard let image = rep?.nsImage else { return }
            DispatchQueue.main.async { self?.icon = image; self?.needsDisplay = true }
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { NSSize(width: 120, height: 140) }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }

    override func draw(_ dirtyRect: NSRect) {
        let side = min(bounds.width, bounds.height - 22)
        let rect = NSRect(x: (bounds.width - side) / 2, y: 22, width: side, height: side)
        icon.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byTruncatingMiddle
        (url.lastPathComponent as NSString).draw(in: NSRect(x: 0, y: 0, width: bounds.width, height: 16), withAttributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.labelColor, .paragraphStyle: style,
        ])
    }

    override func mouseDown(with event: NSEvent) { downEvent = event }

    override func mouseDragged(with event: NSEvent) {
        guard let start = downEvent else { return }
        downEvent = nil
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        let p = convert(start.locationInWindow, from: nil)
        item.setDraggingFrame(NSRect(x: p.x - 40, y: p.y - 40, width: 80, height: 80), contents: icon)
        beginDraggingSession(with: [item], event: start, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        [.copy, .generic]
    }
}

/// A keycap, e.g. ⇧ or ⌘, drawn like the ones on Apple's keyboards.
struct KeyCap: View {
    let text: String
    var large = false

    var body: some View {
        Text(text)
            .font(.system(size: large ? 20 : 12, weight: .semibold, design: .rounded))
            .frame(minWidth: large ? 44 : 26, minHeight: large ? 40 : 22)
            .padding(.horizontal, large ? 8 : 4)
            .background(RoundedRectangle(cornerRadius: large ? 9 : 6, style: .continuous).fill(.background))
            .overlay(RoundedRectangle(cornerRadius: large ? 9 : 6, style: .continuous).strokeBorder(.separator))
            .shadow(color: .black.opacity(0.12), radius: 0, y: large ? 2 : 1)
    }
}

/// The coloured format pill used in the wheel and the Formats page.
struct FormatBadge: View {
    let ext: String
    var label: String?

    var body: some View {
        Text(label ?? ext.uppercased())
            .font(.system(size: 10.5, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Theme.category(forExt: ext).color.swiftUI))
    }
}

/// Wraps content in a rounded card on the window background.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.background.opacity(0.6)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.separator.opacity(0.6)))
    }
}

/// Wraps lines of chips onto new rows as needed.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 400
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { x = 0; y += row + spacing; row = 0 }
            x += size.width + spacing
            row = max(row, size.height)
        }
        return CGSize(width: width, height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += row + spacing; row = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            row = max(row, size.height)
        }
    }
}
