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
    private var shake = ShakeDetector()

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
                shake.reset()
                // Give a drop on a shake-opened shelf a moment to land before closing unused ones.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    MainActor.assumeIsolated { if NSEvent.pressedMouseButtons & 1 == 0 { ShelfManager.closeUnusedShakeShelves() } }
                }
                if wheel.isVisible && !wheel.interactive {
                    // Give a drop on the wheel a moment to be handled before tidying up.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        if NSEvent.pressedMouseButtons & 1 == 0 && !wheel.interactive { wheel.hide() }
                    }
                }
            }
            return
        }

        if dragURLs == nil {
            let pasteboard = NSPasteboard(name: .drag)
            guard pasteboard.changeCount != baseline else { return }
            baseline = pasteboard.changeCount
            dragURLs = pasteboard.readObjects(forClasses: [NSURL.self],
                                              options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        }
        guard let urls = dragURLs, !urls.isEmpty else { return }
        checkShake()
        // Over a shelf the drop is meant for the shelf: keep the picker out of the way.
        let point = NSEvent.mouseLocation
        if NSApp.windows.contains(where: { $0 is ShelfPanel && $0.isVisible && $0.frame.contains(point) }) {
            if wheel.isVisible && !wheel.interactive { wheel.hide() }
            return
        }
        guard Settings.dragWheelEnabled, !(wheel.isVisible && wheel.interactive),
              let mode = Settings.mode(for: NSEvent.modifierFlags) else { return }
        if wheel.isVisible {
            wheel.setMode(mode)
        } else {
            wheel.show(urls: urls, mode: mode, at: NSEvent.mouseLocation, interactive: false)
        }
    }

    /// Shaking the pointer while dragging files opens an empty shelf right under it, ready for the drop.
    private func checkShake() {
        guard Settings.shakeToOpen, !WheelController.shared.isVisible else { return }
        let point = NSEvent.mouseLocation
        guard shake.feed(point, minimumSwing: Settings.shakeStrength.minimumSwing) else { return }
        if let app = NSWorkspace.shared.frontmostApplication?.bundleIdentifier, Settings.shakeIgnoredApps.contains(app) { return }
        // Not when the files are being dragged out of, or over, a shelf already.
        if NSApp.windows.contains(where: { $0 is ShelfPanel && $0.isVisible && $0.frame.insetBy(dx: -40, dy: -40).contains(point) }) { return }
        ShelfManager.open(with: [], near: point, centered: true)
    }
}

/// Spots a shake: the pointer reversing direction left and right several times, quickly, with each
/// swing travelling at least a minimum distance. Fires once per drag.
struct ShakeDetector {
    private var direction: CGFloat = 0
    private var turnX: CGFloat?
    private var reversals: [TimeInterval] = []
    private var fired = false

    mutating func reset() { self = ShakeDetector() }

    /// Feed the pointer position each tick; returns true the moment a shake completes.
    mutating func feed(_ point: NSPoint, minimumSwing: CGFloat, now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
        guard !fired else { return false }
        guard let start = turnX else { turnX = point.x; return false }
        let dx = point.x - start
        let moving: CGFloat = dx > 0 ? 1 : -1
        if direction == 0 {
            if abs(dx) >= minimumSwing { direction = moving; turnX = point.x }
            return false
        }
        if moving == direction {
            // Still heading the same way: the turning point follows the pointer.
            if (point.x - start) * direction > 0 { turnX = point.x }
        } else if abs(dx) >= minimumSwing {
            // Swung back far enough the other way: a reversal.
            direction = moving
            turnX = point.x
            reversals.append(now)
            reversals.removeAll { now - $0 > 0.8 }
            if reversals.count >= 3 { fired = true; return true }
        }
        return false
    }
}
