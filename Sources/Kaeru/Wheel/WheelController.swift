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
        generation += 1
        panel?.contentView?.layer?.removeAnimation(forKey: "out")
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
            ctx.duration = 0.16
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
        guard let layer = panel.contentView?.layer else { return }
        let size = panel.frame.size
        let pivot = CGPoint(x: size.width / 2, y: WheelView.captionHeight + size.width / 2)
        var from = CATransform3DMakeTranslation(pivot.x, pivot.y, 0)
        from = CATransform3DScale(from, 0.86, 0.86, 1)
        from = CATransform3DTranslate(from, -pivot.x, -pivot.y, 0)
        let spring = CASpringAnimation(keyPath: "transform")
        spring.fromValue = from
        spring.toValue = CATransform3DIdentity
        spring.damping = 18
        spring.stiffness = 300
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

    /// Bumped on every show, so a hide animation finishing late never closes a picker that reopened.
    private var generation = 0

    func hide() {
        guard let panel, panel.isVisible else { return }
        let current = generation
        // A quick fade and settle, so the picker melts away instead of vanishing.
        if let layer = panel.contentView?.layer {
            let size = panel.frame.size
            let pivot = CGPoint(x: size.width / 2, y: WheelView.captionHeight + size.width / 2)
            var to = CATransform3DMakeTranslation(pivot.x, pivot.y, 0)
            to = CATransform3DScale(to, 0.94, 0.94, 1)
            to = CATransform3DTranslate(to, -pivot.x, -pivot.y, 0)
            let shrink = CABasicAnimation(keyPath: "transform")
            shrink.toValue = to
            shrink.duration = 0.14
            shrink.timingFunction = CAMediaTimingFunction(name: .easeIn)
            shrink.fillMode = .forwards
            shrink.isRemovedOnCompletion = false
            layer.add(shrink, forKey: "out")
        }
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.14; panel.animator().alphaValue = 0 }) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == current else { return }
                panel.orderOut(nil)
                panel.contentView?.layer?.removeAnimation(forKey: "out")
            }
        }
        if interactive && !NSApp.windows.contains(where: { $0.isVisible && ($0 is MainWindow || $0 is OnboardingWindow || $0 is ShelfPanel) }) {
            NSApp.hide(nil)  // hand focus back to Finder
        }
    }

    func perform(_ op: FileOperation, on dropped: [URL]? = nil) {
        let targets = dropped?.isEmpty == false ? dropped! : urls
        Recents.record(op, for: targets, mode: mode)
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

/// A brief message near the top of the screen, for instant actions like Copy Path. It drops in with a
/// small spring, waits, then lifts away.
@MainActor
enum Toast {
    private static var panel: NSPanel?

    static func show(_ text: String, isError: Bool = false) {
        panel?.orderOut(nil)
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingMiddle
        let iconSize: CGFloat = 18
        let size = NSSize(width: min(label.intrinsicContentSize.width + iconSize + 46, 500), height: 40)

        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.level = .statusBar
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        effect.material = .hudWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = size.height / 2
        effect.layer?.masksToBounds = true
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
            .applying(.init(paletteColors: [.white, isError ? .systemOrange : Theme.brand]))
        let icon = NSImageView(image: NSImage(systemSymbolName: isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill",
                                              accessibilityDescription: nil)?.withSymbolConfiguration(config) ?? NSImage())
        icon.frame = NSRect(x: 14, y: (size.height - iconSize) / 2, width: iconSize, height: iconSize)
        label.frame = NSRect(x: 14 + iconSize + 8, y: 11, width: size.width - iconSize - 44, height: 18)
        effect.addSubview(icon)
        effect.addSubview(label)
        p.contentView = effect
        guard let screen = NSScreen.main?.visibleFrame else { return }
        let rest = NSPoint(x: screen.midX - size.width / 2, y: screen.maxY - size.height - 22)
        p.setFrameOrigin(NSPoint(x: rest.x, y: rest.y + 14))
        p.alphaValue = 0
        p.orderFrontRegardless()
        panel = p
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.32
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 1.25, 0.4, 1)
            p.animator().alphaValue = 1
            p.animator().setFrameOrigin(rest)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.25
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                p.animator().alphaValue = 0
                p.animator().setFrameOrigin(NSPoint(x: rest.x, y: rest.y + 10))
            }) { Task { @MainActor in p.orderOut(nil) } }
        }
    }
}
