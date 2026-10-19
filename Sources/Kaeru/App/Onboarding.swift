import AppKit
import Combine
import SwiftUI

/// First-run tutorial: welcome, a hands-on try with a sample file, keyboard setup, done.
final class OnboardingWindow: NSWindow {
    private static var shared: OnboardingWindow?

    @MainActor
    static func show() {
        let window = shared ?? OnboardingWindow()
        shared = window
        OnboardingModel.shared.step = 0
        OnboardingModel.shared.welcomeStart = Date()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    @MainActor
    private init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 680, height: 500), styleMask: [.titled, .closable, .fullSizeContentView],
                   backing: .buffered, defer: false)
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        contentView = NSHostingView(rootView: OnboardingView())
        center()
    }
}

@MainActor
final class OnboardingModel: ObservableObject {
    static let shared = OnboardingModel()

    @Published var step = 0
    /// When the welcome screen appeared; drives its staged entrance and animations.
    var welcomeStart = Date()
    @Published var triedIt = false
    @Published var result: URL?
    let sample: URL
    private var subscription: AnyCancellable?

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Kaeru/Tutorial")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        sample = dir.appendingPathComponent("Kaeru Frog.png")
        if !FileManager.default.fileExists(atPath: sample.path) { Self.drawSample(to: sample) }

        // The tutorial step completes the first time anything made from the sample succeeds.
        subscription = JobCenter.shared.finished.sink { [weak self] job in
            guard let self, job.subtitle == self.sample.lastPathComponent, case .done = job.state else { return }
            self.result = job.existingOutputs.first
            withAnimation(.spring(response: 0.4)) { self.triedIt = true }
        }
    }

    private static func drawSample(to url: URL) {
        let image = NSImage(size: NSSize(width: 640, height: 480), flipped: false) { rect in
            NSGradient(colors: [NSColor(srgbRed: 0.85, green: 0.97, blue: 0.9, alpha: 1),
                                NSColor(srgbRed: 0.65, green: 0.9, blue: 0.98, alpha: 1)])!.draw(in: rect, angle: -60)
            Artwork.appMark(size: 260).draw(in: NSRect(x: 190, y: 110, width: 260, height: 260))
            return true
        }
        if let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
        }
    }
}

private struct OnboardingView: View {
    @ObservedObject private var model = OnboardingModel.shared
    @ObservedObject private var app = AppModel.shared

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch model.step {
                case 0: welcome
                case 1: tryIt
                case 2: keyboard
                default: ready
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)))
            footer
        }
        .frame(width: 680, height: 500)
        .overlay(alignment: .topTrailing) {
            if model.step < 3 {
                Button("Skip tutorial") { NSApp.keyWindow?.close() }
                    .buttonStyle(.link).font(.system(size: 12)).padding(.top, 14).padding(.trailing, 18)
            }
        }
        .background(LinearGradient(colors: [Theme.brand.swiftUI.opacity(0.10), .clear], startPoint: .top, endPoint: .center))
    }

    private var welcome: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSince(model.welcomeStart)
            HStack(spacing: 28) {
                VStack(alignment: .leading, spacing: 13) {
                    Image(nsImage: Artwork.appMark(size: 72))
                        .shadow(color: Theme.brand.swiftUI.opacity(0.45), radius: 16, y: 8)
                        .offset(y: sin(t * 2.2) * 3)
                        .appear(t, 0.05)
                    Text("Welcome to Kaeru").font(.system(size: 32, weight: .bold, design: .rounded)).appear(t, 0.15)
                    Text("かえる means “to change” — and “frog”.").foregroundStyle(.secondary).appear(t, 0.25)
                    FormatFlip(t: t - 0.4).padding(.vertical, 6).appear(t, 0.4)
                    Text("Drag any file, hold a key, and drop it on what you want. No apps to open, nothing uploaded.")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).appear(t, 0.5)
                    HStack(spacing: 8) {
                        pill("lock.shield", "Private")
                        pill("bolt", "Instant")
                        pill("square.grid.3x3", "350+ conversions")
                    }
                    .padding(.top, 4)
                    .appear(t, 0.6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                WheelPreview(hover: Int(max(0, t - 0.8) / 0.75))
                    .aspectRatio(WheelPreview.aspect, contentMode: .fit)
                    .frame(width: 250)
                    .appear(t, 0.3)
            }
            .padding(.horizontal, 36)
        }
    }

    private func pill(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol).font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Capsule().fill(.background.opacity(0.7)))
            .overlay(Capsule().strokeBorder(.separator))
    }

    private var tryIt: some View {
        VStack(spacing: 18) {
            Text(model.triedIt ? "That’s all there is to it" : "Try it now").font(.system(size: 26, weight: .bold, design: .rounded))
            if model.triedIt {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 54)).foregroundStyle(.green)
                    Text("You converted your first file. It works the same way from Finder, the Desktop or any app.")
                        .multilineTextAlignment(.center).foregroundStyle(.secondary)
                    if let result = model.result {
                        Button("Show the result") { NSWorkspace.shared.activateFileViewerSelecting([result]) }
                    }
                }
                .transition(.scale.combined(with: .opacity))
            } else {
                HStack(spacing: 28) {
                    DraggableFile(url: model.sample)
                        .frame(width: 130, height: 150)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.background))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.separator))
                        .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
                    VStack(alignment: .leading, spacing: 14) {
                        step(1, "Start dragging the frog picture")
                        step(2, "While dragging, press", key: Settings.modifier(for: .convert).glyph)
                        step(3, "Drop it on **JPG** in the wheel")
                    }
                }
                Text("Tip: hold ⌘ for tools or ⌃ for actions instead — try switching while the wheel is open.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(30)
    }

    private func step(_ n: Int, _ text: LocalizedStringKey, key: String? = nil) -> some View {
        HStack(spacing: 10) {
            Text("\(n)").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                .frame(width: 22, height: 22).background(Circle().fill(Theme.brand.swiftUI))
            Text(text)
            if let key { KeyCap(text: key) }
        }
    }

    private var keyboard: some View {
        VStack(spacing: 16) {
            KeyCap(text: "↩", large: true).scaleEffect(1.4).padding(.bottom, 6)
            Text("Press Return in Finder").font(.system(size: 26, weight: .bold, design: .rounded))
            Text("Select files in Finder and press Return to open the wheel — no dragging needed. Renaming still works as usual.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 420)
            if app.keyboardReady {
                Label("Ready", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.headline)
            } else {
                Button("Allow Keyboard Access…") { KeyboardTap.shared.requestPermission() }.controlSize(.large)
                Text("In System Settings → Privacy & Security → Accessibility (called “Device Control and Data Access” on newer macOS), switch on Kaeru. If it’s already on, select it, click −, then add it again with +.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 420)
                Button("Open System Settings") { KeyboardTap.shared.openSystemSettings() }.buttonStyle(.link).font(.caption)
            }
        }
        .padding(30)
    }

    private var ready: some View {
        VStack(spacing: 16) {
            Image(nsImage: Artwork.menuBarIcon).resizable().frame(width: 44, height: 44).foregroundStyle(Theme.brand.swiftUI)
            Text("You’re all set").font(.system(size: 28, weight: .bold, design: .rounded))
            Text("Kaeru lives in your menu bar. Click the frog any time for history, settings and formats.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 400)
            Toggle("Open Kaeru when I log in", isOn: $app.launchAtLogin).toggleStyle(.switch).padding(.top, 8)
        }
        .padding(30)
    }

    private var footer: some View {
        HStack {
            HStack(spacing: 6) {
                ForEach(0..<4) { i in
                    Capsule().fill(i == model.step ? Theme.brand.swiftUI : Color.secondary.opacity(0.3))
                        .frame(width: i == model.step ? 18 : 7, height: 7)
                }
            }
            Spacer()
            if model.step > 0 && model.step < 3 {
                Button(model.step == 1 && !model.triedIt ? "Skip" : "Back") {
                    advance(model.step == 1 && !model.triedIt ? 1 : -1)
                }
            }
            Button(model.step == 3 ? "Start Using Kaeru" : model.step == 0 ? "Get Started" : "Continue") {
                if model.step == 3 { NSApp.keyWindow?.close() } else { advance(1) }
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .tint(Theme.brand.swiftUI)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    private func advance(_ delta: Int) {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) { model.step = max(0, min(3, model.step + delta)) }
    }
}
