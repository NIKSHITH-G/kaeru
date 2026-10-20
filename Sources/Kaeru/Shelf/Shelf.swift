import AppKit
import Combine
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

/// A floating shelf that holds files while you work: drop files in, run Kaeru on them (results stay on the
/// shelf), then drag them out to wherever they belong.
///
/// It has three shapes: a compact glass tile showing the files as a fanned stack, an expanded list or grid,
/// and a small collapsed badge. Each shelf has its own name, colour and behaviour (see `ShelfSettings`).
struct ShelfItem: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    /// Made on this shelf (lives in its staging folder) rather than a file the user brought in.
    let staged: Bool
}

enum ShelfShape { case compact, expanded, collapsed }
enum ShelfLayout { case list, grid }

@MainActor
final class ShelfModel: ObservableObject, Identifiable {
    let id = UUID()
    @Published private(set) var items: [ShelfItem] = []
    @Published var selection: Set<UUID> = []
    @Published var dropTargeted = false
    /// Files currently being dragged out, shown dimmed until the drag ends.
    @Published var draggingOut: Set<UUID> = []
    @Published private(set) var thumbnails: [UUID: NSImage] = [:]

    // What the shelf looks like right now, and its own preferences.
    @Published var shape: ShelfShape = .compact
    /// Which screen edge the collapsed tab sits on.
    @Published var dockedRight = true
    @Published var layout: ShelfLayout = .list
    /// Empty means "use the first file's name".
    @Published var customName = ""
    @Published var colorIndex = 4
    @Published var alwaysShowIndicator = false
    /// A pinned shelf stays open when its last file is dragged out; others close themselves.
    @Published var pinned = false
    @Published var ownSpace = false { didSet { onSpaceChange?() } }
    var onSpaceChange: (() -> Void)?
    /// Opened by shaking the pointer: if the drag ends without dropping anything on it, it closes again.
    var openedByShake = false
    var onEmptied: (() -> Void)?

    /// Where Kaeru writes results of operations started from this shelf.
    lazy var stagingDirectory: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Kaeru/Shelves/\(id.uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static let colors: [Color] = [
        Color(white: 0.55), Color(red: 0.85, green: 0.45, blue: 0.2), Color(red: 0.88, green: 0.68, blue: 0.16),
        Color(red: 0.42, green: 0.78, blue: 0.2), Color(red: 0.13, green: 0.77, blue: 0.47), Color(red: 0.26, green: 0.5, blue: 0.95),
        Color(red: 0.5, green: 0.3, blue: 0.95), Color(red: 0.93, green: 0.45, blue: 0.4), Color(red: 0.93, green: 0.86, blue: 0.48),
        Color(red: 0.36, green: 0.5, blue: 0.3),
    ]
    var color: Color { Self.colors[colorIndex % Self.colors.count] }

    var name: String {
        if !customName.isEmpty { return customName }
        if items.count == 1 { return items[0].url.lastPathComponent }
        return items.isEmpty ? "Shelf" : "\(items.count) Files"
    }

    var totalSize: String { Output.format(bytes: items.reduce(0) { $0 + Output.size(of: $1.url) }) }

    func add(_ urls: [URL], staged: Bool = false) {
        let wasEmpty = items.isEmpty
        var added = 0, made = 0
        for url in urls where !items.contains(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) {
            let item = ShelfItem(url: url, staged: staged || isInStaging(url))
            withAnimation(.spring(response: 0.42, dampingFraction: 0.68)) { items.append(item) }
            loadThumbnail(for: item)
            added += 1
            if item.staged { made += 1 }
        }
        if made > 0 { ShelfSound.play(.made) } else if added > 0 { ShelfSound.play(.drop) }
        if added > 0 { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
        // Retract after first drop: the shelf tucks itself into the screen edge.
        if wasEmpty && added > 0 && made == 0 && Settings.shelfRetract && shape == .compact {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                MainActor.assumeIsolated { if self?.shape == .compact { self?.shape = .collapsed } }
            }
        }
    }

    /// Puts every file on the shelf (or just the selection) on the clipboard; paste in Finder to copy them.
    func copyAll() {
        let chosen = items.filter { selection.contains($0.id) }
        let files = (chosen.isEmpty ? items : chosen).map(\.url)
        guard !files.isEmpty else { return }
        let board = NSPasteboard.general
        board.clearContents()
        board.writeObjects(files as [NSURL])
        ShelfSound.play(.drop)
        Toast.show(files.count == 1 ? "Copied \(files[0].lastPathComponent). Paste in Finder to copy it there"
                                    : "Copied \(files.count) files. Paste in Finder to copy them there")
    }

    /// Takes a file off with the classic poof (the cloud at the pointer, and its sound).
    func poof(_ item: ShelfItem) {
        ShelfSound.play(.poof)
        PoofCloud.show(at: NSEvent.mouseLocation)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { remove(item) }
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

    /// After a drag out: an unpinned shelf whose files have all gone closes itself.
    func dragEnded(everything: Bool, moved: Bool) {
        pruneMissing()
        guard !pinned else { return }
        switch Settings.closeOnDragOut {
        case .always: if items.isEmpty || everything { onEmptied?() }
        case .moved: if items.isEmpty && moved { onEmptied?() }
        case .never: break
        }
    }

    /// What double-clicking a file does (Settings → Shelf).
    func openItem(_ url: URL) {
        switch Settings.doubleClickFile {
        case .open: NSWorkspace.shared.open(url)
        case .reveal: NSWorkspace.shared.activateFileViewerSelecting([url])
        case .quickLook: QuickLookPreview.show(url)
        }
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
        let request = QLThumbnailGenerator.Request(fileAt: item.url, size: CGSize(width: 220, height: 220),
                                                   scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .all)
        // Finder's own look: page edges, shadows and folded corners rather than a bare cropped preview.
        request.iconMode = true
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

    static func open(with urls: [URL], near point: NSPoint = NSEvent.mouseLocation, centered: Bool = false) {
        let model = ShelfModel()
        model.openedByShake = centered
        model.pinned = Settings.closeOnDragOut == .never
        model.ownSpace = !Settings.shelfAllSpaces
        model.add(urls)
        let panel = ShelfPanel(model: model)
        panels.append(panel)
        model.onEmptied = { [weak panel] in if let panel { close(panel) } }
        let size = panel.frame.size
        // Opened by a shake, the shelf appears under the pointer so the drag can land straight on it.
        var origin = centered ? NSPoint(x: point.x - size.width / 2, y: point.y - size.height / 2)
                              : NSPoint(x: point.x + 24, y: point.y - size.height / 2)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(point) })?.visibleFrame {
            origin.x = min(max(origin.x, screen.minX + 8), screen.maxX - size.width - 8)
            origin.y = min(max(origin.y, screen.minY + 8), screen.maxY - size.height - 8)
        }
        panel.setFrameOrigin(origin)
        panel.popIn()
        ShelfSound.play(.open)
    }

    /// The shelf that collects new screenshots; reused while it's open.
    private static weak var screenshotShelf: ShelfModel?

    /// Adds new screenshots to the screenshot shelf, opening it in the bottom-right corner if needed.
    static func addScreenshots(_ urls: [URL]) {
        if let shelf = screenshotShelf, panels.contains(where: { $0.model === shelf }) {
            shelf.add(urls)
            return
        }
        guard let screen = NSScreen.main?.visibleFrame else { return }
        open(with: urls, near: NSPoint(x: screen.maxX - 140, y: screen.minY + 140), centered: true)
        if let model = panels.last?.model {
            model.openedByShake = false
            model.customName = "Screenshots"
            screenshotShelf = model
        }
    }

    /// After a drag ends: shelves opened by a shake that nothing was dropped on close themselves.
    static func closeUnusedShakeShelves() {
        for panel in panels where panel.model.openedByShake {
            if panel.model.items.isEmpty { close(panel) } else { panel.model.openedByShake = false }
        }
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
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.15; panel.animator().alphaValue = 0 }) {
            MainActor.assumeIsolated {
                panel.orderOut(nil)
                panels.removeAll { $0 === panel }
            }
        }
    }
}

final class ShelfPanel: NSPanel {
    let model: ShelfModel

    @MainActor
    init(model: ShelfModel) {
        self.model = model
        super.init(contentRect: NSRect(x: 0, y: 0, width: 220, height: 220), styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        isMovableByWindowBackground = true
        // Clicks go straight to the shelf instead of first activating it; it only becomes key when
        // something needs typing (the shelf name).
        becomesKeyOnlyIfNeeded = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        applySpaceBehaviour()
        model.onSpaceChange = { [weak self] in MainActor.assumeIsolated { self?.applySpaceBehaviour() } }
        shapeWatch = model.$shape.dropFirst().removeDuplicates().sink { [weak self] shape in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.shapeChanged(to: shape) } }
        }
        let host = NSHostingController(rootView: ShelfView(model: model) { [weak self] in
            guard let self else { return }
            MainActor.assumeIsolated { ShelfManager.close(self) }
        })
        host.sizingOptions = [.preferredContentSize]
        contentViewController = host
    }

    /// Follow you to every Space, or stay in the one it was opened in.
    @MainActor
    private func applySpaceBehaviour() {
        collectionBehavior = model.ownSpace ? [.managed, .fullScreenAuxiliary] : [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { true }
    // The panel never steals focus from the app you're working in.
    override var canBecomeMain: Bool { false }

    private var shapeWatch: AnyCancellable?
    /// Where the shelf was before it collapsed, to return there.
    private var restoreOrigin: NSPoint?
    /// Set while the shelf positions itself, so the resize rule below stays out of the way.
    private var placing = false

    @MainActor
    private func shapeChanged(to shape: ShelfShape) {
        guard let screen = (screen ?? NSScreen.main)?.visibleFrame else { return }
        let size = contentViewController?.preferredContentSize ?? frame.size
        placing = true
        defer { placing = false }
        if shape == .collapsed {
            restoreOrigin = frame.origin
            let right = frame.midX > screen.midX
            model.dockedRight = right
            let tab = NSSize(width: 26, height: 96)
            let target = NSRect(x: right ? screen.maxX - tab.width : screen.minX, y: min(max(frame.maxY - tab.height - 40, screen.minY), screen.maxY - tab.height),
                                width: tab.width, height: tab.height)
            setFrame(target, display: true, animate: true)
        } else if let origin = restoreOrigin, frame.width < 40 {
            restoreOrigin = nil
            var target = NSRect(origin: origin, size: size)
            target.origin.x = min(max(target.minX, screen.minX + 4), screen.maxX - size.width - 4)
            target.origin.y = min(max(target.minY, screen.minY + 4), screen.maxY - size.height - 4)
            setFrame(target, display: true, animate: true)
        }
    }

    /// When the shelf changes shape its window resizes; keep the top edge where it is (macOS would keep the
    /// bottom), and keep the whole shelf on screen.
    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        var frame = frameRect
        if isVisible, !placing, frame.size != self.frame.size, model.shape != .collapsed, self.frame.width > 40 {
            frame.origin.y = self.frame.maxY - frame.height
            frame.origin.x = self.frame.minX
            if let screen = screen?.visibleFrame {
                frame.origin.x = min(max(frame.minX, screen.minX + 4), screen.maxX - frame.width - 4)
                frame.origin.y = min(max(frame.minY, screen.minY + 4), screen.maxY - frame.height - 4)
            }
        }
        super.setFrame(frame, display: flag)
    }

    /// Snap into place: let go near a screen edge and the shelf settles neatly against it.
    @MainActor
    func snapToEdge() {
        guard Settings.shelfSnap, model.shape != .collapsed, let screen = screen?.visibleFrame else { return }
        let margin: CGFloat = 10, reach: CGFloat = 60
        var target = frame
        if frame.minX - screen.minX < reach { target.origin.x = screen.minX + margin }
        if screen.maxX - frame.maxX < reach { target.origin.x = screen.maxX - frame.width - margin }
        if frame.minY - screen.minY < reach { target.origin.y = screen.minY + margin }
        if screen.maxY - frame.maxY < reach { target.origin.y = screen.maxY - frame.height - margin }
        guard target.origin != frame.origin else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 1.1, 0.4, 1)
            animator().setFrameOrigin(target.origin)
        }
    }

    /// Springs up from 90%, about its centre.
    @MainActor
    func popIn() {
        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.2; animator().alphaValue = 1 }
        guard let layer = contentView?.layer ?? { contentView?.wantsLayer = true; return contentView?.layer }() else { return }
        let size = frame.size
        var from = CATransform3DMakeTranslation(size.width / 2, size.height / 2, 0)
        from = CATransform3DScale(from, 0.9, 0.9, 1)
        from = CATransform3DTranslate(from, -size.width / 2, -size.height / 2, 0)
        let spring = CASpringAnimation(keyPath: "transform")
        spring.fromValue = from
        spring.toValue = CATransform3DIdentity
        spring.damping = 17
        spring.stiffness = 260
        spring.duration = spring.settlingDuration
        layer.add(spring, forKey: "pop")
    }
}

// MARK: - Views

private struct ShelfView: View {
    @ObservedObject var model: ShelfModel
    let onClose: () -> Void

    var body: some View {
        Group {
            switch model.shape {
            case .collapsed: CollapsedShelf(model: model)
            case .expanded: ExpandedShelf(model: model, onClose: onClose)
            case .compact: CompactShelf(model: model, onClose: onClose)
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: model.shape)
        // A click on the trackpad as files arrive over the shelf (Force Touch trackpads).
        .onChange(of: model.dropTargeted) { over in
            if over { NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now) }
        }
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
}

/// Frosted glass with a hairline edge. It stays still while files are dragged over it.
private struct ShelfGlass: ViewModifier {
    @ObservedObject var model: ShelfModel
    let radius: CGFloat
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Color.glass(0.18), lineWidth: 1))
    }
}

/// A round glass button, as in the corners of the compact shelf.
private struct GlassButton: View {
    let symbol: String
    var size: CGFloat = 34
    var help = ""
    let action: () -> Void
    @StateObject private var hover = Flag()
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: size * 0.36, weight: .semibold))
                .frame(width: size, height: size)
                .background(Circle().fill(Color.glass(hover.on ? 0.22 : 0.12)))
                .overlay(Circle().strokeBorder(Color.glass(0.12)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hover.on = $0 }
        .help(help)
    }
}

// MARK: Compact

private struct CompactShelf: View {
    @ObservedObject var model: ShelfModel
    let onClose: () -> Void

    var body: some View {
        ZStack {
            WindowDragArea()
            if model.items.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tray.and.arrow.down").font(.system(size: 34, weight: .light)).foregroundStyle(.secondary)
                        // Files hovering over: the tray lifts to catch them.
                        .offset(y: model.dropTargeted ? -8 : 0)
                        .scaleEffect(model.dropTargeted ? 1.12 : 1)
                        .animation(.spring(response: 0.32, dampingFraction: 0.6), value: model.dropTargeted)
                    Text("Drop files here").font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                }
                .allowsHitTesting(false)
            } else {
                // The stack: drag it to take every file out; click it to see them all.
                FileStack(model: model)
                    .frame(width: 120, height: 120)
                    .overlay(ShelfDragArea(model: model, items: { [model] in model.items }, onClick: { [model] _ in model.shape = .expanded },
                                           onDoubleClick: { [model] in if let first = model.items.last { model.openItem(first.url) } }))
                    .offset(y: -2)
            }
            VStack {
                HStack {
                    GlassButton(symbol: "xmark", help: "Close shelf", action: onClose)
                    Spacer()
                    if model.alwaysShowIndicator { Circle().fill(model.color).frame(width: 9, height: 9) }
                    Spacer()
                    GlassButton(symbol: "chevron.down", help: "Collapse") { model.shape = .collapsed }
                }
                Spacer()
                HStack(spacing: 8) {
                    if !model.items.isEmpty {
                        GlassButton(symbol: "doc.on.doc", size: 32, help: "Copy all files") { model.copyAll() }
                        NamePill(model: model)
                        GlassButton(symbol: "wand.and.stars", size: 32, help: "Change with Kaeru") {
                            WheelController.shared.show(urls: model.items.map(\.url), mode: .convert, at: NSEvent.mouseLocation, interactive: true)
                        }
                    }
                }
            }
            .padding(14)
            VStack { Capsule().fill(Color.glass(0.35)).frame(width: 40, height: 5).padding(.top, 7); Spacer() }
                .allowsHitTesting(false)
        }
        .frame(width: 220, height: 220)
        .modifier(ShelfGlass(model: model, radius: 30))
    }
}

/// Up to three thumbnails fanned like a little pile of papers.
private struct FileStack: View {
    @ObservedObject var model: ShelfModel
    var body: some View {
        let top = Array(model.items.suffix(3))
        // New files drop onto the pile with a little bounce.
        ZStack {
            ForEach(Array(top.enumerated()), id: \.element.id) { index, item in
                let depth = top.count - 1 - index
                Group {
                    if let thumb = model.thumbnails[item.id] { Image(nsImage: thumb).resizable().aspectRatio(contentMode: .fit) }
                }
                .frame(width: 104, height: 104)
                .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
                .opacity(model.draggingOut.contains(item.id) ? 0.35 : 1)
                // Files hovering over: the pile fans apart to make room for them.
                .rotationEffect(.degrees(Double(depth) * (index % 2 == 0 ? -7 : 7) * (model.dropTargeted ? 1.8 : 1)))
                .offset(x: CGFloat(depth) * (index % 2 == 0 ? -8 : 8) * (model.dropTargeted ? 2.2 : 1),
                        y: CGFloat(depth) * -4 + (model.dropTargeted && depth == 0 ? 6 : 0))
                .scaleEffect(1 - CGFloat(depth) * 0.06)
                .transition(.asymmetric(insertion: .scale(scale: 1.35).combined(with: .opacity).combined(with: .offset(y: -26)),
                                        removal: .scale(scale: 0.4).combined(with: .opacity)))
                .overlay(alignment: .bottomTrailing) {
                    if depth == 0 && item.staged {
                        Image(systemName: "sparkles").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                            .padding(5).background(Circle().fill(Theme.brand.swiftUI)).offset(x: 4, y: 4)
                    }
                }
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.7), value: top.map(\.id))
        .animation(.spring(response: 0.32, dampingFraction: 0.65), value: model.dropTargeted)
        .allowsHitTesting(false)
    }
}

/// The name of the shelf's file (or "3 Files") with a chevron; opens the full list.
private struct NamePill: View {
    @ObservedObject var model: ShelfModel
    @StateObject private var hover = Flag()
    var body: some View {
        Button { if !model.items.isEmpty { model.shape = .expanded } } label: {
            HStack(spacing: 6) {
                Text(model.name).font(.system(size: 13)).lineLimit(1).truncationMode(.head)
                if !model.items.isEmpty { Image(systemName: "chevron.right").font(.system(size: 9.5, weight: .bold)).opacity(0.7) }
            }
            .padding(.horizontal, 14).frame(height: 32)
            .background(Capsule().fill(Color.glass(hover.on ? 0.2 : 0.12)))
            .overlay(Capsule().strokeBorder(Color.glass(0.12)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover.on = $0 }
        .frame(maxWidth: 112)
        .help(model.items.isEmpty ? "" : "Show all files")
    }
}

// MARK: Expanded

private struct ExpandedShelf: View {
    @ObservedObject var model: ShelfModel
    let onClose: () -> Void
    @StateObject private var settings = Flag()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                GlassButton(symbol: "chevron.left", size: 36, help: "Back") { model.shape = .compact }
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.items.count == 1 ? "1 File" : "\(model.items.count) Files").font(.system(size: 15, weight: .semibold))
                    Text(model.totalSize).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                GlassButton(symbol: "doc.on.doc", size: 36, help: "Copy all files (or the selected ones)") { model.copyAll() }
                GlassButton(symbol: "wand.and.stars", size: 36, help: "Change all with Kaeru") {
                    WheelController.shared.show(urls: model.items.map(\.url), mode: .convert, at: NSEvent.mouseLocation, interactive: true)
                }
                GlassButton(symbol: "slider.horizontal.3", size: 36, help: "Shelf settings") { settings.on.toggle() }
                    .popover(isPresented: $settings.on, arrowEdge: .trailing) { ShelfSettings(model: model) }
                HStack(spacing: 2) {
                    layoutButton(.grid, "square.grid.2x2")
                    layoutButton(.list, "list.bullet")
                }
                .padding(3)
                .background(Capsule().fill(Color.glass(0.1)))
            }
            .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 10)
            .background(WindowDragArea())

            ScrollView {
                if model.layout == .list {
                    VStack(spacing: 2) {
                        ForEach(model.items) { ShelfRow(model: model, item: $0)
                            .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity),
                                                    removal: .scale(scale: 0.6, anchor: .leading).combined(with: .opacity))) }
                    }
                    .padding(.horizontal, 8)
                    .animation(.spring(response: 0.3, dampingFraction: 0.85), value: model.items.map(\.id))
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 10) {
                        ForEach(model.items) { ShelfTile(model: model, item: $0).transition(.scale(scale: 0.8).combined(with: .opacity)) }
                        RevealTile(model: model)
                    }
                    .animation(.spring(response: 0.3, dampingFraction: 0.85), value: model.items.map(\.id))
                    .padding(.horizontal, 12)
                }
            }
            .frame(height: contentHeight)

            Text("Drag out to save · ✨ to change a file · drop more in")
                .font(.system(size: 10.5)).foregroundStyle(.tertiary)
                .padding(.vertical, 8).frame(maxWidth: .infinity)
                .background(WindowDragArea())
        }
        .frame(width: 400)
        .modifier(ShelfGlass(model: model, radius: 26))
    }

    private var contentHeight: CGFloat {
        let n = CGFloat(max(model.items.count, 1))
        // The grid has one extra tile (Reveal in Finder) and rows of three.
        return model.layout == .list ? min(n * 46 + 8, 360) : min(ceil((n + 1) / 3) * 134 + 8, 420)
    }

    private func layoutButton(_ layout: ShelfLayout, _ symbol: String) -> some View {
        Button { model.layout = layout } label: {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).frame(width: 30, height: 28)
                .background(Capsule().fill(model.layout == layout ? Color.glass(0.22) : .clear))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct ShelfRow: View {
    @ObservedObject var model: ShelfModel
    let item: ShelfItem
    @StateObject private var hover = Flag()

    var body: some View {
        let selected = model.selection.contains(item.id)
        HStack(spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                Group { if let thumb = model.thumbnails[item.id] { Image(nsImage: thumb).resizable().aspectRatio(contentMode: .fit) } }
                    .frame(width: 30, height: 30)
                if item.staged {
                    Image(systemName: "sparkles").font(.system(size: 7, weight: .bold)).foregroundStyle(.white)
                        .padding(2.5).background(Circle().fill(Theme.brand.swiftUI)).offset(x: 3, y: 3)
                }
            }
            Text(item.url.lastPathComponent).font(.system(size: 13)).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 8)
            if !hover.on {
                Text(item.staged ? "New · \(Output.format(bytes: Output.size(of: item.url)))" : Output.format(bytes: Output.size(of: item.url)))
                    .font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.55))
            }
        }
        .padding(.vertical, 7).padding(.leading, 8).padding(.trailing, hover.on ? 70 : 10)
        .overlay(ShelfDragArea(model: model, items: { [model, item] in model.dragItems(startingAt: item) },
                               onClick: { [model, item] event in model.click(item, extend: event.modifierFlags.contains(.command)) },
                               onDoubleClick: { [model, item] in model.openItem(item.url) }))
        .overlay(alignment: .trailing) {
            if hover.on {
                HStack(spacing: 4) {
                    GlassButton(symbol: "wand.and.stars", size: 26, help: "Change with Kaeru") {
                        WheelController.shared.show(urls: model.dragItems(startingAt: item).map(\.url), mode: .convert,
                                                    at: NSEvent.mouseLocation, interactive: true)
                    }
                    GlassButton(symbol: "minus", size: 26, help: item.staged ? "Discard" : "Remove from shelf") { model.poof(item) }
                }
                .padding(.trailing, 6)
            }
        }
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(selected ? Theme.brand.swiftUI.opacity(0.2) : (hover.on ? Color.glass(0.07) : .clear)))
        .onHover { hover.on = $0 }
    }
}

private struct ShelfTile: View {
    @ObservedObject var model: ShelfModel
    let item: ShelfItem
    @StateObject private var hover = Flag()

    var body: some View {
        let selected = model.selection.contains(item.id)
        VStack(spacing: 5) {
            Group { if let thumb = model.thumbnails[item.id] { Image(nsImage: thumb).resizable().aspectRatio(contentMode: .fit) } }
                .frame(width: 80, height: 80)
                .opacity(model.draggingOut.contains(item.id) ? 0.35 : 1)
            VStack(spacing: 2) {
                Text(item.url.lastPathComponent).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                Text(Output.format(bytes: Output.size(of: item.url))).font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.55))
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity)
        .overlay(ShelfDragArea(model: model, items: { [model, item] in model.dragItems(startingAt: item) },
                               onClick: { [model, item] event in model.click(item, extend: event.modifierFlags.contains(.command)) },
                               onDoubleClick: { [model, item] in model.openItem(item.url) }))
        .overlay(alignment: .topTrailing) {
            if hover.on {
                VStack(spacing: 4) {
                    GlassButton(symbol: "wand.and.stars", size: 22, help: "Change with Kaeru") {
                        WheelController.shared.show(urls: model.dragItems(startingAt: item).map(\.url), mode: .convert,
                                                    at: NSEvent.mouseLocation, interactive: true)
                    }
                    GlassButton(symbol: "minus", size: 22, help: "Remove") { model.poof(item) }
                }
                .padding(2)
            }
        }
        .overlay(alignment: .topLeading) {
            if item.staged {
                Image(systemName: "sparkles").font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
                    .padding(3).background(Circle().fill(Theme.brand.swiftUI)).padding(4)
            }
        }
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(selected ? Theme.brand.swiftUI.opacity(0.2) : (hover.on ? Color.glass(0.07) : .clear)))
        .onHover { hover.on = $0 }
    }
}

/// "Reveal in Finder" for everything on the shelf (or the selection), as the last tile of the grid.
private struct RevealTile: View {
    @ObservedObject var model: ShelfModel
    @StateObject private var hover = Flag()
    var body: some View {
        Button {
            let chosen = model.items.filter { model.selection.contains($0.id) }
            NSWorkspace.shared.activateFileViewerSelecting((chosen.isEmpty ? model.items : chosen).map(\.url))
        } label: {
            VStack(spacing: 8) {
                Image(systemName: "arrowshape.turn.up.right.circle").font(.system(size: 44, weight: .light))
                    .foregroundStyle(Color.primary.opacity(hover.on ? 0.85 : 0.55))
                    .frame(height: 76)
                Text("Reveal in Finder").font(.system(size: 12)).lineLimit(1)
            }
            .padding(6).frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(hover.on ? Color.glass(0.07) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover.on = $0 }
    }
}

/// Per-shelf preferences, shown in a popover from the expanded shelf.
private struct ShelfSettings: View {
    @ObservedObject var model: ShelfModel

    var body: some View {
        VStack(spacing: 12) {
            section {
                HStack {
                    Text("Shelf name")
                    Spacer()
                    TextField(model.name, text: $model.customName)
                        .textFieldStyle(.roundedBorder).frame(width: 190)
                }
            }
            section {
                switchRow("Always show indicator", $model.alwaysShowIndicator)
                Divider()
                HStack(alignment: .top) {
                    Text("Indicator color")
                    Spacer()
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(24), spacing: 10), count: 5), spacing: 10) {
                        ForEach(ShelfModel.colors.indices, id: \.self) { i in
                            Button { model.colorIndex = i } label: {
                                Circle().fill(ShelfModel.colors[i]).frame(width: 20, height: 20)
                                    .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: model.colorIndex == i ? 2.5 : 0).padding(-3))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(width: 166)
                }
            }
            section {
                switchRow("Pin Shelf", $model.pinned)
                    .help("Keep this shelf open after its last file is dragged out")
                Divider()
                switchRow("Keep Shelf in own Space", $model.ownSpace)
                    .help("Stay in the Space it was opened in instead of following you")
            }
            Text("These preferences apply only to this shelf.").font(.system(size: 11.5)).foregroundStyle(Theme.brand.swiftUI)
        }
        .font(.system(size: 13))
        .padding(16)
        .frame(width: 360)
    }

    private func switchRow(_ title: String, _ value: Binding<Bool>) -> some View {
        HStack {
            Text(title)
            Spacer()
            Toggle(title, isOn: value).toggleStyle(.switch).labelsHidden().controlSize(.small)
        }
    }

    private func section<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) { content() }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.05)))
    }
}

// MARK: Collapsed

/// Collapsed: a slim tab tucked against the screen edge. Click it to bring the shelf back where it was;
/// drag it up or down the edge to move it.
private struct CollapsedShelf: View {
    @ObservedObject var model: ShelfModel
    var body: some View {
        let onRight = model.dockedRight
        ZStack {
            UnevenRoundedRectangle(topLeadingRadius: onRight ? 14 : 0, bottomLeadingRadius: onRight ? 14 : 0,
                                   bottomTrailingRadius: onRight ? 0 : 14, topTrailingRadius: onRight ? 0 : 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(UnevenRoundedRectangle(topLeadingRadius: onRight ? 14 : 0, bottomLeadingRadius: onRight ? 14 : 0,
                                                bottomTrailingRadius: onRight ? 0 : 14, topTrailingRadius: onRight ? 0 : 14, style: .continuous)
                    .strokeBorder(Color.glass(0.18)))
            VStack(spacing: 8) {
                if model.alwaysShowIndicator || !model.items.isEmpty { Circle().fill(model.color).frame(width: 7, height: 7) }
                Image(systemName: onRight ? "chevron.left" : "chevron.right").font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.primary.opacity(0.55))
                if !model.items.isEmpty { Text("\(model.items.count)").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary) }
            }
            ClickOrMoveArea { model.shape = .compact }
        }
        .frame(width: 26, height: 96)
        .help("\(model.name). Click to open")
    }
}

private extension Color {
    /// A see-through tint that reads on frosted glass in both modes: light on dark, dark on light.
    static func glass(_ amount: Double) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(white: 1, alpha: amount) : NSColor(white: 0, alpha: amount * 0.55)
        })
    }
}

/// A bit of view state (hover, a popover) kept in an object, since `@State` needs a compiler plugin
/// the Command Line Tools don't ship.
private final class Flag: ObservableObject { @Published var on = false }

// MARK: - AppKit helpers

/// AppKit drag source for a file, the selection, or the whole shelf, with click and double-click.
private struct ShelfDragArea: NSViewRepresentable {
    let model: ShelfModel
    let items: @MainActor () -> [ShelfItem]
    let onClick: (NSEvent) -> Void
    let onDoubleClick: () -> Void
    func makeNSView(context: Context) -> ShelfDragView {
        ShelfDragView(model: model, items: items, onClick: onClick, onDoubleClick: onDoubleClick)
    }
    func updateNSView(_ view: ShelfDragView, context: Context) {}
}

final class ShelfDragView: NSView, NSDraggingSource {
    private let model: ShelfModel
    private let items: @MainActor () -> [ShelfItem]
    private let onClick: (NSEvent) -> Void
    private let onDoubleClick: () -> Void
    private var downEvent: NSEvent?
    private var dragging: [ShelfItem] = []

    init(model: ShelfModel, items: @escaping @MainActor () -> [ShelfItem], onClick: @escaping (NSEvent) -> Void,
         onDoubleClick: @escaping () -> Void) {
        self.model = model
        self.items = items
        self.onClick = onClick
        self.onDoubleClick = onDoubleClick
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    override func mouseDown(with event: NSEvent) {
        downEvent = event
        if event.clickCount == 2 { downEvent = nil; onDoubleClick() }
    }

    override func mouseUp(with event: NSEvent) {
        guard downEvent != nil else { return }
        downEvent = nil
        onClick(event)
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
            dragItem.setDraggingFrame(NSRect(x: origin.x - 28 + offset, y: origin.y - 28 - offset, width: 56, height: 56), contents: image)
            return dragItem
        }
        let ids = Set(dragging.map(\.id))
        MainActor.assumeIsolated { withAnimation(.easeOut(duration: 0.15)) { model.draggingOut = ids } }
        beginDraggingSession(with: draggingItems, event: start, source: self)
    }

    /// Files made on the shelf move to where they're dropped (so that's where they're saved); files you brought
    /// in are only copied, so dragging them out never relocates your originals.
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        // Only real moves and copies: offering .link or .generic lets Finder drop an alias instead of the file.
        guard context == .outsideApplication else { return .copy }
        return dragging.allSatisfy(\.staged) ? [.move, .copy] : .copy
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        MainActor.assumeIsolated { withAnimation(.easeOut(duration: 0.2)) { model.draggingOut = [] } }
        // Dropped back into the folder it came from, Finder makes "name 2.ext"; that's never wanted from a shelf.
        if operation.contains(.copy) {
            let originals = dragging.filter { !$0.staged }.map(\.url)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { ShelfDragView.trashDuplicates(of: originals) }
        }
        // Dropped somewhere real (not cancelled, not back on the shelf): an unpinned shelf closes once everything left.
        let landedOutside = !operation.isEmpty && !(window?.frame.contains(screenPoint) ?? false)
        let everything = landedOutside && MainActor.assumeIsolated { dragging.count == model.items.count }
        let moved = landedOutside && operation.contains(.move)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [model] in
            MainActor.assumeIsolated { model.dragEnded(everything: everything, moved: moved) }
        }
    }
}

extension ShelfDragView {
    /// Moves to the Trash any copy Finder just made next to an original: "name 2.ext" or "name copy.ext",
    /// created in the last few seconds, the same size as the original.
    static func trashDuplicates(of originals: [URL]) {
        let fm = FileManager.default
        for url in originals {
            let base = url.deletingPathExtension().lastPathComponent, ext = url.pathExtension
            let dir = url.deletingLastPathComponent()
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
            let names = ["\(base) copy"] + (2...30).map { "\(base) \($0)" }
            for name in names {
                let candidate = dir.appendingPathComponent(ext.isEmpty ? name : "\(name).\(ext)")
                guard let values = try? candidate.resourceValues(forKeys: [.creationDateKey, .fileSizeKey]),
                      let created = values.creationDate, Date().timeIntervalSince(created) < 5,
                      values.fileSize == size else { continue }
                try? fm.trashItem(at: candidate, resultingItemURL: nil)
            }
        }
    }
}

/// The shelf's sounds, all built into macOS: Pop for opening and drops, the Dock's poof for removing,
/// Glass when a file you changed arrives. Switched off in Settings → Shelf.
@MainActor
enum ShelfSound {
    enum Kind { case open, drop, poof, made }
    private static var cache: [Kind: NSSound] = [:]

    static func play(_ kind: Kind) {
        guard Settings.shelfSounds else { return }
        if cache[kind] == nil {
            let path: String
            switch kind {
            case .open, .drop: path = "/System/Library/Sounds/Pop.aiff"
            case .made: path = "/System/Library/Sounds/Glass.aiff"
            case .poof: path = "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/dock/poof item off dock.aif"
            }
            cache[kind] = NSSound(contentsOfFile: path, byReference: true)
        }
        guard let sound = cache[kind] else { return }
        sound.volume = kind == .open ? 0.35 : 0.55
        sound.stop()
        sound.play()
    }
}

/// The classic puff of smoke from dragging an icon off the Dock, drawn where a file was removed.
@MainActor
enum PoofCloud {
    static func show(at point: NSPoint) {
        let size: CGFloat = 64
        let panel = NSPanel(contentRect: NSRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        let view = NSView(frame: NSRect(x: 0, y: 0, width: size, height: size))
        view.wantsLayer = true
        // A few soft grey puffs that billow out and fade.
        for k in 0..<5 {
            let puff = CALayer()
            let s: CGFloat = 22
            puff.frame = CGRect(x: size / 2 - s / 2, y: size / 2 - s / 2, width: s, height: s)
            puff.cornerRadius = s / 2
            puff.backgroundColor = NSColor(white: 0.85, alpha: 0.9).cgColor
            view.layer?.addSublayer(puff)
            let angle = CGFloat(k) / 5 * 2 * .pi + 0.4
            let move = CABasicAnimation(keyPath: "position")
            move.toValue = CGPoint(x: size / 2 + cos(angle) * 20, y: size / 2 + sin(angle) * 20)
            let grow = CABasicAnimation(keyPath: "transform.scale")
            grow.fromValue = 0.4; grow.toValue = 1.5
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.95; fade.toValue = 0
            let group = CAAnimationGroup()
            group.animations = [move, grow, fade]
            group.duration = 0.42
            group.timingFunction = CAMediaTimingFunction(name: .easeOut)
            group.fillMode = .forwards
            group.isRemovedOnCompletion = false
            puff.add(group, forKey: "poof")
        }
        panel.contentView = view
        panel.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { panel.orderOut(nil) }
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
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        guard let panel = window as? ShelfPanel else { window?.performDrag(with: event); return }
        if event.clickCount == 2 {
            MainActor.assumeIsolated { if Settings.doubleClickEdgeCollapses { panel.model.shape = .collapsed } }
            return
        }
        panel.performDrag(with: event)  // returns when the mouse is released
        MainActor.assumeIsolated { panel.snapToEdge() }
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
}

/// Quick Look for a file, via the system's own previewer.
enum QuickLookPreview {
    static func show(_ url: URL) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/qlmanage")
        task.arguments = ["-p", url.path]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
    }
}

/// Click to act, or drag to move the window (the collapsed badge).
private struct ClickOrMoveArea: NSViewRepresentable {
    let action: () -> Void
    func makeNSView(context: Context) -> ClickOrMoveView { ClickOrMoveView(action: action) }
    func updateNSView(_ view: ClickOrMoveView, context: Context) {}
}

private final class ClickOrMoveView: NSView {
    private let action: () -> Void
    private var down: NSEvent?
    init(action: @escaping () -> Void) { self.action = action; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { down = event }
    override func mouseDragged(with event: NSEvent) {
        guard let start = down else { return }
        down = nil
        window?.performDrag(with: start)
    }
    override func mouseUp(with event: NSEvent) {
        guard down != nil else { return }
        down = nil
        action()
    }
}
