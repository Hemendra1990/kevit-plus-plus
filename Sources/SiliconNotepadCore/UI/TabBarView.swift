import AppKit

protocol TabBarViewDelegate: AnyObject {
    func tabBar(_ tabBar: TabBarView, didSelect index: Int)
    func tabBar(_ tabBar: TabBarView, didClose index: Int)
    func tabBar(_ tabBar: TabBarView, didReorder from: Int, to: Int)
    func tabBar(_ tabBar: TabBarView, perform action: TabBarAction, at index: Int)
    /// Clicking the empty area beside the tabs requests a new tab.
    func tabBarDidRequestNewTab(_ tabBar: TabBarView)
}

enum TabBarAction: Int {
    case close, closeOthers, closeAll, closeLeft, closeRight
    case moveToStart, moveToEnd, moveLeft, moveRight
    case clone, copyPath, copyFilename, openContainingFolder, renameSaveAs, reload
}

final class TabBarView: NSView {
    weak var delegate: TabBarViewDelegate?

    private let scrollView = NSScrollView()
    private let stack = NSStackView()
    private var tabViews: [TabItemView] = []
    private var selectedIndex: Int = -1

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        stack.orientation = .horizontal
        stack.spacing = 0
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        stack.translatesAutoresizingMaskIntoConstraints = false

        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.horizontalScrollElasticity = .allowed
        scrollView.documentView = stack
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.heightAnchor.constraint(equalTo: scrollView.heightAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func applyTheme(_ theme: EditorTheme) {
        layer?.backgroundColor = theme.tabBackground.cgColor
        for (index, tab) in tabViews.enumerated() {
            tab.applyTheme(theme, selected: index == selectedIndex)
        }
    }

    func reload(titles: [String], selectedIndex: Int) {
        self.selectedIndex = selectedIndex
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        tabViews.removeAll()

        for (index, title) in titles.enumerated() {
            let tab = TabItemView(title: title, index: index, selected: index == selectedIndex)
            tab.onSelect = { [weak self] idx in self?.delegate?.tabBar(self!, didSelect: idx) }
            tab.onClose = { [weak self] idx in self?.delegate?.tabBar(self!, didClose: idx) }
            tab.onAction = { [weak self] action, idx in self?.delegate?.tabBar(self!, perform: action, at: idx) }
            tabViews.append(tab)
            stack.addArrangedSubview(tab)
        }
        applyTheme(ThemeManager.shared.current)
        stack.layoutSubtreeIfNeeded()
        let width = tabViews.reduce(CGFloat(0)) { $0 + max($1.fittingSize.width, 90) }
        stack.setFrameSize(NSSize(width: max(width, scrollView.bounds.width), height: max(scrollView.bounds.height, 30)))
        scrollSelectedTabIntoView()
    }

    private func scrollSelectedTabIntoView() {
        guard tabViews.indices.contains(selectedIndex) else { return }
        let tab = tabViews[selectedIndex]
        tab.layoutSubtreeIfNeeded()
        scrollView.contentView.scrollToVisible(tab.frame)
    }

    /// A click counts as "empty area" only when it lands beyond the last tab
    /// (or there are no tabs at all) — clicks anywhere within the tab region,
    /// including gaps between tabs, are ignored to avoid accidents.
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if shouldCreateTab(clickingAt: point) {
            delegate?.tabBarDidRequestNewTab(self)
        } else {
            super.mouseDown(with: event)
        }
    }

    func shouldCreateTab(clickingAt point: NSPoint) -> Bool {
        guard let last = tabViews.last else { return true }
        last.layoutSubtreeIfNeeded()
        let frameInBar = convert(last.frame, from: last.superview)
        return point.x > frameInBar.maxX + 2
    }
}

private final class TabItemView: NSView {
    var onSelect: ((Int) -> Void)?
    var onClose: ((Int) -> Void)?
    var onAction: ((TabBarAction, Int) -> Void)?

    private let accentBar = NSView()
    private let iconView = NSImageView()
    private let titleButton = NSButton()
    private let closeButton = NSButton()
    private let index: Int
    private var isSelected: Bool

    init(title: String, index: Int, selected: Bool) {
        self.index = index
        self.isSelected = selected
        super.init(frame: .zero)
        wantsLayer = true

        accentBar.wantsLayer = true
        accentBar.translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImage(systemSymbolName: "doc.fill", accessibilityDescription: nil)
        iconView.image = icon
        iconView.contentTintColor = NSColor(calibratedRed: 0.75, green: 0.25, blue: 0.35, alpha: 1)
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
        iconView.translatesAutoresizingMaskIntoConstraints = false

        titleButton.title = title
        titleButton.bezelStyle = .inline
        titleButton.isBordered = false
        titleButton.font = .systemFont(ofSize: 12, weight: selected ? .semibold : .regular)
        titleButton.target = self
        titleButton.action = #selector(selectTab)
        titleButton.toolTip = title
        titleButton.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        // Dirty docs use • prefix from Document.displayName
        if title.hasPrefix("• ") {
            iconView.contentTintColor = NSColor(calibratedRed: 0.95, green: 0.55, blue: 0.15, alpha: 1)
        }

        closeButton.title = "×"
        closeButton.bezelStyle = .inline
        closeButton.isBordered = false
        closeButton.font = .systemFont(ofSize: 13, weight: .regular)
        closeButton.target = self
        closeButton.action = #selector(closeTab)
        closeButton.toolTip = "Close"

        let content = NSStackView(views: [iconView, titleButton, closeButton])
        content.orientation = .horizontal
        content.spacing = 5
        content.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 6)
        content.translatesAutoresizingMaskIntoConstraints = false

        addSubview(accentBar)
        addSubview(content)

        NSLayoutConstraint.activate([
            accentBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            accentBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            accentBar.topAnchor.constraint(equalTo: topAnchor),
            accentBar.heightAnchor.constraint(equalToConstant: 3),

            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: accentBar.bottomAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),

            heightAnchor.constraint(equalToConstant: 30),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 90),
            widthAnchor.constraint(lessThanOrEqualToConstant: 200),
            iconView.widthAnchor.constraint(equalToConstant: 12),
            iconView.heightAnchor.constraint(equalToConstant: 12)
        ])

        menu = buildContextMenu()
        let middle = NSClickGestureRecognizer(target: self, action: #selector(middleClick(_:)))
        middle.buttonMask = 0x4
        addGestureRecognizer(middle)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func applyTheme(_ theme: EditorTheme, selected: Bool) {
        isSelected = selected
        layer?.backgroundColor = (selected ? theme.tabActiveBackground : theme.tabBackground).cgColor
        accentBar.layer?.backgroundColor = selected ? theme.tabAccent.cgColor : NSColor.clear.cgColor
        let textColor = selected ? theme.tabActiveText : theme.tabInactiveText
        titleButton.contentTintColor = textColor
        titleButton.font = .systemFont(ofSize: 12, weight: selected ? .semibold : .regular)
        closeButton.contentTintColor = textColor.withAlphaComponent(0.7)
        // Separator edge like N++
        layer?.borderWidth = 0.5
        layer?.borderColor = theme.chromeBackground.blended(withFraction: 0.3, of: .black)?.cgColor
            ?? theme.statusForeground.withAlphaComponent(0.15).cgColor
    }

    private func buildContextMenu() -> NSMenu {
        let menu = NSMenu(title: "Tab")
        func item(_ title: String, _ action: TabBarAction) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: #selector(menuAction(_:)), keyEquivalent: "")
            i.target = self
            i.tag = action.rawValue
            return i
        }
        menu.addItem(item("Close", .close))
        menu.addItem(item("Close Others", .closeOthers))
        menu.addItem(item("Close All", .closeAll))
        menu.addItem(item("Close All to the Left", .closeLeft))
        menu.addItem(item("Close All to the Right", .closeRight))
        menu.addItem(.separator())
        menu.addItem(item("Move Tab to Start", .moveToStart))
        menu.addItem(item("Move Tab to End", .moveToEnd))
        menu.addItem(item("Move Tab Left", .moveLeft))
        menu.addItem(item("Move Tab Right", .moveRight))
        menu.addItem(.separator())
        menu.addItem(item("Clone to New Tab", .clone))
        menu.addItem(item("Reload from Disk", .reload))
        menu.addItem(item("Save As…", .renameSaveAs))
        menu.addItem(.separator())
        menu.addItem(item("Copy File Path", .copyPath))
        menu.addItem(item("Copy Filename", .copyFilename))
        menu.addItem(item("Open Containing Folder", .openContainingFolder))
        return menu
    }

    @objc private func selectTab() { onSelect?(index) }
    @objc private func closeTab() { onClose?(index) }
    @objc private func middleClick(_ g: NSClickGestureRecognizer) { onClose?(index) }
    @objc private func menuAction(_ sender: NSMenuItem) {
        guard let action = TabBarAction(rawValue: sender.tag) else { return }
        if action == .close { onClose?(index) } else { onAction?(action, index) }
    }
}
