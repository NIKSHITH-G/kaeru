import AppKit
import ApplicationServices
import Carbon

/// Optional keyboard hook (needs Accessibility permission). It provides two features that
/// modifier flags alone can't:
///   • Tab as a wheel trigger: Tab is a normal key, so its up/down state is tracked here.
///   • Return in Finder opens the wheel for the selection, except while renaming or searching.
@MainActor
final class KeyboardTap {
    static let shared = KeyboardTap()

    /// Set from the C callback, which runs on the main run loop.
    nonisolated(unsafe) static var tabDown = false
    private var tap: CFMachPort?
    private var retryTimer: Timer?

    var isRunning: Bool { tap != nil }
    var isTrusted: Bool { AXIsProcessTrusted() }

    /// Starts now if permission is already granted, otherwise keeps checking until it is.
    func start() {
        guard tap == nil else { return }
        if AXIsProcessTrusted() {
            install()
        } else if retryTimer == nil {
            retryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, AXIsProcessTrusted() else { return }
                    self.retryTimer?.invalidate()
                    self.retryTimer = nil
                    self.install()
                }
            }
        }
    }

    /// Shows the system prompt that sends the user to Privacy & Security → Accessibility.
    func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        start()
    }

    private func install() {
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: CGEventMask(mask), callback: keyboardTapCallback,
                                          userInfo: nil) else {
            NSLog("Kaeru: couldn't create keyboard tap")
            return
        }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
    }

    fileprivate func reenable() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    /// True when Return should open the wheel instead of reaching Finder.
    fileprivate func shouldCaptureReturn(_ event: CGEvent) -> Bool {
        guard Settings.returnInFinder,
              event.getIntegerValueField(.keyboardEventAutorepeat) == 0,
              event.flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]).isEmpty,
              let finder = NSWorkspace.shared.frontmostApplication, finder.bundleIdentifier == "com.apple.finder"
        else { return false }
        return !isEditingText(in: finder.processIdentifier)
    }

    /// Renaming a file or typing in the search field focuses a text element; leave Return alone then.
    private func isEditingText(in pid: pid_t) -> Bool {
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXFocusedUIElementAttribute as CFString,
                                            &focused) == .success, let element = focused else { return false }
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(element as! AXUIElement, kAXRoleAttribute as CFString, &role)
        let textRoles: Set<String> = [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole, "AXSearchField"]
        return textRoles.contains(role as? String ?? "")
    }
}

private func keyboardTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                                 userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        MainActor.assumeIsolated { KeyboardTap.shared.reenable() }
        return Unmanaged.passUnretained(event)
    }
    let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
    if keyCode == kVK_Tab {
        KeyboardTap.tabDown = type == .keyDown
    } else if type == .keyDown, keyCode == kVK_Return || keyCode == kVK_ANSI_KeypadEnter {
        let capture = MainActor.assumeIsolated { KeyboardTap.shared.shouldCaptureReturn(event) }
        if capture {
            DispatchQueue.main.async {
                (NSApp.delegate as? AppDelegate)?.convertFinderSelection()
            }
            return nil
        }
    }
    return Unmanaged.passUnretained(event)
}
