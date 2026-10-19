import AppKit
import SwiftUI

/// Keeps Kaeru up to date without getting in the way: checks GitHub Releases at launch and every
/// six hours, downloads a new version in the background, then offers "Restart Now" in a small card.
/// If you choose Later, the update installs itself the next time Kaeru quits.
/// Downloads made with URLSession aren't quarantined, so the new version opens without a Gatekeeper prompt.
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()
    static let repository = "NIKSHITH-G/kaeru"
    static let autoCheckKey = "autoCheckUpdates"
    private static let lastCheckKey = "lastUpdateCheck"
    private static let interval: TimeInterval = 6 * 3600

    struct Release {
        let version: String
        let notes: String
        let dmg: URL
        let page: URL
    }

    enum Status {
        case idle, checking, upToDate
        case available(Release)
        case downloading(Double)
        /// Downloaded and unpacked; waiting for a restart (or for Kaeru to quit).
        case ready(Release, URL)
        case installing
        case failed(String)
    }

    @Published private(set) var status: Status = .idle
    private var timer: Timer?

    /// KAERU_FAKE_VERSION pretends to be an older build, so the update pipeline can be tested end to end.
    var currentVersion: String {
        ProcessInfo.processInfo.environment["KAERU_FAKE_VERSION"]
            ?? Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    var readyRelease: Release? { if case .ready(let r, _) = status { return r }; return nil }

    private var automatic: Bool { UserDefaults.standard.object(forKey: Self.autoCheckKey) as? Bool ?? true }

    /// Checks now if it's been a while, then every six hours while Kaeru runs.
    func startAutomaticChecks() {
        let last = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date ?? .distantPast
        if automatic, Date().timeIntervalSince(last) > Self.interval { Task { await check(interactive: false) } }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { _ in
            Task { @MainActor in
                guard Updater.shared.automatic else { return }
                await Updater.shared.check(interactive: false)
            }
        }
    }

    /// Finds the latest release and, if it's newer, downloads it straight away so it's ready to install.
    func check(interactive: Bool) async {
        if case .ready = status { if let r = readyRelease { UpdateCard.show(r) }; return }
        if case .downloading = status { return }
        status = .checking
        UserDefaults.standard.set(Date(), forKey: Self.lastCheckKey)
        do {
            var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repository)/releases/latest")!)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                status = interactive ? .failed("No releases published yet") : .idle
                return
            }
            let release = try Self.parse(data)
            guard Self.isVersion(release.version, newerThan: currentVersion) else {
                status = .upToDate
                return
            }
            status = .available(release)
            await prepare(release)
        } catch {
            status = interactive ? .failed(error.localizedDescription) : .idle
        }
    }

    /// Downloads and unpacks the update, then offers it.
    func prepare(_ release: Release) async {
        do {
            status = .downloading(0)
            let dmg = try await download(release.dmg)
            let staged = try await extractApp(from: dmg)
            try? FileManager.default.removeItem(at: dmg)
            status = .ready(release, staged)
            UpdateCard.show(release)
        } catch {
            status = .failed("Update failed: \(error.localizedDescription)")
        }
    }

    func restartNow() {
        guard case .ready(_, let staged) = status else { return }
        status = .installing
        do { try swap(in: staged, relaunch: true) } catch { status = .failed("Update failed: \(error.localizedDescription)") }
    }

    /// Called as Kaeru quits: a downloaded update is installed quietly, ready for next launch.
    func installOnQuitIfReady() {
        guard case .ready(_, let staged) = status else { return }
        try? swap(in: staged, relaunch: false)
    }

    private func download(_ url: URL) async throws -> URL {
        let (bytes, response) = try await URLSession.shared.bytes(from: url)
        let total = Double(response.expectedContentLength)
        let file = Output.temp(ext: "dmg")
        FileManager.default.createFile(atPath: file.path, contents: nil)
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        var buffer = Data()
        var received = 0.0
        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= 1 << 16 {
                try handle.write(contentsOf: buffer)
                received += Double(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                if total > 0 { status = .downloading(received / total) }
            }
        }
        try handle.write(contentsOf: buffer)
        return file
    }

    private func extractApp(from dmg: URL) async throws -> URL {
        let mount = try Output.tempDirectory()
        try await Shell.run("/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-readonly", "-mountpoint", mount.path])
        defer { Task { try? await Shell.run("/usr/bin/hdiutil", ["detach", mount.path, "-force"]) } }
        guard let app = try FileManager.default.contentsOfDirectory(at: mount, includingPropertiesForKeys: nil)
            .first(where: { $0.pathExtension == "app" }) else { throw fail("The update doesn't contain an app") }
        let staged = try Output.tempDirectory().appendingPathComponent(app.lastPathComponent)
        try await Shell.run("/usr/bin/ditto", [app.path, staged.path])
        return staged
    }

    /// A tiny shell script waits for this process to quit, swaps the bundle and (optionally) opens the new one.
    private func swap(in staged: URL, relaunch: Bool) throws {
        let target = Bundle.main.bundleURL.path
        let script = """
        while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done
        rm -rf "$1" && mv "$2" "$1" && xattr -dr com.apple.quarantine "$1" 2>/dev/null
        \(relaunch ? "open \"$1\"" : "true")
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, "sh", target, staged.path]
        try process.run()
        if relaunch { NSApp.terminate(nil) }
    }

    static func parse(_ data: Data) throws -> Release {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let page = (json["html_url"] as? String).flatMap(URL.init(string:)),
              let assets = json["assets"] as? [[String: Any]],
              let dmg = assets.first(where: { ($0["name"] as? String)?.hasSuffix(".dmg") == true })?["browser_download_url"] as? String,
              let dmgURL = URL(string: dmg)
        else { throw fail("Unexpected release format") }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        return Release(version: version, notes: json["body"] as? String ?? "", dmg: dmgURL, page: page)
    }

    /// Numeric, component-wise comparison: 0.10.0 > 0.9.2.
    static func isVersion(_ a: String, newerThan b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }, pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}

/// "Kaeru 0.9.9 is ready": a small card under the menu bar with Restart Now / Later / What's New.
@MainActor
enum UpdateCard {
    private static var panel: NSPanel?

    static func show(_ release: Updater.Release) {
        panel?.orderOut(nil)
        let size = NSSize(width: 340, height: 132)
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.level = .statusBar
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = NSHostingView(rootView: UpdateCardView(release: release, dismiss: { hide() }))
        if let screen = NSScreen.main?.visibleFrame {
            p.setFrameOrigin(NSPoint(x: screen.maxX - size.width - 12, y: screen.maxY - size.height - 10))
        }
        p.alphaValue = 0
        p.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.25; p.animator().alphaValue = 1 }
        panel = p
    }

    static func hide() {
        guard let p = panel else { return }
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.2; p.animator().alphaValue = 0 }) {
            Task { @MainActor in p.orderOut(nil) }
        }
        panel = nil
    }
}

private struct UpdateCardView: View {
    let release: Updater.Release
    let dismiss: () -> Void

    private var headline: String {
        release.notes.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.hasPrefix("### ") }.map { String($0.dropFirst(4)) } ?? "A new version is ready to install."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(nsImage: Artwork.appMark(size: 34))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Kaeru \(release.version) is ready").font(.system(size: 13, weight: .semibold))
                    Text(headline).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                Button("What’s New") { NSWorkspace.shared.open(release.page) }.buttonStyle(.link).font(.system(size: 12))
                Spacer()
                Button("Later") { dismiss() }
                Button("Restart Now") { Updater.shared.restartNow() }
                    .buttonStyle(BrandButtonStyle())
            }
            .controlSize(.small)
            Text("Or it installs by itself the next time you quit Kaeru.")
                .font(.system(size: 10.5)).foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(width: 340, height: 132)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.separator.opacity(0.5)))
    }
}

/// Always-green primary button. System prominent buttons turn grey in windows that never become key,
/// and the update card deliberately never takes focus.
private struct BrandButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Theme.brand.swiftUI.opacity(configuration.isPressed ? 0.75 : 1)))
    }
}
