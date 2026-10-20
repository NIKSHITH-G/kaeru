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

/// How hard a shake has to be to open a shelf: how far each swing must travel.
enum ShakeStrength: String, CaseIterable, Identifiable {
    case gentle, normal, firm
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var minimumSwing: CGFloat { [.gentle: 28, .normal: 48, .firm: 80][self]! }
}

enum CloseOnDragOut: String, CaseIterable, Identifiable {
    case always, moved, never
    var id: String { rawValue }
    var label: String { [.always: "Always", .moved: "Only when files are moved", .never: "Never"][self]! }
}

enum DoubleClickFile: String, CaseIterable, Identifiable {
    case open, reveal, quickLook
    var id: String { rawValue }
    var label: String { [.open: "Open", .reveal: "Reveal in Finder", .quickLook: "Quick Look"][self]! }
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

    // MARK: Shelves

    static let shakeKey = "shelf.shakeToOpen"
    static let shakeStrengthKey = "shelf.shakeStrength"
    static let shakeIgnoredAppsKey = "shelf.shakeIgnoredApps"
    static let shelfAutoCloseKey = "shelf.autoClose"
    static let shelfAllSpacesKey = "shelf.allSpaces"
    static let shelfSoundsKey = "shelf.sounds"
    static let closeOnDragOutKey = "shelf.closeOnDragOut"
    static let doubleClickFileKey = "shelf.doubleClickFile"
    static let doubleClickEdgeKey = "shelf.doubleClickEdge"
    static let shelfSnapKey = "shelf.snap"
    static let shelfRetractKey = "shelf.retract"
    static let screenshotShelfKey = "shelf.screenshots"
    /// Pop, poof and chime sounds as files land on and leave shelves.
    static var shelfSounds: Bool { defaults.object(forKey: shelfSoundsKey) as? Bool ?? true }

    /// Shaking the pointer while dragging files opens a new shelf under it.
    static var shakeToOpen: Bool { defaults.object(forKey: shakeKey) as? Bool ?? true }
    static var shakeStrength: ShakeStrength { ShakeStrength(rawValue: defaults.string(forKey: shakeStrengthKey) ?? "") ?? .normal }
    /// Bundle identifiers of apps where shaking does nothing.
    static var shakeIgnoredApps: [String] {
        get { defaults.stringArray(forKey: shakeIgnoredAppsKey) ?? [] }
        set { defaults.set(newValue, forKey: shakeIgnoredAppsKey) }
    }
    /// When a shelf closes itself after files are dragged out of it (unless pinned).
    static var closeOnDragOut: CloseOnDragOut {
        if let raw = defaults.string(forKey: closeOnDragOutKey), let value = CloseOnDragOut(rawValue: raw) { return value }
        // Carry over the earlier on/off switch.
        return defaults.object(forKey: shelfAutoCloseKey) as? Bool == false ? .never : .always
    }
    static var shelfAutoClose: Bool { closeOnDragOut != .never }
    static var doubleClickFile: DoubleClickFile { DoubleClickFile(rawValue: defaults.string(forKey: doubleClickFileKey) ?? "") ?? .open }
    /// Double-clicking an empty part of a shelf tucks it into the screen edge.
    static var doubleClickEdgeCollapses: Bool { defaults.object(forKey: doubleClickEdgeKey) as? Bool ?? true }
    /// A shelf let go near a screen edge snaps neatly against it.
    static var shelfSnap: Bool { defaults.object(forKey: shelfSnapKey) as? Bool ?? false }
    /// A shelf tucks into the screen edge as soon as the first files land on it.
    static var shelfRetract: Bool { defaults.object(forKey: shelfRetractKey) as? Bool ?? false }
    /// New screenshots appear in a shelf.
    static var screenshotShelf: Bool { defaults.object(forKey: screenshotShelfKey) as? Bool ?? false }
    /// New shelves follow you to every Space.
    static var shelfAllSpaces: Bool { defaults.object(forKey: shelfAllSpacesKey) as? Bool ?? true }

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
