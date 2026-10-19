import AppKit

let arguments = Array(CommandLine.arguments.dropFirst())

if let command = arguments.first, command.hasPrefix("--") {
    // Headless mode for scripting and tests:
    //   Kaeru --list <files…>          print available operation ids
    //   Kaeru --run <op-id> <files…>   run one operation and print the outputs
    let files = arguments.dropFirst(command == "--run" ? 2 : 1).map { URL(fileURLWithPath: $0) }
    // Headless runs must never prompt to control PowerPoint/Keynote unless asked to.
    if command == "--self-test" { setenv("KAERU_NO_APPS", "1", 1) }
    Task { @MainActor in
        switch command {
        case "--list":
            for mode in WheelMode.allCases {
                let ops = Registry.operations(for: files, mode: mode)
                print("\(mode.title): " + ops.map(\.id).joined(separator: " "))
            }
            exit(0)
        case "--render-wheel" where arguments.count >= 3:
            // Kaeru --render-wheel <mode 0-2> <files…> — draws the wheel to wheel.png for design checks.
            let mode = WheelMode(rawValue: Int(arguments[1]) ?? 0) ?? .convert
            let targets = Array(files.dropFirst()).filter { $0.lastPathComponent != "dark" }
            let items = Registry.operations(for: targets, mode: mode)
            let side = WheelView.diameter(forItems: items.count) + 40
            let view = WheelView(frame: NSRect(x: 0, y: 0, width: side, height: side))
            view.configure(urls: targets, mode: mode, items: items, interactive: false)
            NSApp.appearance = NSAppearance(named: arguments.contains("dark") ? .darkAqua : .aqua)
            view.appearance = NSApp.appearance
            let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
            view.cacheDisplay(in: view.bounds, to: rep)
            // Composite over a soft backdrop that stands in for the live frosted glass.
            let out = NSImage(size: view.bounds.size, flipped: false) { rect in
                let dark = arguments.contains("dark")
                let ring = NSBezierPath(ovalIn: rect.insetBy(dx: 20 + WheelView.pop, dy: 20 + WheelView.pop))
                (dark ? NSColor(white: 0.16, alpha: 0.96) : NSColor(white: 0.97, alpha: 0.96)).setFill()
                let shadow = NSShadow()
                shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
                shadow.shadowBlurRadius = 16
                shadow.shadowOffset = NSSize(width: 0, height: -5)
                NSGraphicsContext.saveGraphicsState(); shadow.set(); ring.fill(); NSGraphicsContext.restoreGraphicsState()
                rep.draw(in: rect)
                return true
            }
            if let tiff = out.tiffRepresentation, let final = NSBitmapImageRep(data: tiff) {
                try? final.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "wheel.png"))
            }
            exit(0)
        case "--self-test":
            exit(SelfTest.run())
        case "--make-icon" where arguments.count >= 2:
            // Kaeru --make-icon <out.png> — the 1024px app icon, from the same artwork the app draws.
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8,
                                       samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                       bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            Artwork.drawIcon(shadow: true)
            NSGraphicsContext.restoreGraphicsState()
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: arguments[1]))
            exit(0)
        case "--render" where arguments.count >= 2:
            // Kaeru --render <main|formats|settings|about|onboarding|onboarding1|crop> [file] [dark]
            // draws that window to render.png for design checks.
            NSApp.appearance = NSAppearance(named: arguments.contains("dark") ? .darkAqua : .aqua)
            let target = arguments[1]
            switch target {
            case "crop":
                if let image = try? ImageOps.load(URL(fileURLWithPath: arguments[2])).0 {
                    Task { _ = await CropWindow.ask(image: image, title: "photo.png") }
                }
            case let t where t.hasPrefix("onboarding"):
                OnboardingWindow.show()
                OnboardingModel.shared.step = Int(t.dropFirst(10)) ?? 0
            default:
                MainWindow.show(page: AppModel.Page(rawValue: target.capitalized) ?? .home)
            }
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if let view = NSApp.windows.first(where: { $0.isVisible && !($0 is NSPanel) })?.contentView?.superview,
               let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "render.png"))
            }
            exit(0)
        case "--run" where arguments.count >= 3:
            guard let op = Registry.find(arguments[1], for: files) else {
                FileHandle.standardError.write(Data("Unknown operation \(arguments[1]) for these files\n".utf8))
                exit(2)
            }
            do {
                let result = try await op.run(files) { _ in }
                result.outputs.forEach { print($0.path) }
                if let message = result.message { print(message) }
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("Error: \(error.localizedDescription)\n".utf8))
                exit(1)
            }
        default:
            print("usage: Kaeru --list <files…> | Kaeru --run <op-id> <files…>")
            exit(2)
        }
    }
    NSApplication.shared.setActivationPolicy(command == "--render" ? .accessory : .prohibited)
    NSApplication.shared.run()
} else {
    let delegate = MainActor.assumeIsolated { AppDelegate() }
    NSApplication.shared.delegate = delegate
    NSApplication.shared.setActivationPolicy(.accessory)
    NSApplication.shared.run()
}
