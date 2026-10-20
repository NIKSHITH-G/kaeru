import AppKit

/// Screenshot shelf: new screenshots appear in a shelf in the corner of the screen, ready to drag
/// into a message or document. Watches the folder macOS saves screenshots to.
@MainActor
final class ScreenshotWatcher {
    static let shared = ScreenshotWatcher()
    private var source: DispatchSourceFileSystemObject?
    private var folder: URL?
    private var seen = Set<String>()

    /// Starts or stops watching to match Settings → Shelf.
    func update() {
        Settings.screenshotShelf ? start() : stop()
    }

    private func start() {
        let dir = Self.screenshotFolder()
        guard source == nil || folder != dir else { return }
        stop()
        folder = dir
        seen = Set((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
        let fd = open(dir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        src.setEventHandler { [weak self] in
            // macOS writes a hidden temporary file first and renames it; give it a moment to settle.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { MainActor.assumeIsolated { self?.scan() } }
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
    }

    private func stop() {
        source?.cancel()
        source = nil
    }

    private func scan() {
        guard let dir = folder else { return }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        let fresh = names.filter { name in
            guard !seen.contains(name), !name.hasPrefix(".") else { return false }
            let url = dir.appendingPathComponent(name)
            let created = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return Date().timeIntervalSince(created) < 15 && Self.looksLikeScreenshot(url)
        }
        seen.formUnion(names)
        guard !fresh.isEmpty else { return }
        let urls = fresh.sorted().map { dir.appendingPathComponent($0) }
        ShelfManager.addScreenshots(urls)
    }

    /// A screenshot or screen recording: an image or movie whose name macOS gave it ("Screenshot …",
    /// "Screen Recording …", or the localized equivalents, which all start with a capital letter and a date).
    private static func looksLikeScreenshot(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        guard ["png", "jpg", "jpeg", "heic", "tiff", "pdf", "mov", "mp4"].contains(ext) else { return false }
        let name = url.deletingPathExtension().lastPathComponent.lowercased()
        return name.contains("screenshot") || name.contains("screen shot") || name.contains("screen recording")
            || name.range(of: "\\d{4}-\\d{2}-\\d{2}", options: .regularExpression) != nil
    }

    /// Where macOS saves screenshots: the user's choice in the Screenshot app, or the Desktop.
    static func screenshotFolder() -> URL {
        if let path = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location") {
            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    }
}
