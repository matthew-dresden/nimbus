import AppKit

final class PreferencesViewController: NSViewController {

    private static var windowController: NSWindowController?

    static func show() {
        if windowController == nil {
            let vc = PreferencesViewController()
            let win = NSWindow(contentViewController: vc)
            win.title = "Nimbus Preferences"
            win.styleMask = [.titled, .closable]
            win.center()
            windowController = NSWindowController(window: win)
        }
        windowController?.showWindow(nil)
    }

    private let prefs = PreferencesManager.shared

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 290))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
    }

    private func rebuildUI() {
        view.subviews.forEach { $0.removeFromSuperview() }
        buildUI()
    }

    private func buildUI() {
        // Title
        let title = NSTextField(labelWithString: "Nimbus Preferences")
        title.font = .boldSystemFont(ofSize: 16)
        title.frame = CGRect(x: 20, y: 250, width: 340, height: 22)
        view.addSubview(title)

        // Auto-copy URL toggle
        let autoCopyCheck = NSButton(checkboxWithTitle: "Auto-copy link after upload", target: self, action: #selector(toggleAutoCopy(_:)))
        autoCopyCheck.state = prefs.autoCopyURL ? .on : .off
        autoCopyCheck.frame = CGRect(x: 20, y: 215, width: 340, height: 22)
        view.addSubview(autoCopyCheck)

        // Auto-save toggle
        let autoSaveCheck = NSButton(checkboxWithTitle: "Auto-save screenshot to folder", target: self, action: #selector(toggleAutoSave(_:)))
        autoSaveCheck.state = prefs.autoSave ? .on : .off
        autoSaveCheck.frame = CGRect(x: 20, y: 185, width: 340, height: 22)
        view.addSubview(autoSaveCheck)

        // Save folder
        let folderLabel = NSTextField(labelWithString: "Save folder:")
        folderLabel.frame = CGRect(x: 20, y: 152, width: 80, height: 18)
        view.addSubview(folderLabel)

        let folderPath = NSTextField(labelWithString: prefs.saveFolder.path)
        folderPath.frame = CGRect(x: 105, y: 152, width: 195, height: 18)
        folderPath.lineBreakMode = .byTruncatingMiddle
        folderPath.textColor = .secondaryLabelColor
        view.addSubview(folderPath)

        let chooseBtn = NSButton(title: "Choose…", target: self, action: #selector(chooseSaveFolder))
        chooseBtn.frame = CGRect(x: 305, y: 148, width: 60, height: 26)
        view.addSubview(chooseBtn)

        // Imgur client ID (register free at api.imgur.com)
        let clientIDLabel = NSTextField(labelWithString: "Imgur Client ID:")
        clientIDLabel.frame = CGRect(x: 20, y: 118, width: 105, height: 18)
        view.addSubview(clientIDLabel)

        let clientIDField = NSTextField(string: prefs.imgurClientID)
        clientIDField.placeholderString = "Register free at api.imgur.com"
        clientIDField.frame = CGRect(x: 130, y: 114, width: 235, height: 22)
        clientIDField.target = self
        clientIDField.action = #selector(imgurClientIDChanged(_:))
        view.addSubview(clientIDField)

        // Hotkey hint
        let hotkeyLabel = NSTextField(labelWithString: "Capture shortcut: ⌘4 by default (configurable in code).")
        hotkeyLabel.font = .systemFont(ofSize: 11)
        hotkeyLabel.textColor = .tertiaryLabelColor
        hotkeyLabel.frame = CGRect(x: 20, y: 84, width: 340, height: 18)
        view.addSubview(hotkeyLabel)

        // Divider
        let line = NSBox()
        line.boxType = .separator
        line.frame = CGRect(x: 20, y: 68, width: 340, height: 1)
        view.addSubview(line)

        // Version
        let version = NSTextField(labelWithString: "Nimbus \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev") - Open Source ❤️")
        version.font = .systemFont(ofSize: 11)
        version.textColor = .tertiaryLabelColor
        version.frame = CGRect(x: 20, y: 16, width: 340, height: 18)
        view.addSubview(version)
    }

    @objc private func imgurClientIDChanged(_ sender: NSTextField) {
        prefs.imgurClientID = sender.stringValue
    }

    @objc private func toggleAutoCopy(_ sender: NSButton) {
        prefs.autoCopyURL = sender.state == .on
    }

    @objc private func toggleAutoSave(_ sender: NSButton) {
        prefs.autoSave = sender.state == .on
    }

    @objc private func chooseSaveFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Choose"
        panel.begin { [weak self] response in
            if response == .OK, let url = panel.url {
                self?.prefs.saveFolder = url
                DispatchQueue.main.async { self?.rebuildUI() }
            }
        }
    }
}
