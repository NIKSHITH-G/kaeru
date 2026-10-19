import AppKit
import Carbon
import ServiceManagement

enum OutputLocation: String, CaseIterable, Identifiable {
    case sameFolder, downloads, desktop

    var id: String { rawValue }
    var label: String {
        switch self {
        case .sameFolder: return "Next to the original"
        case .downloads: return "Downloads"
        case .desktop: return "Desktop"
        }
    }
}

/// Keys that open a wheel while dragging. Tab and fn are offered for people whose Shift is
/// already taken by another drag tool.
enum ModifierKey: String, CaseIterable, Identifiable {
    case shift, command, control, option, fn, tab

    var id: String { rawValue }
    var glyph: String {
        switch self {
        case .tab: return "⇥"
        case .option: return "⌥"
        case .fn: return "fn"
        case .shift: return "⇧"
        case .command: return "⌘"
        case .control: return "⌃"
        }
    }
    var label: String { "\(glyph) \(self == .fn ? "Function" : rawValue.capitalized)" }

    func isPressed(_ flags: NSEvent.ModifierFlags) -> Bool {
        switch self {
        case .tab:
            // The keyboard tap tracks Tab when Accessibility is granted; the key-state query covers
            // systems where reading it doesn't need extra permission.
            return KeyboardTap.tabDown || CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(kVK_Tab))
        case .option: return flags.contains(.option)
        case .fn: return flags.contains(.function)
        case .shift: return flags.contains(.shift)
        case .command: return flags.contains(.command)
        case .control: return flags.contains(.control)
        }
    }
}

enum Settings {
    private static var defaults: UserDefaults { .standard }

    static let outputLocationKey = "outputLocation"
    static let dragWheelKey = "dragWheelEnabled"
    static let returnInFinderKey = "returnInFinder"
    static func modifierKey(_ mode: WheelMode) -> String { "trigger.\(mode.rawValue)" }
    static let defaultTriggers: [ModifierKey] = [.shift, .command, .control]

    static var outputLocation: OutputLocation {
        OutputLocation(rawValue: defaults.string(forKey: outputLocationKey) ?? "") ?? .sameFolder
    }

    static var dragWheelEnabled: Bool { defaults.object(forKey: dragWheelKey) as? Bool ?? true }

    /// Return in Finder opens the wheel (needs Accessibility; renaming and search still get Return).
    static var returnInFinder: Bool { defaults.object(forKey: returnInFinderKey) as? Bool ?? true }

    static func modifier(for mode: WheelMode) -> ModifierKey {
        ModifierKey(rawValue: defaults.string(forKey: modifierKey(mode)) ?? "") ?? defaultTriggers[mode.rawValue]
    }

    /// Which wheel the currently held keys ask for, if any.
    static func mode(for flags: NSEvent.ModifierFlags) -> WheelMode? {
        WheelMode.allCases.first { modifier(for: $0).isPressed(flags) }
    }

    static var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Kaeru: launch at login failed: \(error)")
            }
        }
    }
}
