import AppKit

final class PreferencesWindowController: NSWindowController {
    static let shared = PreferencesWindowController()

    private let fontSizeField = NSTextField(string: "")
    private let tabWidthField = NSTextField(string: "")
    private let encodingPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let eolPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let autoReloadButton = NSButton(checkboxWithTitle: "Reload files when changed on disk", target: nil, action: nil)
    private let toolbarButton = NSButton(checkboxWithTitle: "Show toolbar", target: nil, action: nil)

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Preferences"
        window.center()
        super.init(window: window)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        guard let content = window?.contentView else { return }
        let prefs = Preferences.shared

        fontSizeField.stringValue = String(Int(prefs.fontSize))
        tabWidthField.stringValue = String(prefs.tabWidth)
        autoReloadButton.state = prefs.autoReloadFiles ? .on : .off
        toolbarButton.state = prefs.showToolbar ? .on : .off

        for encoding in TextEncodingKind.allCases {
            encodingPopup.addItem(withTitle: encoding.rawValue)
        }
        encodingPopup.selectItem(withTitle: prefs.defaultEncoding.rawValue)

        for eol in EOLStyle.allCases {
            eolPopup.addItem(withTitle: eol.rawValue)
        }
        eolPopup.selectItem(withTitle: prefs.defaultEOL.rawValue)

        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Font size:"), fontSizeField],
            [NSTextField(labelWithString: "Tab width:"), tabWidthField],
            [NSTextField(labelWithString: "Default encoding:"), encodingPopup],
            [NSTextField(labelWithString: "Default EOL:"), eolPopup],
            [NSTextField(labelWithString: ""), autoReloadButton],
            [NSTextField(labelWithString: ""), toolbarButton]
        ])
        grid.translatesAutoresizingMaskIntoConstraints = false

        let save = NSButton(title: "Save", target: self, action: #selector(savePrefs))
        save.bezelStyle = .rounded
        save.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(grid)
        content.addSubview(save)
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            grid.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            save.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            save.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16)
        ])
    }

    @objc private func savePrefs() {
        let prefs = Preferences.shared
        if let size = Double(fontSizeField.stringValue), size > 0 {
            prefs.fontSize = CGFloat(size)
        }
        if let tabs = Int(tabWidthField.stringValue), tabs > 0 {
            prefs.tabWidth = tabs
        }
        if let encoding = TextEncodingKind(rawValue: encodingPopup.titleOfSelectedItem ?? "") {
            prefs.defaultEncoding = encoding
        }
        if let eol = EOLStyle(rawValue: eolPopup.titleOfSelectedItem ?? "") {
            prefs.defaultEOL = eol
        }
        prefs.autoReloadFiles = autoReloadButton.state == .on
        prefs.showToolbar = toolbarButton.state == .on
        window?.close()
    }
}
