import AppKit

/// Watches for file drags anywhere on screen and opens the wheel when a configured modifier is held.
///
/// Polling avoids the Accessibility permission that a global event tap would need: the drag
/// pasteboard's change count bumps whenever any app starts a drag, and `NSEvent` exposes the
/// current mouse buttons and modifiers to every process.
@MainActor
final class DragMonitor {
    private var timer: Timer?
    private var wasPressed = false
    private var baseline = NSPasteboard(name: .drag).changeCount
    /// Files in the current drag; empty for non-file drags, nil when no drag is in progress.
    private var dragURLs: [URL]?

    func start() {
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        let pressed = NSEvent.pressedMouseButtons & 1 != 0
        defer { wasPressed = pressed }
        let wheel = WheelController.shared

        guard pressed else {
            if wasPressed {
                baseline = NSPasteboard(name: .drag).changeCount
                dragURLs = nil
                if wheel.isVisible && !wheel.interactive {
                    // Give a drop on the wheel a moment to be handled before tidying up.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        if NSEvent.pressedMouseButtons & 1 == 0 && !wheel.interactive { wheel.hide() }
                    }
                }
            }
            return
        }

        guard Settings.dragWheelEnabled else { return }
        if dragURLs == nil {
            let pasteboard = NSPasteboard(name: .drag)
            guard pasteboard.changeCount != baseline else { return }
            baseline = pasteboard.changeCount
            dragURLs = pasteboard.readObjects(forClasses: [NSURL.self],
                                              options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        }
        guard let urls = dragURLs, !urls.isEmpty, !(wheel.isVisible && wheel.interactive),
              let mode = Settings.mode(for: NSEvent.modifierFlags) else { return }
        if wheel.isVisible {
            wheel.setMode(mode)
        } else {
            wheel.show(urls: urls, mode: mode, at: NSEvent.mouseLocation, interactive: false)
        }
    }
}
