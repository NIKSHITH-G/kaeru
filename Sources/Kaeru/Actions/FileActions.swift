import AppKit

/// The Actions wheel: things you do *with* files rather than to them. Works on folders and mixed selections.
enum FileActions {
    static let all: [FileOperation] = [
        instant("action.airdrop", "AirDrop", "airplayaudio") { urls in
            guard let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: urls) else {
                throw fail("AirDrop isn't available")
            }
            NSApp.activate(ignoringOtherApps: true)
            service.perform(withItems: urls)
            return nil
        },
        instant("action.float", "Shelf", "tray.full") { urls in
            ShelfManager.open(with: urls)
            return nil
        },
        instant("action.copy", "Copy", "doc.on.doc") { urls in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects(urls as [NSURL])
            return "Copied \(urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) items") — paste in Finder"
        },
        instant("action.path", "Copy Path", "link") { urls in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(urls.map(\.path).joined(separator: "\n"), forType: .string)
            return "Copied path"
        },
        instant("action.move", "Move To…", "folder") { urls in
            NSApp.activate(ignoringOtherApps: true)
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.canCreateDirectories = true
            panel.prompt = "Move Here"
            panel.directoryURL = urls[0].deletingLastPathComponent()
            guard panel.runModal() == .OK, let dir = panel.url else { return nil }
            for url in urls {
                try FileManager.default.moveItem(at: url, to: Output.unique(dir.appendingPathComponent(url.lastPathComponent)))
            }
            return "Moved to \(dir.lastPathComponent)"
        },
        instant("action.terminal", "Terminal", "terminal") { urls in
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: urls[0].path, isDirectory: &isDir)
            let dir = isDir.boolValue ? urls[0] : urls[0].deletingLastPathComponent()
            let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal")
                ?? URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
            NSWorkspace.shared.open([dir], withApplicationAt: terminal,
                                    configuration: NSWorkspace.OpenConfiguration())
            return nil
        },
        instant("action.reveal", "Reveal", "magnifyingglass") { urls in
            NSWorkspace.shared.activateFileViewerSelecting(urls)
            return nil
        },
    ]

    private static func instant(_ id: String, _ title: String, _ symbol: String,
                                _ body: @escaping @MainActor ([URL]) throws -> String?) -> FileOperation {
        FileOperation(id: id, title: title, symbol: symbol, isInstant: true) { urls, _ in
            OpResult(message: try await MainActor.run { try body(urls) })
        }
    }
}
