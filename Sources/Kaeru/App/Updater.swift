import AppKit

/// Checks GitHub Releases for a newer version, then downloads the DMG, swaps the app bundle
/// in place and relaunches. Downloads made with URLSession aren't quarantined, so the new
/// version opens without a Gatekeeper prompt.
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()
    static let repository = "NIKSHITH-G/kaeru"
    static let autoCheckKey = "autoCheckUpdates"
    private static let lastCheckKey = "lastUpdateCheck"

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
        case installing
        case failed(String)
    }

    @Published private(set) var status: Status = .idle

    var currentVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0" }

    /// Daily background check; only speaks up when there's something new.
    func checkOnLaunch() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: Self.autoCheckKey) as? Bool ?? true else { return }
        if let last = defaults.object(forKey: Self.lastCheckKey) as? Date, Date().timeIntervalSince(last) < 86_400 { return }
        Task { await check(interactive: false) }
    }

    func check(interactive: Bool) async {
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
            if Self.isVersion(release.version, newerThan: currentVersion) {
                status = .available(release)
                if !interactive { promptToInstall(release) }
            } else {
                status = .upToDate
            }
        } catch {
            status = interactive ? .failed(error.localizedDescription) : .idle
        }
    }

    func promptToInstall(_ release: Release) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Kaeru \(release.version) is available"
        alert.informativeText = "You have \(currentVersion).\n\n" + String(release.notes.prefix(600))
        alert.icon = NSApp.applicationIconImage
        alert.addButton(withTitle: "Install and Relaunch")
        alert.addButton(withTitle: "Later")
        alert.addButton(withTitle: "Release Notes")
        switch alert.runModal() {
        case .alertFirstButtonReturn: Task { await install(release) }
        case .alertThirdButtonReturn: NSWorkspace.shared.open(release.page)
        default: break
        }
    }

    func install(_ release: Release) async {
        do {
            status = .downloading(0)
            let dmg = try await download(release.dmg)
            status = .installing
            let staged = try await extractApp(from: dmg)
            try relaunch(replacingWith: staged)
        } catch {
            status = .failed("Update failed: \(error.localizedDescription)")
        }
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

    /// A tiny shell script waits for this process to quit, swaps the bundle and opens the new one.
    private func relaunch(replacingWith staged: URL) throws {
        let target = Bundle.main.bundleURL.path
        let script = """
        while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done
        rm -rf "$1" && mv "$2" "$1" && xattr -dr com.apple.quarantine "$1" 2>/dev/null; open "$1"
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, "sh", target, staged.path]
        try process.run()
        NSApp.terminate(nil)
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
