import Cocoa

/// Watches for external displays connecting and for the Mac waking from
/// sleep, and reapplies the patched EDID each time -- the override
/// doesn't persist across either event, so this is the only way to
/// make it stick without you doing it by hand every time.
final class DisplayWatcher {

    private var knownDisplayIDs: Set<CGDirectDisplayID> = []
    private let onStatusChange: (String) -> Void

    init(onStatusChange: @escaping (String) -> Void) {
        self.onStatusChange = onStatusChange
        self.knownDisplayIDs = Set(NSScreen.screens.compactMap(DisplayWatcher.displayID(for:)))

        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(didWake),
            name: NSWorkspace.didWakeNotification, object: nil
        )
    }

    @objc private func screensChanged() {
        let current = Set(NSScreen.screens.compactMap(DisplayWatcher.displayID(for:)))
        let newlyConnected = current.subtracting(knownDisplayIDs)
        knownDisplayIDs = current

        guard !newlyConnected.isEmpty else { return }
        applyOverride()
    }

    @objc private func didWake() {
        // Give the display a couple seconds to re-negotiate before we
        // try to inject -- doing it immediately on wake is unreliable.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.applyOverride()
        }
    }

    func applyOverride() {
        guard let edid = try? Data(contentsOf: EDIDSourceWindowController.activeEDIDURL) else {
            onStatusChange("No EDID set yet — use “Set Custom EDID…”")
            return
        }
        let count = EDIDInjector.applyEDID(edid)
        onStatusChange(count > 0 ? "Applied to \(count) display(s)" : "No external display found")
    }

    func resetOverride() {
        EDIDInjector.reset()
        onStatusChange("Reset to native EDID")
    }

    private static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
