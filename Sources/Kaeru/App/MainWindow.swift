import AppKit
import SwiftUI
import UniformTypeIdentifiers

final class MainWindow: NSWindow {
    private static var shared: MainWindow?

    @MainActor
    static func show(page: AppModel.Page? = nil) {
        if let page { AppModel.shared.page = page }
        let window = shared ?? MainWindow()
        shared = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 860, height: 620),
                   styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                   backing: .buffered, defer: false)
        title = "Kaeru"
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isReleasedWhenClosed = false
        minSize = NSSize(width: 760, height: 540)
        contentView = NSHostingView(rootView: MainView())
        center()
    }
}

/// Window state. Held in an ObservableObject because the Command Line Tools toolchain
/// ships without the SwiftUI macro plugin that `@State` needs.
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    enum Page: String, CaseIterable, Identifiable {
        case home = "Home", history = "History", formats = "Formats", settings = "Settings", about = "About"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .home: return "house"
            case .history: return "clock.arrow.circlepath"
            case .formats: return "square.grid.2x2"
            case .settings: return "gearshape"
            case .about: return "info.circle"
            }
        }
    }

    @Published var page: Page? = .home
    @Published var dropTargeted = false
    @Published var historySearch = ""
    @Published var formatSearch = ""
    @Published var keyboardReady = false
    @Published var launchAtLogin = Settings.launchAtLogin {
        didSet { Settings.launchAtLogin = launchAtLogin }
    }

    private init() {
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                let ready = KeyboardTap.shared.isRunning
                if self?.keyboardReady != ready { self?.keyboardReady = ready }
            }
        }
    }
}

private struct MainView: View {
    @ObservedObject private var model = AppModel.shared

    var body: some View {
        NavigationSplitView {
            List(AppModel.Page.allCases, selection: $model.page) { page in
                Label(page.rawValue, systemImage: page.symbol).tag(page)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 180, max: 220)
            .safeAreaInset(edge: .top) { brand }
        } detail: {
            Group {
                switch model.page ?? .home {
                case .home: HomeView()
                case .history: HistoryView()
                case .formats: FormatsView()
                case .settings: SettingsView()
                case .about: AboutView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var brand: some View {
        HStack(spacing: 8) {
            Image(nsImage: Artwork.appMark(size: 26))
            Text("Kaeru").font(.system(size: 15, weight: .bold, design: .rounded))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 34)
        .padding(.bottom, 6)
    }
}

// MARK: - Home

private struct HomeView: View {
    @ObservedObject private var model = AppModel.shared
    @ObservedObject private var center = JobCenter.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Change any file, from anywhere").font(.system(size: 24, weight: .bold, design: .rounded))
                    Text("Drag a file and hold a key — the wheel appears right under your cursor. Everything stays on your Mac.")
                        .foregroundStyle(.secondary)
                }
                dropZone
                keys
                recent
            }
            .padding(28)
        }
    }

    private var dropZone: some View {
        VStack(spacing: 10) {
            Image(systemName: model.dropTargeted ? "arrow.down.circle.fill" : "arrow.down.doc")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(model.dropTargeted ? Theme.brand.swiftUI : .secondary)
                .scaleEffect(model.dropTargeted ? 1.12 : 1)
            Text(model.dropTargeted ? "Release to choose what to do" : "Drop files here")
                .font(.system(size: 15, weight: .semibold))
            Button("Choose Files…") { chooseFiles() }.controlSize(.small)
        }
        .frame(maxWidth: .infinity, minHeight: 150)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(model.dropTargeted ? Theme.brand.swiftUI.opacity(0.1) : Color.secondary.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [7, 5]))
            .foregroundStyle(model.dropTargeted ? Theme.brand.swiftUI : Color.secondary.opacity(0.35)))
        .animation(.spring(response: 0.3), value: model.dropTargeted)
        .onDrop(of: [.fileURL], isTargeted: $model.dropTargeted) { providers in
            loadURLs(providers) { openWheel($0) }
            return true
        }
    }

    private var keys: some View {
        HStack(spacing: 12) {
            keyCard(.convert, "Convert", "HEIC → JPG, MOV → MP4, DOCX → PDF", Theme.brand)
            keyCard(.tools, "Tools", "Trim, crop, compress, remove background", Theme.Category.tool.color)
            keyCard(.actions, "Actions", "AirDrop, float, copy path, move", Theme.Category.action.color)
        }
    }

    private func keyCard(_ mode: WheelMode, _ title: String, _ detail: String, _ color: NSColor) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    KeyCap(text: Settings.modifier(for: mode).glyph, large: true)
                    Spacer()
                    Image(systemName: mode.symbol).font(.system(size: 16, weight: .semibold)).foregroundStyle(color.swiftUI)
                }
                Text(title).font(.headline)
                Text(detail).font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recent").font(.headline)
                Spacer()
                if !center.jobs.isEmpty { Button("See All") { model.page = .history }.buttonStyle(.link) }
            }
            if center.jobs.isEmpty {
                HStack(spacing: 10) {
                    KeyCap(text: "↩")
                    Text("Tip: select files in Finder and press Return to open the wheel.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            } else {
                Card {
                    VStack(spacing: 0) {
                        ForEach(Array(center.jobs.prefix(4).enumerated()), id: \.element.id) { i, job in
                            if i > 0 { Divider() }
                            JobCard(job: job, compact: false)
                        }
                    }
                }
            }
        }
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        if panel.runModal() == .OK { openWheel(panel.urls) }
    }
}

@MainActor
private func openWheel(_ urls: [URL]) {
    guard !urls.isEmpty else { return }
    let point = NSApp.keyWindow.map { NSPoint(x: $0.frame.midX, y: $0.frame.midY) } ?? NSEvent.mouseLocation
    WheelController.shared.show(urls: urls, mode: .convert, at: point, interactive: true)
}

private func loadURLs(_ providers: [NSItemProvider], completion: @escaping @MainActor ([URL]) -> Void) {
    let group = DispatchGroup()
    var urls: [URL] = []
    let lock = NSLock()
    for provider in providers {
        group.enter()
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            if let url { lock.lock(); urls.append(url); lock.unlock() }
            group.leave()
        }
    }
    group.notify(queue: .main) { MainActor.assumeIsolated { completion(urls) } }
}

// MARK: - History

private struct HistoryView: View {
    @ObservedObject private var model = AppModel.shared
    @ObservedObject private var center = JobCenter.shared

    private var filtered: [Job] {
        let q = model.historySearch.lowercased()
        return q.isEmpty ? center.jobs : center.jobs.filter { "\($0.title) \($0.subtitle)".lowercased().contains(q) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("History").font(.system(size: 22, weight: .bold, design: .rounded))
                Spacer()
                TextField("Search", text: $model.historySearch).textFieldStyle(.roundedBorder).frame(width: 200)
                Button("Clear") { center.clearFinished() }.disabled(center.jobs.isEmpty)
            }
            if filtered.isEmpty {
                Spacer()
                Text(center.jobs.isEmpty ? "Conversions you make will appear here." : "No matches")
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity)
                Spacer()
            } else {
                List(filtered) { JobCard(job: $0, compact: false).listRowSeparator(.visible) }
                    .listStyle(.inset)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(28)
    }
}

// MARK: - Formats

/// Every input format and what it can become, derived from the Registry so it never goes stale.
private struct FormatsView: View {
    @ObservedObject private var model = AppModel.shared

    private static let groups: [(String, [String])] = [
        ("Images", ["heic", "jpg", "png", "webp", "avif", "tiff", "gif", "bmp", "svg", "psd", "dng"]),
        ("Video", ["mp4", "mov", "mkv", "webm", "avi", "wmv"]),
        ("Audio", ["mp3", "m4a", "wav", "flac", "ogg", "opus", "aiff", "wma"]),
        ("PDF", ["pdf"]),
        ("Documents", ["docx", "doc", "odt", "rtf", "md", "html", "txt", "epub", "pages"]),
        ("Slides", ["pptx", "ppt", "key"]),
        ("Spreadsheets", ["xlsx", "xls", "ods", "csv", "tsv"]),
        ("Data & Subtitles", ["json", "plist", "srt", "vtt"]),
        ("Archives", ["zip", "rar", "7z", "gz"]),
    ]

    private static let catalog: [(group: String, rows: [(ext: String, outputs: [String])])] = groups.map { group, exts in
        (group, exts.map { ext in
            let url = URL(fileURLWithPath: "/tmp/sample.\(ext)")
            return (ext, Registry.operations(for: [url], mode: .convert).map(\.title))
        })
    }

    private static let total = catalog.flatMap(\.rows).reduce(0) { $0 + $1.outputs.count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Formats").font(.system(size: 22, weight: .bold, design: .rounded))
                        Text("\(Self.total) conversions, plus tools and actions for every file.").foregroundStyle(.secondary)
                    }
                    Spacer()
                    TextField("Find a format", text: $model.formatSearch).textFieldStyle(.roundedBorder).frame(width: 200)
                }
                ForEach(Self.catalog, id: \.group) { section in
                    let rows = section.rows.filter(matches)
                    if !rows.isEmpty {
                        Card {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(section.group).font(.headline)
                                ForEach(rows, id: \.ext) { row in
                                    HStack(alignment: .top, spacing: 10) {
                                        FormatBadge(ext: row.ext).frame(width: 54, alignment: .leading)
                                        Image(systemName: "arrow.right").font(.caption).foregroundStyle(.tertiary).padding(.top, 3)
                                        FlowLayout {
                                            ForEach(row.outputs, id: \.self) { title in
                                                Text(title).font(.system(size: 11, weight: .medium))
                                                    .padding(.horizontal, 7).padding(.vertical, 3)
                                                    .background(Capsule().fill(.quaternary))
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(28)
        }
    }

    private func matches(_ row: (ext: String, outputs: [String])) -> Bool {
        let q = model.formatSearch.lowercased().trimmingCharacters(in: .whitespaces)
        return q.isEmpty || row.ext.contains(q) || row.outputs.contains { $0.lowercased().contains(q) }
    }
}

// MARK: - Settings

private struct SettingsView: View {
    @AppStorage(Settings.outputLocationKey) private var output = OutputLocation.sameFolder.rawValue
    @AppStorage(Settings.dragWheelKey) private var dragWheel = true
    @AppStorage(Settings.modifierKey(.convert)) private var convertKey = Settings.defaultTriggers[0].rawValue
    @AppStorage(Settings.modifierKey(.tools)) private var toolsKey = Settings.defaultTriggers[1].rawValue
    @AppStorage(Settings.modifierKey(.actions)) private var actionsKey = Settings.defaultTriggers[2].rawValue
    @AppStorage(Settings.returnInFinderKey) private var returnInFinder = true
    @AppStorage(Updater.autoCheckKey) private var autoUpdate = true
    @ObservedObject private var model = AppModel.shared

    var body: some View {
        Form {
            Section("General") {
                Toggle("Open Kaeru at login", isOn: $model.launchAtLogin)
                Picker("Save results", selection: $output) {
                    ForEach(OutputLocation.allCases) { Text($0.label).tag($0.rawValue) }
                }
                Toggle("Check for updates automatically", isOn: $autoUpdate)
            }
            Section("Drag wheel") {
                Toggle("Open the wheel while dragging files", isOn: $dragWheel)
                keyPicker("Convert", $convertKey)
                keyPicker("Tools", $toolsKey)
                keyPicker("Actions", $actionsKey)
            }
            Section("Keyboard") {
                Toggle("Return in Finder opens the wheel", isOn: $returnInFinder)
                HStack {
                    Image(systemName: model.keyboardReady ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .foregroundStyle(model.keyboardReady ? .green : .orange)
                    VStack(alignment: .leading) {
                        Text("Accessibility permission")
                        Text("Needed for Return in Finder (renaming and search still get Return) and for ⇥ Tab as a trigger.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !model.keyboardReady { Button("Grant…") { KeyboardTap.shared.requestPermission() } }
                }
                LabeledContent("Open wheel for Finder selection") { KeyCap(text: "⌃⌥M") }
            }
            Section("Helpers") {
                helper("ffmpeg", "Audio, video, GIF and PNG compression", install: "brew install ffmpeg")
                helper("cwebp", "WebP export", install: "brew install webp")
            }
        }
        .formStyle(.grouped)
    }

    private func keyPicker(_ title: String, _ binding: Binding<String>) -> some View {
        Picker(title, selection: binding) {
            ForEach(ModifierKey.allCases) { Text($0.label).tag($0.rawValue) }
        }
    }

    private func helper(_ name: String, _ purpose: String, install: String) -> some View {
        let path = Tools.path(name)
        let bundled = path?.hasPrefix(Bundle.main.bundlePath) == true
        return HStack {
            Image(systemName: path != nil ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(path != nil ? .green : .secondary)
            VStack(alignment: .leading) {
                Text(name).font(.system(.body, design: .monospaced))
                Text(purpose).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if path == nil {
                Text(install).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
            } else {
                Text(bundled ? "Built in" : "Homebrew").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - About

private struct AboutView: View {
    @ObservedObject private var updater = Updater.shared

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(nsImage: Artwork.appMark(size: 96)).shadow(color: .black.opacity(0.2), radius: 8, y: 4)
            Text("Kaeru").font(.system(size: 28, weight: .bold, design: .rounded))
            Text("かえる — “to change”, and “frog”").foregroundStyle(.secondary)
            Text("Version \(updater.currentVersion)").font(.callout).foregroundStyle(.secondary)
            updateRow.frame(height: 32)
            HStack(spacing: 16) {
                Link("GitHub", destination: URL(string: "https://github.com/\(Updater.repository)")!)
                Link("Report an issue", destination: URL(string: "https://github.com/\(Updater.repository)/issues/new")!)
                Link("Website", destination: URL(string: "https://getkaeru.vercel.app")!)
            }
            .font(.callout)
            Spacer()
            Text("Free and open source. Audio and video use FFmpeg (LGPL/GPL). Files never leave your Mac.")
                .font(.caption).foregroundStyle(.tertiary).multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var updateRow: some View {
        switch updater.status {
        case .idle, .upToDate, .failed:
            HStack(spacing: 10) {
                Button("Check for Updates") { Task { await updater.check(interactive: true) } }
                if case .upToDate = updater.status { Label("Up to date", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                if case .failed(let message) = updater.status { Text(message).foregroundStyle(.orange).font(.caption) }
            }
        case .checking:
            ProgressView().controlSize(.small)
        case .available(let release):
            Button("Install Kaeru \(release.version)") { Task { await updater.install(release) } }.buttonStyle(.borderedProminent)
        case .downloading(let p):
            ProgressView(value: p) { Text("Downloading…").font(.caption) }.frame(width: 220)
        case .installing:
            Text("Installing…").foregroundStyle(.secondary)
        }
    }
}
