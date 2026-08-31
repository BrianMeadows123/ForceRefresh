import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var watcher: DisplayWatcher!
    private var edidWindowController: EDIDSourceWindowController?
    private let statusMenuItem = NSMenuItem(title: "Status: —", action: nil, keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "tv", accessibilityDescription: "ForceRefresh")

        watcher = DisplayWatcher { [weak self] status in
            DispatchQueue.main.async {
                self?.statusMenuItem.title = "Status: \(status)"
            }
        }

        let menu = NSMenu()
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Set Custom EDID…", action: #selector(setEDID), keyEquivalent: "e")
        menu.addItem(withTitle: "Apply now", action: #selector(applyNow), keyEquivalent: "a")
        menu.addItem(withTitle: "Reset to native EDID", action: #selector(resetNow), keyEquivalent: "r")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu

        // Try once at launch in case the display is already connected
        // and an EDID was already set in a previous session.
        watcher.applyOverride()
    }

    @objc private func setEDID() {
        let controller = EDIDSourceWindowController { [weak self] in
            self?.watcher.applyOverride()
        }
        edidWindowController = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func applyNow() { watcher.applyOverride() }
    @objc private func resetNow() { watcher.resetOverride() }
}
