import AppKit
import QuickLookThumbnailing

/// Owns the floating wheel window: shows it under the cursor, swaps modes, and hands drops to the JobCenter.
@MainActor
final class WheelController {
    static let shared = WheelController()

    private(set) var urls: [URL] = []
    private(set) var mode: WheelMode = .convert
    /// Interactive wheels (hotkey, Dock, main window) are driven by clicks and keys instead of a drag.
    private(set) var interactive = false
    private var panel: WheelPanel?
    private var view: WheelView?
    private var glass: NSVisualEffectView?

    var isVisible: Bool { panel?.isVisible == true }

    func show(urls: [URL], mode: WheelMode, at point: NSPoint, interactive: Bool) {
        guard !urls.isEmpty else { return }
        self.urls = urls
        self.mode = mode
        self.interactive = interactive

        // Size the window for the busiest mode so switching modes never resizes it.
        let counts = WheelMode.allCases.map { Registry.operations(for: urls, mode: $0).count }
        let size = WheelView.size(forItems: counts.max() ?? 0)

        let panel = self.panel ?? WheelPanel()
        self.panel = panel
        let view = self.view ?? WheelView(frame: .zero)
        self.view = view
        let glass = self.glass ?? {
            let g = NSVisualEffectView()
            g.material = .hudWindow
            g.blendingMode = .behindWindow
            g.state = .active
            return g
        }()
        self.glass = glass
        if panel.contentView?.subviews.contains(view) != true {
            let root = NSView()
            root.wantsLayer = true
            root.addSubview(glass)
            root.addSubview(view)
            panel.contentView = root
        }
        panel.interactive = interactive

        // Put the disc's centre (not the window's) under the cursor; the caption hangs below.
        var frame = NSRect(x: point.x - size.width / 2, y: point.y - WheelView.captionHeight - size.width / 2,
                           width: size.width, height: size.height)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(point) })?.visibleFrame {
            frame.origin.x = min(max(frame.minX, screen.minX), screen.maxX - size.width)
            frame.origin.y = min(max(frame.minY, screen.minY), screen.maxY - size.height)
        }
        panel.setFrame(frame, display: false)
        let bounds = NSRect(origin: .zero, size: frame.size)
        glass.frame = bounds
        view.frame = bounds
        view.setThumbnail(NSWorkspace.shared.icon(forFile: urls[0].path))
        configureView()
        loadThumbnail(for: urls[0])

        panel.alphaValue = 0
        if interactive {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(view)
        } else {
            panel.orderFrontRegardless()
        }
        animateIn(panel)
    }

    private func configureView() {
        guard let view else { return }
        view.configure(urls: urls, mode: mode, items: Registry.operations(for: urls, mode: mode), interactive: interactive)
        glass?.maskImage = view.backdropMask()
    }

    /// Fade plus a small spring from 88% scale, about the wheel's centre.
    private func animateIn(_ panel: NSPanel) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.14
            panel.animator().alphaValue = 1
        }
        guard let layer = panel.contentView?.layer else { return }
        let size = panel.frame.size
        let pivot = CGPoint(x: size.width / 2, y: WheelView.captionHeight + size.width / 2)
        var from = CATransform3DMakeTranslation(pivot.x, pivot.y, 0)
        from = CATransform3DScale(from, 0.9, 0.9, 1)
        from = CATransform3DTranslate(from, -pivot.x, -pivot.y, 0)
        let spring = CASpringAnimation(keyPath: "transform")
        spring.fromValue = from
        spring.toValue = CATransform3DIdentity
        spring.damping = 16
        spring.stiffness = 260
        spring.duration = spring.settlingDuration
        layer.add(spring, forKey: "pop")
    }

    private func loadThumbnail(for url: URL) {
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 68, height: 68),
                                                   scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { rep, _ in
            guard let image = rep?.nsImage else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.urls.first == url else { return }
                self.view?.setThumbnail(image)
            }
        }
    }

    func setMode(_ mode: WheelMode) {
        guard isVisible, mode != self.mode else { return }
        self.mode = mode
        configureView()
    }

    func cycleMode(by delta: Int) {
        let all = WheelMode.allCases
        setMode(all[(mode.rawValue + delta + all.count) % all.count])
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        panel.orderOut(nil)
        if interactive && !NSApp.windows.contains(where: { $0.isVisible && ($0 is MainWindow || $0 is OnboardingWindow) }) {
            NSApp.hide(nil)  // hand focus back to Finder
        }
    }

    func perform(_ op: FileOperation, on dropped: [URL]? = nil) {
        let targets = dropped?.isEmpty == false ? dropped! : urls
        hide()
        if op.isInstant {
            Task {
                do {
                    let result = try await op.run(targets) { _ in }
                    if let message = result.message { Toast.show(message) }
                } catch {
                    Toast.show(error.localizedDescription, isError: true)
                }
            }
        } else {
            JobCenter.shared.run(op, on: targets)
        }
    }
}

final class WheelPanel: NSPanel {
    var interactive = false

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        acceptsMouseMovedEvents = true
    }

    override var canBecomeKey: Bool { interactive }

    override func resignKey() {
        super.resignKey()
        if interactive { Task { @MainActor in WheelController.shared.hide() } }
    }
}

/// A brief message near the top of the screen, for instant actions like Copy Path.
@MainActor
enum Toast {
    private static var panel: NSPanel?

    static func show(_ text: String, isError: Bool = false) {
        panel?.orderOut(nil)
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = isError ? .systemOrange : .labelColor
        label.lineBreakMode = .byTruncatingMiddle
        let size = NSSize(width: min(label.intrinsicContentSize.width + 36, 480), height: 38)

        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.level = .statusBar
        p.backgroundColor = .clear
        p.isOpaque = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        effect.material = .hudWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 19
        label.frame = NSRect(x: 18, y: 10, width: size.width - 36, height: 18)
        effect.addSubview(label)
        p.contentView = effect
        if let screen = NSScreen.main?.visibleFrame {
            p.setFrameOrigin(NSPoint(x: screen.midX - size.width / 2, y: screen.maxY - size.height - 24))
        }
        p.orderFrontRegardless()
        panel = p
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.25; p.animator().alphaValue = 0 }) {
                Task { @MainActor in p.orderOut(nil) }
            }
        }
    }
}
