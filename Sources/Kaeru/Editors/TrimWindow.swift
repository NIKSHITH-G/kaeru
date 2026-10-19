import AVKit

/// QuickTime-style trimming: AVPlayerView's built-in trim bar, returning the chosen range in seconds.
@MainActor
final class TrimWindow: NSWindow, NSWindowDelegate {
    private let playerView = AVPlayerView()
    private var continuation: CheckedContinuation<ClosedRange<Double>?, Never>?

    static func ask(_ url: URL) async throws -> ClosedRange<Double>? {
        guard try await AVURLAsset(url: url).load(.isPlayable) else {
            throw fail("Trim works with formats QuickTime can play — convert \(url.lastPathComponent) to MP4 or M4A first")
        }
        let window = TrimWindow(url: url)
        return try await window.run()
    }

    private init(url: URL) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 760, height: 480),
                   styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        title = "Trim — \(url.lastPathComponent)"
        isReleasedWhenClosed = false
        playerView.player = AVPlayer(url: url)
        playerView.controlsStyle = .inline
        contentView = playerView
        delegate = self
        center()
    }

    private func run() async throws -> ClosedRange<Double>? {
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
        for _ in 0..<100 where !playerView.canBeginTrimming {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        guard playerView.canBeginTrimming else {
            orderOut(nil)
            throw fail("This file can't be trimmed")
        }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            playerView.beginTrimming { [weak self] result in
                MainActor.assumeIsolated {
                    guard let self, result == .okButton, let item = self.playerView.player?.currentItem else {
                        self?.finish(nil)
                        return
                    }
                    let start = item.reversePlaybackEndTime.isNumeric ? item.reversePlaybackEndTime.seconds : 0
                    let end = item.forwardPlaybackEndTime.isNumeric ? item.forwardPlaybackEndTime.seconds : item.duration.seconds
                    self.finish(end > start ? start...end : nil)
                }
            }
        }
    }

    private func finish(_ range: ClosedRange<Double>?) {
        playerView.player?.pause()
        continuation?.resume(returning: range)
        continuation = nil
        orderOut(nil)
    }

    func windowWillClose(_ notification: Notification) { finish(nil) }
}
