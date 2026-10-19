import AppKit
import Combine
import Carbon

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let dragMonitor = DragMonitor()
    private var hotKey: HotKey?
    private var dragToggle: NSMenuItem!
    private var recentMenu = NSMenu()
    private var updateItem: NSMenuItem!
    private var updateObserver: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()
        dragMonitor.start()
        KeyboardTap.shared.start()
        hotKey = HotKey(keyCode: kVK_ANSI_M, modifiers: controlKey | optionKey, id: 1) { [weak self] in
            self?.convertFinderSelection()
        }
        if !UserDefaults.standard.bool(forKey: "onboarded") {
            UserDefaults.standard.set(true, forKey: "onboarded")
            OnboardingWindow.show()
        }
        Updater.shared.startAutomaticChecks()
        // A dot on the frog and a "Restart to Update" menu item whenever an update is ready.
        updateObserver = Updater.shared.$status.receive(on: RunLoop.main).sink { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshUpdateIndicator() }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainWindow.show()
        return false
    }

    /// Files dropped on the Dock icon or sent via "Open With".
    func application(_ application: NSApplication, open urls: [URL]) {
        WheelController.shared.show(urls: urls, mode: .convert, at: NSEvent.mouseLocation, interactive: true)
    }

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = Artwork.menuBarIcon
        statusItem.button?.toolTip = "Kaeru"

        let menu = NSMenu()
        menu.delegate = self
        updateItem = add(menu, "Restart to Update", #selector(restartToUpdate))
        updateItem.isHidden = true
        add(menu, "Open Kaeru", #selector(openMain))
        add(menu, "Convert Finder Selection", #selector(convertFinderSelection), key: "m", modifiers: [.control, .option])
        add(menu, "New Shelf", #selector(newShelf), key: "s", modifiers: [.control, .option])
        let recent = menu.addItem(withTitle: "Recent", action: nil, keyEquivalent: "")
        recent.submenu = recentMenu
        menu.addItem(.separator())
        dragToggle = add(menu, "Drag Wheel", #selector(toggleDragWheel))
        add(menu, "Formats…", #selector(openFormats))
        add(menu, "Settings…", #selector(openSettings), key: ",")
        menu.addItem(.separator())
        add(menu, "Check for Updates…", #selector(checkForUpdates))
        add(menu, "Show Tutorial", #selector(showTutorial))
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Kaeru", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    @discardableResult
    private func add(_ menu: NSMenu, _ title: String, _ action: Selector, key: String = "",
                     modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = self
        return item
    }

    func menuWillOpen(_ menu: NSMenu) {
        dragToggle.state = Settings.dragWheelEnabled ? .on : .off
        recentMenu.removeAllItems()
        let jobs = JobCenter.shared.jobs.filter { !$0.existingOutputs.isEmpty }.prefix(6)
        if jobs.isEmpty {
            recentMenu.addItem(withTitle: "Nothing yet", action: nil, keyEquivalent: "").isEnabled = false
        }
        for job in jobs {
            let item = recentMenu.addItem(withTitle: "\(job.title) · \(job.subtitle)", action: #selector(revealRecent(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = job.existingOutputs
            item.image = job.thumbnail.map { thumb in
                let small = NSImage(size: NSSize(width: 18, height: 18))
                small.lockFocus()
                thumb.draw(in: NSRect(x: 0, y: 0, width: 18, height: 18))
                small.unlockFocus()
                return small
            }
        }
    }

    @objc private func revealRecent(_ sender: NSMenuItem) {
        if let urls = sender.representedObject as? [URL] { NSWorkspace.shared.activateFileViewerSelecting(urls) }
    }

    @objc private func newShelf() { ShelfManager.open(with: []) }

    @objc private func openFormats() { MainWindow.show(page: .formats) }
    @objc private func openSettings() { MainWindow.show(page: .settings) }
    @objc private func showTutorial() { OnboardingWindow.show() }

    @objc private func checkForUpdates() {
        Task {
            await Updater.shared.check(interactive: true)
            switch Updater.shared.status {
            case .upToDate: Toast.show("Kaeru \(Updater.shared.currentVersion) is the latest version")
            case .failed(let message): Toast.show(message, isError: true)
            default: break  // a ready update shows its own card
            }
        }
    }

    @objc private func restartToUpdate() { Updater.shared.restartNow() }

    private func refreshUpdateIndicator() {
        let ready = Updater.shared.readyRelease
        updateItem?.isHidden = ready == nil
        updateItem?.title = ready.map { "Restart to Update to \($0.version)" } ?? "Restart to Update"
        statusItem?.button?.image = ready == nil ? Artwork.menuBarIcon : Artwork.menuBarIconWithBadge
    }

    func applicationWillTerminate(_ notification: Notification) {
        Updater.shared.installOnQuitIfReady()
    }

    @objc private func openMain() { MainWindow.show(page: .home) }

    @objc private func toggleDragWheel() {
        UserDefaults.standard.set(!Settings.dragWheelEnabled, forKey: Settings.dragWheelKey)
    }

    @objc func convertFinderSelection() {
        let urls = FinderSelection.urls()
        guard !urls.isEmpty else {
            Toast.show("Select files in Finder first", isError: true)
            return
        }
        WheelController.shared.show(urls: urls, mode: .convert, at: NSEvent.mouseLocation, interactive: true)
    }
}
