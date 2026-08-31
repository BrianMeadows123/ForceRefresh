import Cocoa
import UniformTypeIdentifiers

/// A small window for setting the active EDID either by pasting plain
/// hex (the output of `xxd -p monitor_59_94.bin`) or by picking the
/// .bin file directly. Whatever you provide gets written to a fixed
/// location so DisplayWatcher always knows where to find it -- no
/// rebuilding the app required to swap EDIDs.
final class EDIDSourceWindowController: NSWindowController {

    static let activeEDIDURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ForceRefresh")
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        return appSupport.appendingPathComponent("active-edid.bin")
    }()

    private let textView = NSTextView()
    private var pickedFileURL: URL?
    private var pickedFileLabel: NSTextField?
    private let onSaved: () -> Void

    init(onSaved: @escaping () -> Void) {
        self.onSaved = onSaved
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        window.title = "Set custom EDID"
        window.center()
        super.init(window: window)
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }

        let label = NSTextField(labelWithString:
            "Paste hex from `xxd -p monitor_59_94.bin`, or choose the file directly:")
        label.frame = NSRect(x: 16, y: 284, width: 448, height: 20)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        contentView.addSubview(label)

        let scrollView = NSScrollView(frame: NSRect(x: 16, y: 90, width: 448, height: 184))
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.isRichText = false
        textView.autoresizingMask = [.width]
        scrollView.documentView = textView
        contentView.addSubview(scrollView)

        let chooseButton = NSButton(title: "Choose File…", target: self, action: #selector(chooseFile))
        chooseButton.frame = NSRect(x: 16, y: 50, width: 120, height: 28)
        contentView.addSubview(chooseButton)

        let fileLabel = NSTextField(labelWithString: "")
        fileLabel.frame = NSRect(x: 144, y: 55, width: 320, height: 18)
        fileLabel.font = .systemFont(ofSize: 11)
        fileLabel.textColor = .secondaryLabelColor
        contentView.addSubview(fileLabel)
        pickedFileLabel = fileLabel

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancelButton.frame = NSRect(x: 292, y: 12, width: 80, height: 28)
        contentView.addSubview(cancelButton)

        let saveButton = NSButton(title: "Save & Apply", target: self, action: #selector(save))
        saveButton.frame = NSRect(x: 376, y: 12, width: 100, height: 28)
        saveButton.keyEquivalent = "\r"
        contentView.addSubview(saveButton)
    }

    @objc private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.data]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a raw EDID .bin file"
        guard let window else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.pickedFileURL = url
            self?.pickedFileLabel?.stringValue = url.lastPathComponent
            self?.textView.string = "" // a chosen file takes precedence over pasted hex
        }
    }

    @objc private func cancel() {
        window?.close()
    }

    @objc private func save() {
        let data: Data
        if let pickedFileURL, let fileData = try? Data(contentsOf: pickedFileURL) {
            data = fileData
        } else {
            let hexOnly = textView.string.filter { $0.isHexDigit }
            guard let parsed = Data(hexString: hexOnly) else {
                showError("Couldn't parse that as hex. Paste the output of `xxd -p monitor_59_94.bin`.")
                return
            }
            data = parsed
        }

        guard data.count > 0, data.count % 128 == 0 else {
            showError("That's \(data.count) bytes -- a valid EDID is a multiple of 128 bytes (128, 256...).")
            return
        }

        do {
            try data.write(to: Self.activeEDIDURL)
        } catch {
            showError("Couldn't save the EDID file: \(error.localizedDescription)")
            return
        }

        onSaved()
        window?.close()
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Invalid EDID"
        alert.informativeText = message
        alert.alertStyle = .warning
        if let window { alert.beginSheetModal(for: window) }
    }
}

private extension Data {
    init?(hexString: String) {
        guard hexString.count % 2 == 0 else { return nil }
        var data = Data(capacity: hexString.count / 2)
        var index = hexString.startIndex
        while index < hexString.endIndex {
            let next = hexString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexString[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        self = data
    }
}
