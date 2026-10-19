import AppKit
import WebKit

/// Formats macOS can't parse itself (PPT/PPTX/Keynote slides, Pages, XLS) are handled two ways:
/// by scripting an installed app (PowerPoint, Keynote, Pages) for full fidelity, or by asking
/// QuickLook's built-in Office renderer for an HTML preview.
enum OfficeApps {
    static func isInstalled(_ bundleID: String) -> Bool {
        // KAERU_NO_APPS=1 forces the QuickLook fallbacks, for testing without automation prompts.
        guard ProcessInfo.processInfo.environment["KAERU_NO_APPS"] == nil else { return false }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    static var hasPowerPoint: Bool { isInstalled("com.microsoft.Powerpoint") }
    static var hasWord: Bool { isInstalled("com.microsoft.Word") }
    static var hasKeynote: Bool { isInstalled("com.apple.iWork.Keynote") }
    static var hasPages: Bool { isInstalled("com.apple.iWork.Pages") }

    /// Exports slides to PDF with PowerPoint or Keynote, exactly as they look in the app.
    static func presentationToPDF(_ input: URL, _ output: URL) async throws {
        let ext = input.pathExtension.lowercased()
        if hasPowerPoint && ext != "key" {
            try await run("""
            on run argv
                set wasRunning to application "Microsoft PowerPoint" is running
                tell application "Microsoft PowerPoint"
                    open POSIX file (item 1 of argv)
                    set pres to active presentation
                    save pres in POSIX file (item 2 of argv) as save as PDF
                    close pres saving no
                    if not wasRunning then quit
                end tell
            end run
            """, input.path, output.path)
        } else if hasKeynote {
            try await run("""
            on run argv
                tell application "Keynote"
                    set doc to open POSIX file (item 1 of argv)
                    export doc to POSIX file (item 2 of argv) as PDF
                    close doc saving no
                end tell
            end run
            """, input.path, output.path)
        } else {
            throw fail("Install Keynote (free) or PowerPoint for full-quality slide conversion")
        }
        try requirePDF(output)
    }

    /// Exports a Word, RTF or ODT document to PDF with Microsoft Word, keeping images, tables and styles.
    static func documentToPDF(_ input: URL, _ output: URL) async throws {
        guard hasWord else { throw fail("Microsoft Word isn't installed") }
        try await run("""
        on run argv
            set wasRunning to application "Microsoft Word" is running
            tell application "Microsoft Word"
                open POSIX file (item 1 of argv)
                set doc to active document
                save as doc file name (item 2 of argv) file format format PDF
                close doc saving no
                if not wasRunning then quit
            end tell
        end run
        """, input.path, output.path)
        try requirePDF(output)
    }

    private static func requirePDF(_ url: URL) throws {
        guard let handle = try? FileHandle(forReadingFrom: url), handle.readData(ofLength: 5) == Data("%PDF-".utf8) else {
            throw fail("The app didn't produce a PDF")
        }
    }

    /// Pages export formats, as named in Pages' scripting dictionary.
    static func pagesExport(_ input: URL, _ output: URL) async throws {
        let format: String
        switch output.pathExtension.lowercased() {
        case "pdf": format = "PDF"
        case "docx": format = "Microsoft Word"
        case "epub": format = "EPUB"
        case "rtf": format = "formatted text"
        case "txt": format = "unformatted text"
        case "pages":
            try await run("""
            on run argv
                tell application "Pages"
                    set doc to open POSIX file (item 1 of argv)
                    save doc in POSIX file (item 2 of argv)
                    close doc saving no
                end tell
            end run
            """, input.path, output.path)
            return
        default: throw fail("Pages can't export .\(output.pathExtension)")
        }
        try await run("""
        on run argv
            tell application "Pages"
                set doc to open POSIX file (item 1 of argv)
                export doc to POSIX file (item 2 of argv) as \(format)
                close doc saving no
            end tell
        end run
        """, input.path, output.path)
    }

    /// Runs an AppleScript, giving up after `timeout` seconds so an app stuck on a dialog can't hang the job.
    private static func run(_ script: String, _ args: String..., timeout: Double = 150) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await Shell.run("/usr/bin/osascript", ["-e", script] + args) }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw fail("The app didn't respond. It may be showing a dialog; answer it and try again")
            }
            try await group.next()
            group.cancelAll()
        }
    }
}

enum QuickLookOffice {
    /// Runs QuickLook's Office generator and returns the HTML preview it writes.
    static func previewHTML(_ url: URL) async throws -> URL {
        let dir = try Output.tempDirectory()
        try await Shell.run("/usr/bin/qlmanage", ["-p", "-o", dir.path, url.path])
        let html = dir.appendingPathComponent(url.lastPathComponent + ".qlpreview/Preview.html")
        guard FileManager.default.fileExists(atPath: html.path) else { throw fail("QuickLook couldn't read \(url.lastPathComponent)") }
        return html
    }

    /// The first table of a spreadsheet preview (XLS and friends), with merged cells expanded.
    static func table(_ url: URL) async throws -> [[String]] {
        let html = try String(contentsOf: try await previewHTML(url), encoding: .utf8)
        guard let tableStart = html.range(of: "<table"),
              let tableEnd = html.range(of: "</table>", range: tableStart.upperBound..<html.endIndex) else {
            throw fail("No table found in \(url.lastPathComponent)")
        }
        let table = String(html[tableStart.lowerBound..<tableEnd.upperBound])
        let rowRE = try NSRegularExpression(pattern: "<tr[^>]*>(.*?)</tr>", options: .dotMatchesLineSeparators)
        let cellRE = try NSRegularExpression(pattern: "<t[dh]([^>]*)>(.*?)</t[dh]>", options: .dotMatchesLineSeparators)
        var rows: [[String]] = []
        for rowMatch in rowRE.matches(in: table, range: NSRange(table.startIndex..., in: table)) {
            let rowHTML = String(table[Range(rowMatch.range(at: 1), in: table)!])
            var row: [String] = []
            for cell in cellRE.matches(in: rowHTML, range: NSRange(rowHTML.startIndex..., in: rowHTML)) {
                let attrs = String(rowHTML[Range(cell.range(at: 1), in: rowHTML)!])
                let span = Int(attrs.range(of: "colspan=\"?(\\d+)", options: .regularExpression)
                    .map { attrs[$0].filter(\.isNumber) } ?? "") ?? 1
                row.append(plainText(String(rowHTML[Range(cell.range(at: 2), in: rowHTML)!])))
                row += Array(repeating: "", count: max(0, span - 1))
            }
            while row.last == "" { row.removeLast() }
            rows.append(row)
        }
        while rows.last?.isEmpty == true { rows.removeLast() }
        while let first = rows.first, first.isEmpty { rows.removeFirst() }
        return rows
    }

    private static func plainText(_ html: String) -> String {
        var s = html.replacingOccurrences(of: "<br[^>]*>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        for (entity, char) in [("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&amp;", "&")] {
            s = s.replacingOccurrences(of: entity, with: char)
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Renders each slide of a QuickLook presentation preview. Used when neither PowerPoint nor
    /// Keynote is installed; QuickLook omits pictures, so slides show text and shapes only.
    @MainActor
    static func slides(_ url: URL) async throws -> [CGImage] {
        let html = try await previewHTML(url)
        // Wide enough for any slide size (16:9 decks are 960pt), so nothing is clipped on the right.
        let canvas: CGFloat = 2400
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: canvas, height: 800))
        let window = NSWindow(contentRect: NSRect(x: -30_000, y: -30_000, width: canvas, height: 800),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = web
        window.orderBack(nil)
        defer { window.orderOut(nil) }

        let loader = PageLoader()
        web.navigationDelegate = loader
        web.loadFileURL(html, allowingReadAccessTo: html.deletingLastPathComponent())
        try await loader.wait()
        try await Task.sleep(nanoseconds: 600_000_000)  // the preview fills slides in with JavaScript

        let js = """
        JSON.stringify({h: document.documentElement.scrollHeight, s: [...document.querySelectorAll('div.slide')]
          .map(e => { const r = e.getBoundingClientRect(); return [r.left + scrollX, r.top + scrollY, r.width, r.height] })})
        """
        guard let json = try await web.evaluateJavaScript(js) as? String,
              let info = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let rects = info["s"] as? [[Double]], !rects.isEmpty else { throw fail("No slides found") }
        let height = info["h"] as? Double ?? 800
        window.setContentSize(NSSize(width: canvas, height: height))
        web.frame = NSRect(x: 0, y: 0, width: canvas, height: height)

        var images: [CGImage] = []
        for r in rects {
            let config = WKSnapshotConfiguration()
            config.rect = CGRect(x: r[0], y: r[1], width: r[2], height: r[3])
            config.snapshotWidth = NSNumber(value: r[2])  // doubled again on Retina
            let snapshot = try await web.takeSnapshot(configuration: config)
            if let cg = snapshot.cgImage(forProposedRect: nil, context: nil, hints: nil) { images.append(cg) }
        }
        return images
    }
}

private final class PageLoader: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?
    private var result: Result<Void, Error>?

    func wait() async throws {
        if let result { return try result.get() }
        try await withCheckedThrowingContinuation { continuation = $0 }
    }

    private func finish(_ r: Result<Void, Error>) {
        if let continuation { continuation.resume(with: r); self.continuation = nil } else { result = r }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finish(.success(())) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish(.failure(error)) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(.failure(error))
    }
}
