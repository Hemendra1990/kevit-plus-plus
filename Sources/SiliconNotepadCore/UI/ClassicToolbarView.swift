import AppKit

/// Classic Notepad++-style icon strip (separate from macOS NSToolbar).
final class ClassicToolbarView: NSView {
    weak var target: AnyObject?

    private let stack = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        stack.orientation = .horizontal
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 3, left: 6, bottom: 3, right: 6)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: 32)
        ])
        rebuild()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func applyTheme(_ theme: EditorTheme) {
        layer?.backgroundColor = theme.toolbarBackground.cgColor
        layer?.borderWidth = 0.5
        layer?.borderColor = theme.tabBackground.cgColor
        let iconColor = theme.isDark ? theme.tabActiveText : NSColor(calibratedWhite: 0.12, alpha: 1)
        for view in stack.arrangedSubviews {
            guard let btn = view as? NSButton else { continue }
            btn.contentTintColor = iconColor
        }
    }

    func rebuild() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let items: [(String, String, Selector)] = [
            ("doc", "New", #selector(MainWindowController.newDocument(_:))),
            ("square.and.pencil", "New Drawing", #selector(MainWindowController.newDrawing(_:))),
            ("folder", "Open", #selector(MainWindowController.openDocument(_:))),
            ("square.and.arrow.down", "Save", #selector(MainWindowController.saveDocument(_:))),
            ("square.and.arrow.down.on.square", "Save All", #selector(MainWindowController.saveAllDocuments(_:))),
            ("xmark.circle", "Close", #selector(MainWindowController.closeDocument(_:))),
            ("xmark.circle.fill", "Close All", #selector(MainWindowController.closeAllTabs(_:))),
            ("", "", #selector(NSObject.description)), // separator marker
            ("printer", "Print", #selector(MainWindowController.printDocument(_:))),
            ("scissors", "Cut", #selector(NSText.cut(_:))),
            ("doc.on.doc", "Copy", #selector(NSText.copy(_:))),
            ("doc.on.clipboard", "Paste", #selector(NSText.paste(_:))),
            ("arrow.uturn.backward", "Undo", Selector(("undo:"))),
            ("arrow.uturn.forward", "Redo", Selector(("redo:"))),
            ("", "", #selector(NSObject.description)),
            ("magnifyingglass", "Find", #selector(MainWindowController.showFindPanel(_:))),
            ("arrow.left.arrow.right", "Replace", #selector(MainWindowController.showReplacePanel(_:))),
            ("plus.magnifyingglass", "Zoom In", #selector(MainWindowController.zoomIn(_:))),
            ("minus.magnifyingglass", "Zoom Out", #selector(MainWindowController.zoomOut(_:))),
            ("text.alignleft", "Word Wrap", #selector(MainWindowController.toggleWordWrap(_:))),
            ("paragraphsign", "Show Symbols", #selector(MainWindowController.toggleInvisibleCharacters(_:))),
            ("", "", #selector(NSObject.description)),
            ("record.circle", "Start Macro", #selector(MainWindowController.startMacroRecording(_:))),
            ("stop.circle", "Stop Macro", #selector(MainWindowController.stopMacroRecording(_:))),
            ("play.circle", "Play Macro", #selector(MainWindowController.playbackMacro(_:)))
        ]

        for (symbol, tip, action) in items {
            if symbol.isEmpty {
                let sep = NSBox()
                sep.boxType = .separator
                sep.translatesAutoresizingMaskIntoConstraints = false
                sep.widthAnchor.constraint(equalToConstant: 8).isActive = true
                stack.addArrangedSubview(sep)
                continue
            }
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            let btn = NSButton()
            btn.bezelStyle = .accessoryBarAction
            btn.isBordered = false
            if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)?
                .withSymbolConfiguration(config) {
                image.isTemplate = true
                btn.image = image
            }
            btn.imagePosition = .imageOnly
            btn.toolTip = tip
            btn.target = (tip == "Cut" || tip == "Copy" || tip == "Paste" || tip == "Undo" || tip == "Redo") ? nil : target
            btn.action = action
            btn.setButtonType(.momentaryPushIn)
            btn.contentTintColor = ThemeManager.shared.current.isDark
                ? ThemeManager.shared.current.tabActiveText
                : NSColor(calibratedWhite: 0.12, alpha: 1)
            btn.widthAnchor.constraint(equalToConstant: 28).isActive = true
            btn.heightAnchor.constraint(equalToConstant: 24).isActive = true
            stack.addArrangedSubview(btn)
        }
    }
}
