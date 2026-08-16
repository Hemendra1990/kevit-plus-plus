import AppKit

/// String Manipulation workbench: input → operation chain → output.
///
/// The UI is generated from `StringOperationKind` (popup, parameter fields,
/// chain rows), so new operations appear without touching this controller's
/// architecture. Pure transformation logic lives in `StringOperations.swift`
/// and is unit-tested independently of the window.
final class StringWorkbenchWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSTextViewDelegate, NSTextFieldDelegate {
    private let opPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let chainTable = NSTableView()
    private let paramHost = NSView()
    private let inputText = NSTextView()
    private let outputText = NSTextView()
    private let inputScroll = NSScrollView()
    private let outputScroll = NSScrollView()
    private let ioDivider = MarkdownDividerView(frame: .zero)
    private let statsLabel = NSTextField(labelWithString: "Ready")
    private let errorLabel = NSTextField(labelWithString: "")
    private let undoButton = NSButton(title: "Undo", target: nil, action: nil)
    private let redoButton = NSButton(title: "Redo", target: nil, action: nil)
    private var ioWidth: NSLayoutConstraint!

    private var chain = StringOperationChain()
    private var recomputeWork: DispatchWorkItem?
    private var computeGeneration = 0
    private var history: [(input: String, chain: StringOperationChain)] = []
    private var historyIndex = -1

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1060, height: 660),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "String Workbench"
        window.minSize = NSSize(width: 680, height: 400)
        window.center()
        super.init(window: window)
        setupUI()
        rebuildChainTable()
        rebuildParamEditor()
        pushHistory()
        recomputeNow()
        applyTheme()
        NotificationCenter.default.addObserver(
            self, selector: #selector(themeChanged), name: .themeDidChange, object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - UI construction

    private func setupUI() {
        guard let content = window?.contentView else { return }

        // --- Top bar: operation picker + add + undo/redo.
        let topBar = NSView()
        topBar.translatesAutoresizingMaskIntoConstraints = false
        topBar.wantsLayer = true

        buildOperationPopup()
        opPopup.translatesAutoresizingMaskIntoConstraints = false

        let addButton = NSButton(title: "Add", target: self, action: #selector(addStep(_:)))
        addButton.bezelStyle = .texturedRounded
        addButton.keyEquivalent = "\r"
        addButton.keyEquivalentModifierMask = [.command, .shift]
        addButton.translatesAutoresizingMaskIntoConstraints = false

        for (button, selector) in [(undoButton, #selector(undo(_:))), (redoButton, #selector(redo(_:)))] {
            button.bezelStyle = .texturedRounded
            button.target = self
            button.action = selector
            button.translatesAutoresizingMaskIntoConstraints = false
        }

        topBar.addSubview(opPopup)
        topBar.addSubview(addButton)
        topBar.addSubview(undoButton)
        topBar.addSubview(redoButton)
        NSLayoutConstraint.activate([
            topBar.heightAnchor.constraint(equalToConstant: 40),
            opPopup.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 12),
            opPopup.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            addButton.leadingAnchor.constraint(equalTo: opPopup.trailingAnchor, constant: 8),
            addButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            redoButton.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -12),
            redoButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            undoButton.trailingAnchor.constraint(equalTo: redoButton.leadingAnchor, constant: -8),
            undoButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor)
        ])

        // --- Chain sidebar: steps table + step controls + parameter editor.
        let sidebar = NSView()
        sidebar.translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("step"))
        column.title = "Operation Chain"
        chainTable.addTableColumn(column)
        chainTable.dataSource = self
        chainTable.delegate = self
        chainTable.rowHeight = 26
        chainTable.headerView = nil
        chainTable.usesAlternatingRowBackgroundColors = true

        let chainScroll = NSScrollView()
        chainScroll.documentView = chainTable
        chainScroll.hasVerticalScroller = true
        chainScroll.translatesAutoresizingMaskIntoConstraints = false

        func stepButton(_ title: String, _ selector: Selector) -> NSButton {
            let button = NSButton(title: title, target: self, action: selector)
            button.bezelStyle = .texturedRounded
            button.font = .systemFont(ofSize: 11)
            button.translatesAutoresizingMaskIntoConstraints = false
            return button
        }
        let removeButton = stepButton("− Remove", #selector(removeStep(_:)))
        let upButton = stepButton("↑", #selector(moveStepUp(_:)))
        let downButton = stepButton("↓", #selector(moveStepDown(_:)))

        let controls = NSStackView(views: [removeButton, upButton, downButton])
        controls.orientation = .horizontal
        controls.spacing = 6
        controls.translatesAutoresizingMaskIntoConstraints = false

        paramHost.translatesAutoresizingMaskIntoConstraints = false

        sidebar.addSubview(chainScroll)
        sidebar.addSubview(controls)
        sidebar.addSubview(paramHost)
        NSLayoutConstraint.activate([
            sidebar.widthAnchor.constraint(equalToConstant: 264),
            chainScroll.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 10),
            chainScroll.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -10),
            chainScroll.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 10),
            chainScroll.heightAnchor.constraint(equalToConstant: 200),
            controls.topAnchor.constraint(equalTo: chainScroll.bottomAnchor, constant: 8),
            controls.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 10),
            paramHost.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 10),
            paramHost.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -10),
            paramHost.topAnchor.constraint(equalTo: controls.bottomAnchor, constant: 12),
            paramHost.bottomAnchor.constraint(lessThanOrEqualTo: sidebar.bottomAnchor, constant: -10)
        ])

        // --- IO area: input | divider | output.
        for (tv, scroll) in [(inputText, inputScroll), (outputText, outputScroll)] {
            tv.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            tv.isAutomaticQuoteSubstitutionEnabled = false
            tv.isAutomaticDashSubstitutionEnabled = false
            tv.isAutomaticTextReplacementEnabled = false
            tv.autoresizingMask = []
            tv.allowsUndo = true
            scroll.documentView = tv
            scroll.hasVerticalScroller = true
            scroll.hasHorizontalScroller = true
            scroll.autohidesScrollers = true
            scroll.borderType = .bezelBorder
            scroll.translatesAutoresizingMaskIntoConstraints = false
        }
        outputText.isEditable = false
        inputText.delegate = self

        ioDivider.translatesAutoresizingMaskIntoConstraints = false
        ioDivider.orientation = .horizontal
        ioDivider.onDrag = { [weak self] delta in
            self?.adjustOutputPane(delta: delta)
        }

        let ioArea = NSView()
        ioArea.translatesAutoresizingMaskIntoConstraints = false
        ioArea.addSubview(inputScroll)
        ioArea.addSubview(ioDivider)
        ioArea.addSubview(outputScroll)
        ioWidth = outputScroll.widthAnchor.constraint(equalToConstant: 420)
        NSLayoutConstraint.activate([
            inputScroll.leadingAnchor.constraint(equalTo: ioArea.leadingAnchor),
            inputScroll.topAnchor.constraint(equalTo: ioArea.topAnchor),
            inputScroll.bottomAnchor.constraint(equalTo: ioArea.bottomAnchor),
            inputScroll.trailingAnchor.constraint(equalTo: ioDivider.leadingAnchor),
            ioDivider.widthAnchor.constraint(equalToConstant: 6),
            ioDivider.topAnchor.constraint(equalTo: ioArea.topAnchor),
            ioDivider.bottomAnchor.constraint(equalTo: ioArea.bottomAnchor),
            ioDivider.trailingAnchor.constraint(equalTo: outputScroll.leadingAnchor),
            outputScroll.trailingAnchor.constraint(equalTo: ioArea.trailingAnchor),
            outputScroll.topAnchor.constraint(equalTo: ioArea.topAnchor),
            outputScroll.bottomAnchor.constraint(equalTo: ioArea.bottomAnchor),
            inputScroll.widthAnchor.constraint(greaterThanOrEqualToConstant: 180),
            ioWidth
        ])

        // --- Bottom bar: stats, error, actions.
        let bottomBar = NSView()
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.wantsLayer = true

        statsLabel.font = .monospacedSystemFont(ofSize: 10.5, weight: .regular)
        statsLabel.textColor = .secondaryLabelColor
        statsLabel.translatesAutoresizingMaskIntoConstraints = false

        errorLabel.font = .systemFont(ofSize: 11)
        errorLabel.textColor = .systemRed
        errorLabel.lineBreakMode = .byTruncatingHead
        errorLabel.translatesAutoresizingMaskIntoConstraints = false

        func actionButton(_ title: String, key: String, modifiers: NSEvent.ModifierFlags, _ selector: Selector) -> NSButton {
            let button = NSButton(title: title, target: self, action: selector)
            button.bezelStyle = .texturedRounded
            button.keyEquivalent = key
            button.keyEquivalentModifierMask = modifiers
            button.translatesAutoresizingMaskIntoConstraints = false
            return button
        }
        let copyButton = actionButton("Copy Output", key: "c", modifiers: [.command, .shift], #selector(copyOutput(_:)))
        let applyButton = actionButton("Apply to Input", key: "\r", modifiers: [.command], #selector(applyToInput(_:)))
        let swapButton = actionButton("Swap", key: "s", modifiers: [.command, .shift], #selector(swapPanes(_:)))
        let clearButton = actionButton("Clear", key: "\u{8}", modifiers: [.command, .shift], #selector(clearAll(_:)))
        let downloadButton = actionButton("Download…", key: "d", modifiers: [.command, .shift], #selector(downloadOutput(_:)))

        bottomBar.addSubview(statsLabel)
        bottomBar.addSubview(errorLabel)
        bottomBar.addSubview(copyButton)
        bottomBar.addSubview(applyButton)
        bottomBar.addSubview(swapButton)
        bottomBar.addSubview(clearButton)
        bottomBar.addSubview(downloadButton)
        NSLayoutConstraint.activate([
            bottomBar.heightAnchor.constraint(equalToConstant: 42),
            statsLabel.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 12),
            statsLabel.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
            errorLabel.leadingAnchor.constraint(equalTo: statsLabel.trailingAnchor, constant: 12),
            errorLabel.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
            downloadButton.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -12),
            downloadButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
            clearButton.trailingAnchor.constraint(equalTo: downloadButton.leadingAnchor, constant: -8),
            clearButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
            swapButton.trailingAnchor.constraint(equalTo: clearButton.leadingAnchor, constant: -8),
            swapButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
            applyButton.trailingAnchor.constraint(equalTo: swapButton.leadingAnchor, constant: -8),
            applyButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
            copyButton.trailingAnchor.constraint(equalTo: applyButton.leadingAnchor, constant: -8),
            copyButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor)
        ])

        content.addSubview(topBar)
        content.addSubview(sidebar)
        content.addSubview(ioArea)
        content.addSubview(bottomBar)
        NSLayoutConstraint.activate([
            topBar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            topBar.topAnchor.constraint(equalTo: content.topAnchor),
            bottomBar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            sidebar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: topBar.bottomAnchor),
            sidebar.bottomAnchor.constraint(equalTo: bottomBar.topAnchor),
            ioArea.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            ioArea.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            ioArea.topAnchor.constraint(equalTo: topBar.bottomAnchor),
            ioArea.bottomAnchor.constraint(equalTo: bottomBar.topAnchor)
        ])

        let inputPlaceholder = NSTextField(labelWithString: "Input")
        inputPlaceholder.font = .systemFont(ofSize: 10, weight: .semibold)
        inputPlaceholder.textColor = .secondaryLabelColor
        inputScroll.addSubview(inputPlaceholder)
        inputPlaceholder.frame.origin = NSPoint(x: 8, y: 4)
    }

    private func buildOperationPopup() {
        let menu = NSMenu()
        for category in ["Case & Text", "Lines", "Search & Replace", "Affixes & Wrapping", "Line Endings", "Escape & Encode", "Analysis"] {
            let item = NSMenuItem(title: category, action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: category)
            for kind in StringOperationKind.allCases where kind.category == category {
                let opItem = NSMenuItem(
                    title: kind.title,
                    action: nil,
                    keyEquivalent: ""
                )
                opItem.representedObject = kind.rawValue
                submenu.addItem(opItem)
            }
            item.submenu = submenu
            menu.addItem(item)
        }
        opPopup.menu = menu
        opPopup.toolTip = "Pick an operation, then Add to append it to the chain (⇧⌘↩)"
    }

    private func adjustOutputPane(delta: CGFloat) {
        let total = outputScroll.superview?.bounds.width ?? 800
        let current = outputScroll.bounds.width
        ioWidth.constant = min(max(current - delta, 180), max(180, total - 200))
    }

    // MARK: - Chain table

    func numberOfRows(in tableView: NSTableView) -> Int { chain.steps.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard chain.steps.indices.contains(row) else { return nil }
        let step = chain.steps[row]
        let field = NSTextField(labelWithString: "")
        field.font = .monospacedSystemFont(ofSize: 11.5, weight: .regular)
        field.lineBreakMode = .byTruncatingMiddle
        field.textColor = row == chainTable.selectedRow ? .controlAccentColor : .labelColor
        field.stringValue = "\(row + 1). \(step.summary)"
        return field
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        rebuildParamEditor()
    }

    // MARK: - Parameter editor (built from the selected step's spec)

    private var parameterField: NSTextField?
    private var secondaryField: NSTextField?
    private var flagButton: NSButton?

    private func rebuildParamEditor() {
        paramHost.subviews.forEach { $0.removeFromSuperview() }
        parameterField = nil
        secondaryField = nil
        flagButton = nil

        let index = chainTable.selectedRow
        guard chain.steps.indices.contains(index) else {
            let hint = NSTextField(labelWithString: chain.isEmpty
                ? "Add operations to build a chain."
                : "Select a step to edit its parameters.")
            hint.font = .systemFont(ofSize: 11)
            hint.textColor = .secondaryLabelColor
            hint.translatesAutoresizingMaskIntoConstraints = false
            paramHost.addSubview(hint)
            NSLayoutConstraint.activate([
                hint.topAnchor.constraint(equalTo: paramHost.topAnchor),
                hint.leadingAnchor.constraint(equalTo: paramHost.leadingAnchor)
            ])
            return
        }

        let step = chain.steps[index]
        var previous: NSView = paramHost
        var first = true

        func attach(_ view: NSView) {
            view.translatesAutoresizingMaskIntoConstraints = false
            paramHost.addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: paramHost.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: paramHost.trailingAnchor),
                first
                    ? view.topAnchor.constraint(equalTo: paramHost.topAnchor)
                    : view.topAnchor.constraint(equalTo: previous.bottomAnchor, constant: 8)
            ])
            previous = view
            first = false
        }

        func makeField(_ label: String, placeholder: String, value: String, secondary: Bool) -> NSTextField {
            let field = NSTextField(string: value)
            field.placeholderString = placeholder
            field.font = .systemFont(ofSize: 12)
            field.delegate = self
            field.toolTip = label
            let title = NSTextField(labelWithString: label)
            title.font = .systemFont(ofSize: 10, weight: .semibold)
            title.textColor = .secondaryLabelColor
            let row = NSStackView(views: [title, field])
            row.orientation = .vertical
            row.alignment = .leading
            row.spacing = 2
            attach(row)
            return field
        }

        func makeFlag(_ label: String, on: Bool) -> NSButton {
            let button = NSButton(checkboxWithTitle: label, target: self, action: #selector(flagChanged(_:)))
            button.state = on ? .on : .off
            button.font = .systemFont(ofSize: 11)
            attach(button)
            return button
        }

        switch step.kind.parameterSpec {
        case .none:
            let label = NSTextField(labelWithString: "No parameters.")
            label.font = .systemFont(ofSize: 11)
            label.textColor = .secondaryLabelColor
            attach(label)
        case .single(let label, let placeholder):
            parameterField = makeField(label, placeholder: placeholder, value: step.parameter, secondary: false)
        case .singleWithFlag(let label, let placeholder, let flagLabel):
            parameterField = makeField(label, placeholder: placeholder, value: step.parameter, secondary: false)
            flagButton = makeFlag(flagLabel, on: step.flag)
        case .double(let label, let secondaryLabel, let placeholder, let secondaryPlaceholder):
            parameterField = makeField(label, placeholder: placeholder, value: step.parameter, secondary: false)
            secondaryField = makeField(secondaryLabel, placeholder: secondaryPlaceholder, value: step.secondary, secondary: true)
        case .doubleWithFlag(let label, let secondaryLabel, let placeholder, let secondaryPlaceholder, let flagLabel):
            parameterField = makeField(label, placeholder: placeholder, value: step.parameter, secondary: false)
            secondaryField = makeField(secondaryLabel, placeholder: secondaryPlaceholder, value: step.secondary, secondary: true)
            flagButton = makeFlag(flagLabel, on: step.flag)
        case .flagOnly(let flagLabel):
            flagButton = makeFlag(flagLabel, on: step.flag)
        }
    }

    private var selectedStepIndex: Int? {
        let index = chainTable.selectedRow
        return chain.steps.indices.contains(index) ? index : nil
    }

    private func updateSelectedStep(_ mutate: (inout StringChainStep) -> Void) {
        guard let index = selectedStepIndex else { return }
        pushHistory()
        mutate(&chain.steps[index])
        rebuildChainTable(preservingSelection: index)
        scheduleRecompute()
    }

    // MARK: - Actions

    @objc private func addStep(_ sender: Any?) {
        guard let item = opPopup.selectedItem,
              let raw = item.representedObject as? String,
              let kind = StringOperationKind(rawValue: raw) else {
            NSSound.beep()
            return
        }
        pushHistory()
        var step = StringChainStep(kind: kind)
        step.flag = step.defaultFlag
        chain.append(step)
        rebuildChainTable(preservingSelection: chain.steps.count - 1)
        scheduleRecompute()
    }

    @objc private func removeStep(_ sender: Any?) {
        guard let index = selectedStepIndex else { return }
        pushHistory()
        chain.remove(at: index)
        rebuildChainTable(preservingSelection: nil)
        scheduleRecompute()
    }

    @objc private func moveStepUp(_ sender: Any?) {
        guard let index = selectedStepIndex, index > 0 else { return }
        pushHistory()
        chain.move(from: index, to: index - 1)
        rebuildChainTable(preservingSelection: index - 1)
        scheduleRecompute()
    }

    @objc private func moveStepDown(_ sender: Any?) {
        guard let index = selectedStepIndex, index < chain.steps.count - 1 else { return }
        pushHistory()
        chain.move(from: index, to: index + 1)
        rebuildChainTable(preservingSelection: index + 1)
        scheduleRecompute()
    }

    @objc private func flagChanged(_ sender: NSButton) {
        updateSelectedStep { $0.flag = sender.state == .on }
    }

    @objc private func copyOutput(_ sender: Any?) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(outputText.string, forType: .string)
    }

    @objc private func applyToInput(_ sender: Any?) {
        pushHistory()
        inputText.string = outputText.string
        recomputeNow()
    }

    @objc private func swapPanes(_ sender: Any?) {
        pushHistory()
        let previousInput = inputText.string
        inputText.string = outputText.string
        outputText.string = previousInput
        updateStats()
    }

    @objc private func clearAll(_ sender: Any?) {
        pushHistory()
        inputText.string = ""
        outputText.string = ""
        errorLabel.stringValue = ""
        statsLabel.stringValue = "Cleared"
    }

    @objc private func downloadOutput(_ sender: Any?) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "output.txt"
        panel.beginSheetModal(for: window!) { response in
            guard response == .OK, let url = panel.url else { return }
            try? self.outputText.string.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Undo / redo

    @objc private func undo(_ sender: Any?) {
        guard historyIndex > 0 else { return }
        historyIndex -= 1
        restoreHistoryEntry(historyIndex)
    }

    @objc private func redo(_ sender: Any?) {
        guard historyIndex >= 0, historyIndex + 1 < history.count else { return }
        historyIndex += 1
        restoreHistoryEntry(historyIndex)
    }

    private func pushHistory() {
        if historyIndex >= 0 && historyIndex < history.count - 1 {
            history.removeSubrange((historyIndex + 1)...)
        }
        history.append((inputText.string, chain))
        if history.count > 50 {
            history.removeFirst(history.count - 50)
        }
        historyIndex = history.count - 1
        updateHistoryButtons()
    }

    private func restoreHistoryEntry(_ index: Int) {
        guard history.indices.contains(index) else { return }
        let entry = history[index]
        inputText.string = entry.input
        chain = entry.chain
        rebuildChainTable(preservingSelection: nil)
        recomputeNow()
        updateHistoryButtons()
    }

    private func updateHistoryButtons() {
        undoButton.isEnabled = historyIndex > 0
        redoButton.isEnabled = historyIndex >= 0 && historyIndex + 1 < history.count
    }

    // MARK: - Live evaluation

    func textDidChange(_ notification: Notification) {
        scheduleRecompute()
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        if field === parameterField {
            updateSelectedStepWithoutHistory { $0.parameter = field.stringValue }
        } else if field === secondaryField {
            updateSelectedStepWithoutHistory { $0.secondary = field.stringValue }
        }
    }

    /// Typing in a parameter field updates the chain continuously without
    /// flooding undo history; the snapshot lands on focus loss.
    func controlTextDidEndEditing(_ obj: Notification) {
        pushHistory()
    }

    private func updateSelectedStepWithoutHistory(_ mutate: (inout StringChainStep) -> Void) {
        guard let index = selectedStepIndex else { return }
        mutate(&chain.steps[index])
        let summaryIndex = index
        chainTable.reloadData()
        if chainTable.selectedRow == -1 {
            chainTable.selectRowIndexes(IndexSet(integer: summaryIndex), byExtendingSelection: false)
        }
        scheduleRecompute()
    }

    private func scheduleRecompute() {
        recomputeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.recomputeNow()
        }
        recomputeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    /// Test hook + live path: evaluates the chain synchronously.
    func recomputeNow() {
        computeGeneration += 1
        let generation = computeGeneration
        let input = inputText.string
        let snapshot = chain
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            let result = snapshot.evaluate(input)
            DispatchQueue.main.async {
                guard let self, self.computeGeneration == generation else { return }
                switch result {
                case .success(let output):
                    self.outputText.string = output
                    self.errorLabel.stringValue = ""
                case .failure(let error):
                    self.errorLabel.stringValue = error.message
                }
                self.updateStats()
            }
        }
    }

    private func updateStats() {
        let input = inputText.string
        let output = outputText.string
        func brief(_ text: String) -> String {
            let lines = (text as NSString).components(separatedBy: "\n").count
            let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
            return "\(text.count) chars · \(words) words · \(lines) lines"
        }
        statsLabel.stringValue = "in: \(brief(input))    out: \(brief(output))"
    }

    // MARK: - Theme

    @objc private func themeChanged() { applyTheme() }

    private func applyTheme() {
        let theme = ThemeManager.shared.current
        ioDivider.applyTheme(theme)
        for tv in [inputText, outputText] {
            tv.backgroundColor = theme.isDark
                ? NSColor(calibratedRed: 0.13, green: 0.14, blue: 0.15, alpha: 1)
                : NSColor.textBackgroundColor
        }
    }

    // MARK: - Test hooks

    var inputForTesting: String {
        get { inputText.string }
        set { inputText.string = newValue }
    }

    var outputForTesting: String { outputText.string }

    var chainForTesting: StringOperationChain {
        get { chain }
        set {
            chain = newValue
            rebuildChainTable(preservingSelection: nil)
        }
    }

    var errorForTesting: String { errorLabel.stringValue }

    private func rebuildChainTable(preservingSelection: Int? = nil) {
        chainTable.reloadData()
        if let selection = preservingSelection, chain.steps.indices.contains(selection) {
            chainTable.selectRowIndexes(IndexSet(integer: selection), byExtendingSelection: false)
        } else {
            chainTable.deselectAll(nil)
        }
        rebuildParamEditor()
    }
}
