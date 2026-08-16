import AppKit

/// General-purpose side-by-side comparator. Works on files (existing menu
/// entries) and free snippets; panes stay editable and re-diff live on a
/// background queue. Text mode highlights additions, deletions, and paired
/// removed+added runs as *modified* sections; JSON mode compares structurally
/// (order-insensitive) and lists every changed path.
final class CompareWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSTextViewDelegate {
    private let leftText = NSTextView()
    private let rightText = NSTextView()
    private let leftScroll = NSScrollView()
    private let rightScroll = NSScrollView()
    private let divider = MarkdownDividerView(frame: .zero)
    private let modeSegment = NSSegmentedControl()
    private let syncToggle = NSButton(checkboxWithTitle: "Sync Scrolling", target: nil, action: nil)
    private let summaryLabel = NSTextField(labelWithString: "")
    private let changeTable = NSTableView()
    private let changeScroll = NSScrollView()
    private let textContainer = NSView()
    private let jsonContainer = NSView()
    private var paneWidth: NSLayoutConstraint!
    private var hunks: [DiffHunk] = []
    private var changes: [JsonDiffChange] = []
    private var jsonMode = false
    private var diffWorkItem: DispatchWorkItem?
    private var isSyncingScroll = false
    private var observations: [NSObjectProtocol] = []

    init(leftTitle: String, rightTitle: String, left: String, right: String) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1080, height: 640),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Compare — \(leftTitle) ↔ \(rightTitle)"
        window.minSize = NSSize(width: 620, height: 320)
        window.center()
        super.init(window: window)
        setupUI(leftTitle: leftTitle, rightTitle: rightTitle)
        leftText.string = left
        rightText.string = right
        recompute()
    }

    /// Empty comparator for pasting two snippets.
    static func snippets() -> CompareWindowController {
        CompareWindowController(
            leftTitle: "Left snippet",
            rightTitle: "Right snippet",
            left: "",
            right: ""
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - UI

    private func setupUI(leftTitle: String, rightTitle: String) {
        guard let content = window?.contentView else { return }

        // --- Top bar: titles, mode, sync toggle, summary.
        let bar = NSView()
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.wantsLayer = true
        bar.layer?.backgroundColor = NSColor.windowBackgroundColor.usingColorSpace(.deviceRGB)?.cgColor

        let leftLabel = NSTextField(labelWithString: leftTitle)
        let rightLabel = NSTextField(labelWithString: rightTitle)
        leftLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        rightLabel.font = .systemFont(ofSize: 12, weight: .semibold)

        modeSegment.segmentStyle = .texturedRounded
        modeSegment.segmentCount = 2
        modeSegment.setLabel("Text", forSegment: 0)
        modeSegment.setLabel("JSON", forSegment: 1)
        modeSegment.trackingMode = .selectOne
        modeSegment.setSelected(true, forSegment: 0)
        modeSegment.target = self
        modeSegment.action = #selector(modeChanged(_:))
        modeSegment.toolTip = "JSON compares structurally (key order ignored) and lists changed paths"

        syncToggle.state = .on
        syncToggle.target = self
        syncToggle.action = #selector(syncToggled(_:))

        summaryLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        summaryLabel.textColor = .secondaryLabelColor

        bar.addSubview(leftLabel)
        bar.addSubview(modeSegment)
        bar.addSubview(syncToggle)
        bar.addSubview(summaryLabel)
        bar.addSubview(rightLabel)
        NSLayoutConstraint.activate([
            bar.heightAnchor.constraint(equalToConstant: 40),
            leftLabel.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 12),
            leftLabel.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            modeSegment.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -12),
            modeSegment.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            syncToggle.trailingAnchor.constraint(equalTo: modeSegment.leadingAnchor, constant: -12),
            syncToggle.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            summaryLabel.centerXAnchor.constraint(equalTo: bar.centerXAnchor),
            summaryLabel.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            rightLabel.trailingAnchor.constraint(equalTo: summaryLabel.leadingAnchor, constant: -24),
            rightLabel.centerYAnchor.constraint(equalTo: bar.centerYAnchor)
        ])

        // --- Side-by-side text panes with a draggable divider (shared component).
        for (tv, scroll) in [(leftText, leftScroll), (rightText, rightScroll)] {
            tv.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            tv.isAutomaticQuoteSubstitutionEnabled = false
            tv.isAutomaticDashSubstitutionEnabled = false
            tv.isAutomaticTextReplacementEnabled = false
            tv.autoresizingMask = []
            tv.backgroundColor = NSColor.textBackgroundColor
            tv.delegate = self
            tv.allowsUndo = true
            scroll.documentView = tv
            scroll.hasVerticalScroller = true
            scroll.hasHorizontalScroller = true
            scroll.autohidesScrollers = true
            scroll.borderType = .noBorder
            scroll.translatesAutoresizingMaskIntoConstraints = false
        }
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.orientation = .horizontal
        divider.onDrag = { [weak self] delta in
            self?.adjustPane(delta: delta)
        }

        textContainer.translatesAutoresizingMaskIntoConstraints = false
        textContainer.addSubview(leftScroll)
        textContainer.addSubview(divider)
        textContainer.addSubview(rightScroll)
        paneWidth = rightScroll.widthAnchor.constraint(equalToConstant: 440)
        NSLayoutConstraint.activate([
            leftScroll.leadingAnchor.constraint(equalTo: textContainer.leadingAnchor),
            leftScroll.topAnchor.constraint(equalTo: textContainer.topAnchor),
            leftScroll.bottomAnchor.constraint(equalTo: textContainer.bottomAnchor),
            leftScroll.trailingAnchor.constraint(equalTo: divider.leadingAnchor),
            divider.widthAnchor.constraint(equalToConstant: 6),
            divider.topAnchor.constraint(equalTo: textContainer.topAnchor),
            divider.bottomAnchor.constraint(equalTo: textContainer.bottomAnchor),
            divider.trailingAnchor.constraint(equalTo: rightScroll.leadingAnchor),
            rightScroll.trailingAnchor.constraint(equalTo: textContainer.trailingAnchor),
            rightScroll.topAnchor.constraint(equalTo: textContainer.topAnchor),
            rightScroll.bottomAnchor.constraint(equalTo: textContainer.bottomAnchor),
            leftScroll.widthAnchor.constraint(greaterThanOrEqualToConstant: 180),
            paneWidth
        ])

        // --- JSON structural change list.
        let kindColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("kind"))
        kindColumn.title = "Change"
        kindColumn.width = 96
        let pathColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("path"))
        pathColumn.title = "Path"
        pathColumn.width = 260
        let valuesColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("values"))
        valuesColumn.title = "Left → Right"
        valuesColumn.width = 520
        changeTable.addTableColumn(kindColumn)
        changeTable.addTableColumn(pathColumn)
        changeTable.addTableColumn(valuesColumn)
        changeTable.dataSource = self
        changeTable.delegate = self
        changeTable.rowHeight = 22
        changeTable.usesAlternatingRowBackgroundColors = true
        changeScroll.documentView = changeTable
        changeScroll.hasVerticalScroller = true
        changeScroll.translatesAutoresizingMaskIntoConstraints = false
        jsonContainer.translatesAutoresizingMaskIntoConstraints = false
        jsonContainer.addSubview(changeScroll)
        NSLayoutConstraint.activate([
            changeScroll.leadingAnchor.constraint(equalTo: jsonContainer.leadingAnchor),
            changeScroll.trailingAnchor.constraint(equalTo: jsonContainer.trailingAnchor),
            changeScroll.topAnchor.constraint(equalTo: jsonContainer.topAnchor),
            changeScroll.bottomAnchor.constraint(equalTo: jsonContainer.bottomAnchor)
        ])
        jsonContainer.isHidden = true

        content.addSubview(bar)
        content.addSubview(textContainer)
        content.addSubview(jsonContainer)
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            bar.topAnchor.constraint(equalTo: content.topAnchor),
            textContainer.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            textContainer.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            textContainer.topAnchor.constraint(equalTo: bar.bottomAnchor),
            textContainer.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            jsonContainer.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            jsonContainer.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            jsonContainer.topAnchor.constraint(equalTo: bar.bottomAnchor),
            jsonContainer.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])

        installScrollSync()
        applyTheme()
        NotificationCenter.default.addObserver(
            self, selector: #selector(themeChanged), name: .themeDidChange, object: nil
        )
    }

    private func adjustPane(delta: CGFloat) {
        let total = textContainer.bounds.width
        let current = rightScroll.bounds.width
        paneWidth.constant = min(max(current - delta, 180), max(180, total - 200))
    }

    // MARK: - Theme

    @objc private func themeChanged() { applyTheme() }

    private func applyTheme() {
        let dark = ThemeManager.shared.current.isDark
        divider.applyTheme(ThemeManager.shared.current)
        for tv in [leftText, rightText] {
            tv.backgroundColor = dark
                ? NSColor(calibratedRed: 0.13, green: 0.14, blue: 0.15, alpha: 1)
                : NSColor.textBackgroundColor
        }
        if jsonMode {
            renderTextPanes()
        }
    }

    // MARK: - Sync scrolling

    private func installScrollSync() {
        let names: [Notification.Name] = [NSView.boundsDidChangeNotification, NSView.frameDidChangeNotification]
        for clip in [leftScroll.contentView, rightScroll.contentView] {
            clip.postsBoundsChangedNotifications = true
            for name in names {
                observations.append(NotificationCenter.default.addObserver(
                    forName: name, object: clip, queue: .main
                ) { [weak self] note in
                    self?.syncScroll(from: note.object as? NSClipView)
                })
            }
        }
    }

    private func syncScroll(from source: NSClipView?) {
        guard syncToggle.state == .on, !isSyncingScroll, let source else { return }
        let target: NSClipView = source === leftScroll.contentView ? rightScroll.contentView : leftScroll.contentView
        guard let sourceDoc = source.documentView, let targetDoc = target.documentView else { return }
        isSyncingScroll = true
        // Proportional: pane heights differ when lines were added/removed.
        let sourceRange = max(sourceDoc.bounds.height - source.bounds.height, 1)
        let targetRange = max(targetDoc.bounds.height - target.bounds.height, 1)
        let ratio = source.bounds.origin.y / sourceRange
        var point = target.bounds.origin
        point.y = ratio * targetRange
        target.scroll(to: point)
        target.superview?.reflectScrolledClipView(target)
        isSyncingScroll = false
    }

    // MARK: - Diffing

    func textDidChange(_ notification: Notification) {
        recompute(debounced: true)
    }

    private func recompute(debounced: Bool = false) {
        diffWorkItem?.cancel()
        let left = leftText.string
        let right = rightText.string
        let work = DispatchWorkItem { [weak self] in
            self?.compute(left: left, right: right)
        }
        diffWorkItem = work
        let delay: TimeInterval = debounced ? 0.3 : 0
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    // Test hooks: the async path never lands without a runloop.
    var hunkCount: Int { hunks.count }
    var changeCount: Int { changes.count }
    var leftTextForTesting: String {
        get { leftText.string }
        set { leftText.string = newValue }
    }
    var rightTextForTesting: String {
        get { rightText.string }
        set { rightText.string = newValue }
    }

    func setJSONModeForTesting(_ on: Bool) {
        jsonMode = on
    }

    func recomputeNow() {
        let left = leftText.string
        let right = rightText.string
        let leftForDiff = jsonMode ? ((try? JsonFormatter.pretty(left)) ?? left) : left
        let rightForDiff = jsonMode ? ((try? JsonFormatter.pretty(right)) ?? right) : right
        hunks = DiffEngine.diff(left: leftForDiff, right: rightForDiff)
        changes = jsonMode ? JsonDiff.compare(leftText: left, rightText: right).changes : []
        renderTextPanes()
        changeTable.reloadData()
        updateSummary()
    }

    /// Hunk diffing happens off the main thread; big files stay interactive.
    private func compute(left: String, right: String) {
        let leftForDiff = jsonMode ? ((try? JsonFormatter.pretty(left)) ?? left) : left
        let rightForDiff = jsonMode ? ((try? JsonFormatter.pretty(right)) ?? right) : right
        let useJSON = jsonMode
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            let computed = DiffEngine.diff(left: leftForDiff, right: rightForDiff)
            let jsonChanges: [JsonDiffChange]
            if useJSON {
                jsonChanges = JsonDiff.compare(leftText: left, rightText: right).changes
            } else {
                jsonChanges = []
            }
            let diffed = computed
            DispatchQueue.main.async {
                self?.hunks = diffed
                self?.changes = jsonChanges
                self?.renderTextPanes()
                self?.changeTable.reloadData()
                self?.updateSummary()
            }
        }
    }

    private func updateSummary() {
        var added = 0, removed = 0
        for hunk in hunks {
            if hunk.kind == .added { added += 1 }
            if hunk.kind == .removed { removed += 1 }
        }
        if jsonMode {
            summaryLabel.stringValue = changes.isEmpty
                ? "JSON: identical structure"
                : "JSON: \(changes.count) structural change\(changes.count == 1 ? "" : "s")"
        } else {
            summaryLabel.stringValue = "+\(added)  −\(removed)"
        }
        modeSegment.setEnabled(JsonDiff.bothValid(leftText.string, rightText.string) || !modeSegment.isSelected(forSegment: 1), forSegment: 1)
    }

    /// Colors each line: green added, red removed, amber when a removed run is
    /// paired with an added run (a modification).
    private func renderTextPanes() {
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let dark = ThemeManager.shared.current.isDark

        func color(_ kind: DiffHunk.Kind, modified: Bool) -> NSColor {
            let alpha: CGFloat = dark ? 0.32 : 0.2
            switch kind {
            case .same: return .clear
            case .added: return modified
                ? NSColor.systemYellow.withAlphaComponent(alpha)
                : NSColor.systemGreen.withAlphaComponent(alpha)
            case .removed: return modified
                ? NSColor.systemYellow.withAlphaComponent(alpha)
                : NSColor.systemRed.withAlphaComponent(alpha)
            }
        }

        // Pair consecutive removed+added runs as modified blocks.
        var modifiedRanges: [ClosedRange<Int>] = []
        var i = 0
        while i < hunks.count {
            guard hunks[i].kind == .removed else { i += 1; continue }
            var removedEnd = i
            while removedEnd + 1 < hunks.count, hunks[removedEnd + 1].kind == .removed { removedEnd += 1 }
            var next = removedEnd + 1
            var addedEnd = -1
            if next < hunks.count, hunks[next].kind == .added {
                addedEnd = next
                while addedEnd + 1 < hunks.count, hunks[addedEnd + 1].kind == .added { addedEnd += 1 }
                modifiedRanges.append(i...addedEnd)
                next = addedEnd + 1
            }
            i = next
        }
        func isModified(_ index: Int) -> Bool {
            modifiedRanges.contains { $0.contains(index) }
        }

        // To keep huge documents smooth, identical lines share one attributed
        // string; only diff hunks get per-line attributes.
        let sameAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.textColor]
        var leftParts: [NSAttributedString] = []
        var rightParts: [NSAttributedString] = []
        var sameBuffer: [String] = []

        func flushSame() {
            guard !sameBuffer.isEmpty else { return }
            let block = (sameBuffer.joined(separator: "\n") + "\n") as NSString
            leftParts.append(NSAttributedString(string: block as String, attributes: sameAttrs))
            rightParts.append(NSAttributedString(string: block as String, attributes: sameAttrs))
            sameBuffer.removeAll()
        }

        for (index, hunk) in hunks.enumerated() {
            if hunk.kind == .same {
                sameBuffer.append(hunk.text)
                continue
            }
            flushSame()
            let modified = isModified(index)
            switch hunk.kind {
            case .removed:
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .backgroundColor: color(.removed, modified: modified)]
                leftParts.append(NSAttributedString(string: hunk.text + "\n", attributes: attrs))
            case .added:
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .backgroundColor: color(.added, modified: modified)]
                rightParts.append(NSAttributedString(string: hunk.text + "\n", attributes: attrs))
            default:
                break
            }
        }
        flushSame()

        let leftOut = NSMutableAttributedString()
        leftParts.forEach(leftOut.append)
        let rightOut = NSMutableAttributedString()
        rightParts.forEach(rightOut.append)
        let leftSel = leftText.selectedRange
        let rightSel = rightText.selectedRange
        leftText.textStorage?.setAttributedString(leftOut)
        rightText.textStorage?.setAttributedString(rightOut)
        leftText.setSelectedRange(leftSel)
        rightText.setSelectedRange(rightSel)
    }

    // MARK: - Mode

    @objc private func modeChanged(_ sender: NSSegmentedControl) {
        jsonMode = sender.isSelected(forSegment: 1)
        textContainer.isHidden = jsonMode
        jsonContainer.isHidden = !jsonMode
        recompute()
    }

    @objc private func syncToggled(_ sender: NSButton) {
        if sender.state == .on {
            syncScroll(from: leftScroll.contentView)
        }
    }

    deinit {
        observations.forEach { NotificationCenter.default.removeObserver($0) }
    }

    // MARK: - Change list (JSON mode)

    func numberOfRows(in tableView: NSTableView) -> Int { changes.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let change = changes[row]
        let field = NSTextField(labelWithString: "")
        field.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        field.lineBreakMode = .byTruncatingMiddle
        switch tableColumn?.identifier.rawValue {
        case "kind":
            let (symbol, color): (String, NSColor) = {
                switch change.kind {
                case .added: return ("added", .systemGreen)
                case .removed: return ("removed", .systemRed)
                case .changed: return ("changed", .systemOrange)
                case .typeChanged: return ("type", .systemPurple)
                }
            }()
            field.stringValue = symbol
            field.textColor = color
        case "path":
            field.stringValue = change.path
        default:
            switch (change.left, change.right) {
            case let (l?, r?): field.stringValue = "\(l)  →  \(r)"
            case let (nil, r?): field.stringValue = r
            case let (l?, nil): field.stringValue = l
            default: field.stringValue = ""
            }
            field.toolTip = "Type: \(change.typeDescription)"
        }
        return field
    }
}
