import AppKit
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

/// A floating shelf that holds files while you work: drop files in, run Kaeru on them (results stay on the
/// shelf), then drag them out to wherever they belong.
struct ShelfItem: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    /// Made on this shelf (lives in its staging folder) rather than a file the user brought in.
    let staged: Bool
}

@MainActor
final class ShelfModel: ObservableObject, Identifiable {
    let id = UUID()
    @Published private(set) var items: [ShelfItem] = []
    @Published var selection: Set<UUID> = []
    @Published var dropTargeted = false
    @Published private(set) var thumbnails: [UUID: NSImage] = [:]

    /// Where Kaeru writes results of operations started from this shelf.
    lazy var stagingDirectory: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Kaeru/Shelves/\(id.uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    func add(_ urls: [URL], staged: Bool = false) {
        for url in urls where !items.contains(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) {
            let item = ShelfItem(url: url, staged: staged || isInStaging(url))
            items.append(item)
            loadThumbnail(for: item)
        }
    }

    /// Removing a file made on the shelf discards it; removing a file you brought in just takes it off the shelf.
    func remove(_ item: ShelfItem) {
        items.removeAll { $0.id == item.id }
        selection.remove(item.id)
        if item.staged { try? FileManager.default.removeItem(at: item.url) }
    }

    /// Drops items whose files have left (e.g. moved out by dragging to Finder).
    func pruneMissing() {
        let gone = items.filter { !FileManager.default.fileExists(atPath: $0.url.path) }
        items.removeAll { gone.contains($0) }
        gone.forEach { selection.remove($0.id) }
    }

    func contains(_ url: URL) -> Bool {
        isInStaging(url) || items.contains { $0.url.standardizedFileURL == url.standardizedFileURL }
    }

    private func isInStaging(_ url: URL) -> Bool {
        url.standardizedFileURL.path.hasPrefix(stagingDirectory.standardizedFileURL.path)
    }

    /// What a drag starting on `item` carries: the whole selection if the item is part of it.
    func dragItems(startingAt item: ShelfItem) -> [ShelfItem] {
        selection.contains(item.id) ? items.filter { selection.contains($0.id) } : [item]
    }

    func click(_ item: ShelfItem, extend: Bool) {
        if extend {
            if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
        } else {
            selection = [item.id]
        }
    }

    var stagedItems: [ShelfItem] { items.filter(\.staged) }

    private func loadThumbnail(for item: ShelfItem) {
        thumbnails[item.id] = NSWorkspace.shared.icon(forFile: item.url.path)
        let request = QLThumbnailGenerator.Request(fileAt: item.url, size: CGSize(width: 64, height: 64),
                                                   scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .all)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { rep, _ in
            guard let image = rep?.nsImage else { return }
            Task { @MainActor in self.thumbnails[item.id] = image }
        }
    }

    func discardStaging() {
        try? FileManager.default.removeItem(at: stagingDirectory)
    }
}

@MainActor
enum ShelfManager {
    private static var panels: [ShelfPanel] = []

    static func open(with urls: [URL], near point: NSPoint = NSEvent.mouseLocation) {
        let model = ShelfModel()
        model.add(urls)
        let panel = ShelfPanel(model: model)
        panels.append(panel)
        let size = panel.frame.size
        var origin = NSPoint(x: point.x + 24, y: point.y - size.height / 2)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(point) })?.visibleFrame {
            origin.x = min(max(origin.x, screen.minX + 8), screen.maxX - size.width - 8)
            origin.y = min(max(origin.y, screen.minY + 8), screen.maxY - size.height - 8)
        }
        panel.setFrameOrigin(origin)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.18; panel.animator().alphaValue = 1 }
    }

    /// The shelf that holds any of these files, so results of operations on them return to it.
    static func shelf(containing urls: [URL]) -> ShelfModel? {
        panels.map(\.model).first { shelf in urls.contains { shelf.contains($0) } }
    }

    static func close(_ panel: ShelfPanel) {
        let model = panel.model
        let staged = model.stagedItems.filter { FileManager.default.fileExists(atPath: $0.url.path) }
        if !staged.isEmpty {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = staged.count == 1 ? "Keep the file made on this shelf?" : "Keep the \(staged.count) files made on this shelf?"
            alert.informativeText = "You haven't dragged \(staged.count == 1 ? "it" : "them") anywhere yet."
            alert.addButton(withTitle: "Move to Downloads")
            alert.addButton(withTitle: "Discard")
            alert.addButton(withTitle: "Cancel")
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
                var moved: [URL] = []
                for item in staged {
                    let target = Output.unique(downloads.appendingPathComponent(item.url.lastPathComponent))
                    if (try? FileManager.default.moveItem(at: item.url, to: target)) != nil { moved.append(target) }
                }
                if !moved.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(moved) }
            case .alertSecondButtonReturn: break
            default: return
            }
        }
        model.discardStaging()
        panel.orderOut(nil)
        panels.removeAll { $0 === panel }
    }
}

final class ShelfPanel: NSPanel {
    let model: ShelfModel

    @MainActor
    init(model: ShelfModel) {
        self.model = model
        super.init(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        let host = NSHostingController(rootView: ShelfView(model: model) { [weak self] in
            guard let self else { return }
            MainActor.assumeIsolated { ShelfManager.close(self) }
        })
        host.sizingOptions = [.preferredContentSize]
        contentViewController = host
    }

    override var canBecomeKey: Bool { true }
}

private struct ShelfView: View {
    @ObservedObject var model: ShelfModel
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            if model.items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray.and.arrow.down").font(.system(size: 26, weight: .light)).foregroundStyle(.secondary)
                    Text("Drop files here").font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
                .background(WindowDragArea())
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(model.items) { item in ShelfRow(model: model, item: item) }
                    }
                    .padding(6)
                }
                .frame(height: min(CGFloat(model.items.count) * 54 + 12, 380))
            }
            Text(model.items.isEmpty ? "Files stay here until you drag them out." : "Drag out to save · ✨ to change a file · drop more in")
                .font(.system(size: 10.5)).foregroundStyle(.tertiary)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity)
                .background(WindowDragArea())
        }
        .frame(width: 300)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(model.dropTargeted ? Theme.brand.swiftUI : Color.secondary.opacity(0.25), lineWidth: model.dropTargeted ? 2 : 1))
        .onDrop(of: [.fileURL], isTargeted: $model.dropTargeted) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in model.add([url]) }
                }
            }
            return true
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(nsImage: Artwork.appMark(size: 18))
            Text("Shelf").font(.system(size: 13, weight: .semibold))
            if !model.items.isEmpty {
                Text("\(model.items.count)").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 1).background(Capsule().fill(.quaternary))
            }
            Spacer()
            if !model.items.isEmpty {
                headerButton("wand.and.stars", help: "Change all with Kaeru") {
                    WheelController.shared.show(urls: model.items.map(\.url), mode: .convert, at: NSEvent.mouseLocation, interactive: true)
                }
                ShelfDragHandle(model: model)
                    .frame(width: 24, height: 24)
                    .help("Drag everything out")
            }
            headerButton("xmark", help: "Close shelf", action: onClose)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        // Grab anywhere on the header (outside its buttons) to move the shelf.
        .background(WindowDragArea())
        .help("Drag to move the shelf")
    }

    private func headerButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11.5, weight: .semibold)).frame(width: 24, height: 24)
                .background(Circle().fill(.quaternary))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private struct ShelfRow: View {
    @ObservedObject var model: ShelfModel
    let item: ShelfItem

    var body: some View {
        let selected = model.selection.contains(item.id)
        HStack(spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let thumb = model.thumbnails[item.id] { Image(nsImage: thumb).resizable().aspectRatio(contentMode: .fit) }
                }
                .frame(width: 38, height: 38)
                if item.staged {
                    Image(systemName: "sparkles").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                        .padding(3).background(Circle().fill(Theme.brand.swiftUI)).offset(x: 4, y: 4)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.url.lastPathComponent).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                Text(subtitle).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
        .padding(.leading, 6)
        .padding(.trailing, 64)
        .overlay(ShelfDragArea(model: model, item: item))  // click, double-click, drag out
        .overlay(alignment: .trailing) {
            HStack(spacing: 4) {
                rowButton("wand.and.stars", help: "Change with Kaeru") {
                    WheelController.shared.show(urls: model.dragItems(startingAt: item).map(\.url), mode: .convert,
                                                at: NSEvent.mouseLocation, interactive: true)
                }
                rowButton("minus", help: item.staged ? "Discard" : "Remove from shelf") { model.remove(item) }
            }
            .padding(.trailing, 6)
        }
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(selected ? Theme.brand.swiftUI.opacity(0.16) : Color.clear))
    }

    private var subtitle: String {
        let size = Output.format(bytes: Output.size(of: item.url))
        return item.staged ? "New · \(size) · drag out to save" : "\(item.url.pathExtension.uppercased()) · \(size)"
    }

    private func rowButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).frame(width: 24, height: 24)
                .background(Circle().fill(.quaternary))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// AppKit drag source for one shelf row (or its selection).
private struct ShelfDragArea: NSViewRepresentable {
    let model: ShelfModel
    let item: ShelfItem
    func makeNSView(context: Context) -> ShelfDragView { ShelfDragView(model: model, items: { [model, item] in model.dragItems(startingAt: item) }, clickItem: item) }
    func updateNSView(_ view: ShelfDragView, context: Context) {}
}

/// The "drag everything" handle in the header.
private struct ShelfDragHandle: NSViewRepresentable {
    let model: ShelfModel
    func makeNSView(context: Context) -> ShelfDragView {
        let view = ShelfDragView(model: model, items: { [model] in model.items }, clickItem: nil)
        view.showsHandle = true
        return view
    }
    func updateNSView(_ view: ShelfDragView, context: Context) {}
}

final class ShelfDragView: NSView, NSDraggingSource {
    private let model: ShelfModel
    private let items: @MainActor () -> [ShelfItem]
    private let clickItem: ShelfItem?
    private var downEvent: NSEvent?
    private var dragging: [ShelfItem] = []
    var showsHandle = false

    init(model: ShelfModel, items: @escaping @MainActor () -> [ShelfItem], clickItem: ShelfItem?) {
        self.model = model
        self.items = items
        self.clickItem = clickItem
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        guard showsHandle else { return }
        NSColor.quaternaryLabelColor.setFill()
        NSBezierPath(ovalIn: bounds.insetBy(dx: 0.5, dy: 0.5)).fill()
        let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold).applying(.init(paletteColors: [.labelColor]))
        if let symbol = NSImage(systemSymbolName: "square.stack.3d.up", accessibilityDescription: "Drag all")?.withSymbolConfiguration(config) {
            let s = symbol.size
            symbol.draw(in: NSRect(x: bounds.midX - s.width / 2, y: bounds.midY - s.height / 2, width: s.width, height: s.height))
        }
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    override func mouseDown(with event: NSEvent) {
        downEvent = event
        if event.clickCount == 2, let clickItem { NSWorkspace.shared.open(clickItem.url) }
    }

    override func mouseUp(with event: NSEvent) {
        guard downEvent != nil, let clickItem else { return }
        downEvent = nil
        MainActor.assumeIsolated { model.click(clickItem, extend: event.modifierFlags.contains(.command)) }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = downEvent else { return }
        downEvent = nil
        dragging = MainActor.assumeIsolated { items() }
        guard !dragging.isEmpty else { return }
        let origin = convert(start.locationInWindow, from: nil)
        let draggingItems = dragging.enumerated().map { i, item -> NSDraggingItem in
            let dragItem = NSDraggingItem(pasteboardWriter: item.url as NSURL)
            let image = MainActor.assumeIsolated { model.thumbnails[item.id] } ?? NSWorkspace.shared.icon(forFile: item.url.path)
            let offset = CGFloat(min(i, 4)) * 6
            dragItem.setDraggingFrame(NSRect(x: origin.x - 24 + offset, y: origin.y - 24 - offset, width: 48, height: 48), contents: image)
            return dragItem
        }
        beginDraggingSession(with: draggingItems, event: start, source: self)
    }

    /// Files made on the shelf move to where they're dropped (so that's where they're saved); files you brought
    /// in are only copied, so dragging them out never relocates your originals.
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        guard context == .outsideApplication else { return [.copy, .generic] }
        return dragging.allSatisfy(\.staged) ? [.move, .copy, .generic] : [.copy, .link, .generic]
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [model] in
            MainActor.assumeIsolated { model.pruneMissing() }
        }
    }
}

/// A strip that moves its window when dragged. SwiftUI content inside a borderless panel swallows
/// the clicks that `isMovableByWindowBackground` relies on, so this hands them to the window directly.
private struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { WindowDragView() }
    func updateNSView(_ view: NSView, context: Context) {}
}

private final class WindowDragView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
}
