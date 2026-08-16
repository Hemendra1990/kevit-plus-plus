import AppKit
import UniformTypeIdentifiers

final class MainWindowController: NSWindowController, TabBarViewDelegate, EditorViewControllerDelegate, FindReplaceControllerDelegate, NSWindowDelegate, NSOpenSavePanelDelegate, DocumentMapViewDelegate, FunctionListViewDelegate, NSMenuItemValidation {
    let store = TabDocumentStore()
    let tabBar = TabBarView()
    private let classicToolbar = ClassicToolbarView()
    let editor = EditorViewController()
    let drawing = DrawingViewController()
    let markdownPreview = MarkdownPreviewViewController()
    let htmlPreview = HTMLPreviewViewController()
    let jsonPreview = JsonPreviewViewController()
    let editorHost = NSView()
    private let splitHost = NSView()
    private let previewDivider = MarkdownDividerView(frame: .zero)
    let markdownBar = MarkdownModeBar()
    private let exitFullscreenButton = NSButton()
    private let findReplace = FindReplaceController()
    private let statusBar = StatusBarController()
    private let documentMap = DocumentMapView()
    private let functionList = FunctionListView()
    private let contentStack = NSStackView()
    private let editorRow = NSStackView()
    private var documentMapWidth: NSLayoutConstraint!
    private var functionListWidth: NSLayoutConstraint!
    private var splitConstraints: [NSLayoutConstraint] = []
    private var previewPaneConstraint: NSLayoutConstraint?
    private var suppressEditorSync = false
    private var showDocumentMap = false
    private var showFunctionList = false
    private var markdownMode: MarkdownViewMode = .code
    private var splitOrientation: NSUserInterfaceLayoutOrientation = .horizontal
    private var previewPaneWidth: CGFloat = 440
    private var previewPaneHeight: CGFloat = 320
    private var previewIsFullscreen = false
    private var modeBeforeFullscreen: MarkdownViewMode = .split
    private var hadWindowToolbarBeforeFullscreen = false
    private var escEventMonitor: Any?
    private var pendingSplitAdjust = false
    private var markdownRenderWork: DispatchWorkItem?
    private var lastRenderedMarkdown: String?
    private var mapRefreshTimer: Timer?
    private var compareWindows: [CompareWindowController] = []
    private var ftpWindow: FTPWindowController?
    private var pluginsMenu: NSMenu?
    private var editorToolbar: EditorToolbar?
    private var fileMonitorTimer: Timer?
    private var sessionHeartbeatTimer: Timer?
    private var sessionDebounceWork: DispatchWorkItem?
    private var pendingReloadPrompt = Set<UUID>()

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = AppIdentity.displayName
        window.minSize = NSSize(width: 640, height: 400)
        window.center()
        window.isReleasedWhenClosed = false
        self.init(window: window)
        window.delegate = self
        setupToolbar()
        setupUI()
        // Tests disable autosave handling to stay hermetic — restoring the
        // developer's real session here made results machine-dependent.
        if SessionManager.automaticAutosaveEnabled, SessionManager.hasAutosave {
            do {
                let session = try SessionManager.load()
                restoreSession(session)
            } catch {
                // Never block launch on a bad session — quarantine it and start fresh.
                let quarantined = SessionManager.quarantineCorruptAutosave()
                let alert = NSAlert()
                alert.messageText = "Saved session could not be restored"
                alert.informativeText = quarantined.map { "The saved session file was unreadable and has been moved to:\n\($0)" }
                    ?? "The saved session file was unreadable and could not be moved."
                alert.runModal()
                newDocument()
            }
        } else {
            newDocument()
        }
        registerNotifications()
    }

    private func setupUI() {
        guard let window else { return }

        tabBar.delegate = self
        tabBar.translatesAutoresizingMaskIntoConstraints = false

        classicToolbar.target = self
        classicToolbar.translatesAutoresizingMaskIntoConstraints = false
        classicToolbar.rebuild()

        editor.delegate = self
        editor.view.translatesAutoresizingMaskIntoConstraints = false
        drawing.onSceneChanged = { [weak self] json in
            guard let self, let doc = self.store.activeDocument, doc.kind == .drawing else { return }
            if doc.text != json {
                doc.text = json
                doc.isDirty = true
                self.reloadTabs()
                self.updateWindowTitle()
                self.scheduleSessionAutosave()
            }
        }

        editorHost.translatesAutoresizingMaskIntoConstraints = false
        editorHost.addSubview(editor.view)
        // Text editor and drawing canvas overlap in editorHost; only one is ever unhidden.
        drawing.view.translatesAutoresizingMaskIntoConstraints = false
        drawing.view.isHidden = true
        editorHost.addSubview(drawing.view)
        NSLayoutConstraint.activate([
            editor.view.leadingAnchor.constraint(equalTo: editorHost.leadingAnchor),
            editor.view.trailingAnchor.constraint(equalTo: editorHost.trailingAnchor),
            editor.view.topAnchor.constraint(equalTo: editorHost.topAnchor),
            editor.view.bottomAnchor.constraint(equalTo: editorHost.bottomAnchor),
            drawing.view.leadingAnchor.constraint(equalTo: editorHost.leadingAnchor),
            drawing.view.trailingAnchor.constraint(equalTo: editorHost.trailingAnchor),
            drawing.view.topAnchor.constraint(equalTo: editorHost.topAnchor),
            drawing.view.bottomAnchor.constraint(equalTo: editorHost.bottomAnchor)
        ])

        findReplace.delegate = self
        documentMap.delegate = self
        functionList.delegate = self
        documentMap.translatesAutoresizingMaskIntoConstraints = false
        functionList.translatesAutoresizingMaskIntoConstraints = false

        // Editor + document previews (Markdown / HTML / JSON) live in
        // splitHost; the mode layout below rebuilds its constraints for
        // code / split / preview arrangements.
        splitHost.translatesAutoresizingMaskIntoConstraints = false
        markdownPreview.view.translatesAutoresizingMaskIntoConstraints = false
        htmlPreview.view.translatesAutoresizingMaskIntoConstraints = false
        jsonPreview.view.translatesAutoresizingMaskIntoConstraints = false
        previewDivider.translatesAutoresizingMaskIntoConstraints = false
        splitHost.addSubview(editorHost)
        splitHost.addSubview(previewDivider)
        splitHost.addSubview(markdownPreview.view)
        splitHost.addSubview(htmlPreview.view)
        splitHost.addSubview(jsonPreview.view)
        htmlPreview.view.isHidden = true
        jsonPreview.view.isHidden = true
        previewDivider.onDrag = { [weak self] delta in
            self?.adjustPreviewPane(by: delta)
        }

        // Floating exit control, only visible in fullscreen preview. Sits on
        // splitHost so it floats above whichever preview is active.
        exitFullscreenButton.bezelStyle = .circular
        exitFullscreenButton.isBordered = true
        exitFullscreenButton.toolTip = "Exit Fullscreen Preview (Esc or ⌥⌘F)"
        exitFullscreenButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Exit Fullscreen Preview")
        exitFullscreenButton.imagePosition = .imageOnly
        exitFullscreenButton.target = self
        exitFullscreenButton.action = #selector(exitFullscreenPreview(_:))
        exitFullscreenButton.translatesAutoresizingMaskIntoConstraints = false
        exitFullscreenButton.isHidden = true
        splitHost.addSubview(exitFullscreenButton)
        NSLayoutConstraint.activate([
            exitFullscreenButton.trailingAnchor.constraint(equalTo: splitHost.trailingAnchor, constant: -14),
            exitFullscreenButton.topAnchor.constraint(equalTo: splitHost.topAnchor, constant: 14)
        ])

        markdownBar.translatesAutoresizingMaskIntoConstraints = false
        markdownBar.onModeChange = { [weak self] mode in
            self?.setMarkdownMode(mode)
        }
        markdownBar.onToggleFullscreen = { [weak self] in
            self?.toggleFullscreenPreview(nil)
        }

        editorRow.orientation = .horizontal
        editorRow.spacing = 0
        editorRow.distribution = .fill
        editorRow.translatesAutoresizingMaskIntoConstraints = false
        editorRow.addArrangedSubview(functionList)
        editorRow.addArrangedSubview(splitHost)
        editorRow.addArrangedSubview(documentMap)

        functionListWidth = functionList.widthAnchor.constraint(equalToConstant: 0)
        documentMapWidth = documentMap.widthAnchor.constraint(equalToConstant: 0)
        functionListWidth.isActive = true
        documentMapWidth.isActive = true
        functionList.isHidden = true
        documentMap.isHidden = true
        previewDivider.isHidden = true
        markdownPreview.view.isHidden = true

        contentStack.orientation = .vertical
        contentStack.spacing = 0
        contentStack.distribution = .fill
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(classicToolbar)
        contentStack.addArrangedSubview(tabBar)
        contentStack.addArrangedSubview(markdownBar)
        contentStack.addArrangedSubview(editorRow)
        contentStack.addArrangedSubview(findReplace.view)
        contentStack.addArrangedSubview(statusBar.view)

        // Keep chrome rows from collapsing under Auto Layout compression.
        classicToolbar.setContentHuggingPriority(.required, for: .vertical)
        classicToolbar.setContentCompressionResistancePriority(.required, for: .vertical)
        tabBar.setContentHuggingPriority(.required, for: .vertical)
        tabBar.setContentCompressionResistancePriority(.required, for: .vertical)
        tabBar.heightAnchor.constraint(equalToConstant: 30).isActive = true
        markdownBar.setContentHuggingPriority(.required, for: .vertical)
        markdownBar.setContentCompressionResistancePriority(.required, for: .vertical)
        markdownBar.isHidden = true

        applyMarkdownLayout()

        let root = FileDropView()
        root.wantsLayer = false
        editorHost.wantsLayer = false
        root.translatesAutoresizingMaskIntoConstraints = false
        root.onDropURLs = { [weak self] urls in
            for url in urls {
                self?.openFile(at: url)
            }
        }
        root.addSubview(contentStack)
        window.contentView = root
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor),
            root.topAnchor.constraint(equalTo: window.contentView!.topAnchor),
            root.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor),

            contentStack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: root.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])
        applyTheme()
        reloadTabs()

        mapRefreshTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.refreshSidePanels()
        }
        fileMonitorTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkExternalFileChanges()
        }
        sessionHeartbeatTimer = Timer.scheduledTimer(withTimeInterval: SessionManager.heartbeatInterval, repeats: true) { [weak self] _ in
            self?.autosaveSession()
        }
    }

    private func setupToolbar() {
        guard let window else { return }
        let toolbar = EditorToolbar(target: self)
        editorToolbar = toolbar
        if Preferences.shared.showToolbar {
            window.toolbar = toolbar.makeToolbar()
        }
    }

    private func registerNotifications() {
        NotificationCenter.default.addObserver(self, selector: #selector(prefsChanged), name: .preferencesDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(themeChanged), name: .themeDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(windowDidBecomeKey), name: NSWindow.didBecomeKeyNotification, object: window)
        NotificationCenter.default.addObserver(self, selector: #selector(splitWindowDidResize(_:)), name: NSWindow.didResizeNotification, object: window)
    }

    /// Narrow windows stack editor and preview vertically instead of side by side.
    /// During live window dragging this notification is delivered *inside* the
    /// display-cycle layout pass; mutating constraints synchronously here threw
    /// NSInternalInconsistencyException and crashed the app. All work is
    /// coalesced onto the next runloop turn instead.
    @objc private func splitWindowDidResize(_ notification: Notification) {
        guard markdownMode == .split, !previewIsFullscreen else { return }
        guard !pendingSplitAdjust else { return }
        pendingSplitAdjust = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pendingSplitAdjust = false
            guard self.markdownMode == .split, !self.previewIsFullscreen else { return }
            let target = self.currentSplitOrientation()
            if target != self.splitOrientation {
                self.splitOrientation = target
                self.previewDivider.orientation = target
                self.applyMarkdownLayout()
            }
            self.clampPreviewPaneToBounds()
        }
    }

    @objc private func windowDidBecomeKey() {
        checkExternalFileChanges()
    }

    @objc private func prefsChanged() {
        editor.applyFontAndTheme()
        window?.toolbar = Preferences.shared.showToolbar ? editorToolbar?.makeToolbar() : nil
        updateStatus()
    }

    @objc private func themeChanged() {
        applyTheme()
    }

    func applyTheme() {
        let theme = ThemeManager.shared.current
        window?.appearance = NSAppearance(named: theme.isDark ? .darkAqua : .aqua)
        window?.backgroundColor = theme.chromeBackground
        tabBar.applyTheme(theme)
        classicToolbar.applyTheme(theme)
        findReplace.applyTheme(theme)
        statusBar.applyTheme(theme)
        documentMap.applyTheme(theme)
        functionList.applyTheme(theme)
        markdownBar.applyTheme(theme)
        previewDivider.applyTheme(theme)
        markdownPreview.applyChromeTheme()
        jsonPreview.applyChromeTheme()
        editor.applyFontAndTheme()
        drawing.applyChromeTheme()
        if store.activeDocument?.kind != .drawing {
            suppressEditorSync = true
            editor.rebuildEditor(languageID: editor.currentLanguageID)
            suppressEditorSync = false
        }
        reloadTabs()
    }

    // MARK: - Documents

    @objc func newDocument(_ sender: Any? = nil) {
        syncActiveDocumentFromEditor()
        let doc = Document.newUntitled()
        store.add(doc)
        presentActiveDocument()
    }

    @objc func newDrawing(_ sender: Any? = nil) {
        syncActiveDocumentFromEditor()
        let doc = Document.newUntitledDrawing()
        store.add(doc)
        presentActiveDocument()
    }

    @objc func openDocument(_ sender: Any? = nil) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.item]
        panel.beginSheetModal(for: window!) { [weak self] response in
            guard response == .OK else { return }
            for url in panel.urls {
                self?.openFile(at: url)
            }
        }
    }

    func openFile(at url: URL) {
        if let existing = store.documents.firstIndex(where: { $0.fileURL == url }) {
            store.setActiveIndex(existing)
            presentActiveDocument()
            return
        }
        do {
            syncActiveDocumentFromEditor()
            let doc = try Document.open(url: url)
            doc.noteOpenedOnDisk()
            store.add(doc)
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
            presentActiveDocument()
        } catch {
            showError(error)
        }
    }

    @objc func openRecentDocument(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        openFile(at: url)
    }

    @objc func saveAllDocuments(_ sender: Any? = nil) {
        syncActiveDocumentFromEditor()
        let active = store.activeIndex
        for (idx, doc) in store.documents.enumerated() {
            store.setActiveIndex(idx)
            if doc.fileURL == nil {
                // Skip untitled without prompting for each — only save those with paths
                continue
            }
            do {
                try doc.save()
            } catch {
                showError(error)
            }
        }
        store.setActiveIndex(active)
        presentActiveDocument()
    }

    @objc func saveDocument(_ sender: Any? = nil) {
        syncActiveDocumentFromEditor()
        guard let doc = store.activeDocument else { return }
        if doc.fileURL == nil {
            saveDocumentAs(sender)
            return
        }
        do {
            try doc.save()
            if doc.kind != .drawing {
                suppressEditorSync = true
                editor.string = doc.text
                suppressEditorSync = false
            }
            reloadTabs()
            updateStatus()
            autosaveSession()
        } catch {
            showError(error)
        }
    }

    @objc func saveDocumentAs(_ sender: Any? = nil) {
        syncActiveDocumentFromEditor()
        guard let doc = store.activeDocument else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [doc.contentType]
        panel.nameFieldStringValue = Self.savePanelName(for: doc)
        panel.beginSheetModal(for: window!) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try doc.save(to: url)
                if doc.kind != .drawing {
                    self?.suppressEditorSync = true
                    self?.editor.string = doc.text
                    self?.suppressEditorSync = false
                }
                self?.reloadTabs()
                self?.updateStatus()
                self?.updateWindowTitle()
                self?.autosaveSession()
            } catch {
                self?.showError(error)
            }
        }
    }

    @objc func closeDocument(_ sender: Any? = nil) {
        guard store.activeIndex >= 0 else { return }
        closeTab(at: store.activeIndex)
    }

    private func closeTab(at index: Int) {
        syncActiveDocumentFromEditor()
        guard store.documents.indices.contains(index) else { return }
        let doc = store.documents[index]
        if doc.isDirty {
            let alert = NSAlert()
            alert.messageText = "Do you want to save the changes you made to \"\(doc.plainDisplayName)\"?"
            alert.informativeText = "Your changes will be lost if you don't save them."
            alert.addButton(withTitle: "Save")
            alert.addButton(withTitle: "Don't Save")
            alert.addButton(withTitle: "Cancel")
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                store.setActiveIndex(index)
                presentActiveDocument()
                saveDocument(nil)
                if doc.isDirty { return }
            } else if response == .alertThirdButtonReturn {
                return
            }
        }
        _ = store.close(at: index)
        if store.isEmpty {
            newDocument()
        } else {
            presentActiveDocument()
        }
        autosaveSession()
    }

    // MARK: - Window / quit

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        autosaveSession()
        return true
    }

    /// Kept for tab-close flows that still prompt. Quit uses the session snapshot instead.
    func confirmDiscardChangesIfNeeded(allowCancel: Bool) -> Bool {
        syncActiveDocumentFromEditor()
        var discard: [Document] = []
        for doc in store.documents where doc.isDirty {
            let alert = NSAlert()
            alert.messageText = "Do you want to save the changes you made to \"\(doc.plainDisplayName)\"?"
            alert.informativeText = "Your changes will be lost if you don't save them."
            alert.addButton(withTitle: "Save")
            alert.addButton(withTitle: "Don't Save")
            if allowCancel {
                alert.addButton(withTitle: "Cancel")
            }
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                if doc.fileURL == nil {
                    guard let url = runSaveAsPanel(for: doc) else { return false }
                    do {
                        try doc.save(to: url)
                    } catch {
                        showError(error)
                        return false
                    }
                } else {
                    do {
                        try doc.save()
                    } catch {
                        showError(error)
                        return false
                    }
                }
            } else if allowCancel, response == .alertThirdButtonReturn {
                return false
            } else {
                discard.append(doc)
            }
        }
        for doc in discard {
            doc.text = ""
            doc.isDirty = false
        }
        return true
    }

    private func runSaveAsPanel(for doc: Document) -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [doc.contentType]
        panel.nameFieldStringValue = Self.savePanelName(for: doc)
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url
    }

    private static func savePanelName(for doc: Document) -> String {
        if doc.fileURL == nil, doc.kind == .drawing {
            return "Untitled.excalidraw"
        }
        return doc.plainDisplayName
    }

    func presentActiveDocument() {
        guard let doc = store.activeDocument else { return }
        if doc.kind == .drawing {
            editor.view.isHidden = true
            drawing.view.isHidden = false
            window?.contentView?.layoutSubtreeIfNeeded()
            drawing.loadScene(doc.text)
            drawing.notifyVisible()
            functionList.isHidden = true
            documentMap.isHidden = true
            functionListWidth.constant = 0
            documentMapWidth.constant = 0
            updateMarkdownChrome()
            reloadTabs()
            updateWindowTitle()
            updateStatus()
            drawing.webView.window?.makeFirstResponder(drawing.webView)
            return
        }
        drawing.view.isHidden = true
        editor.view.isHidden = false
        functionList.isHidden = !showFunctionList
        documentMap.isHidden = !showDocumentMap
        functionListWidth.constant = showFunctionList ? 200 : 0
        documentMapWidth.constant = showDocumentMap ? 96 : 0
        updateMarkdownChrome()
        suppressEditorSync = true
        editor.rebuildEditor(languageID: doc.languageID)
        editor.string = doc.text
        suppressEditorSync = false
        reloadTabs()
        updateWindowTitle()
        updateStatus()
        refreshSidePanels()
        if previewIsFullscreen || markdownMode != .code {
            window?.makeFirstResponder(markdownMode == .preview || previewIsFullscreen ? (activePreviewFirstResponder() ?? editor.textView) : editor.textView)
        } else {
            window?.makeFirstResponder(editor.textView)
        }
    }

    private func syncActiveDocumentFromEditor() {
        guard !suppressEditorSync, let doc = store.activeDocument else { return }
        if doc.kind == .drawing {
            drawing.flushPendingChanges()
            if drawing.lastSceneJSON != doc.text {
                doc.text = drawing.lastSceneJSON
                doc.isDirty = true
            }
            return
        }
        let text = editor.string
        if doc.text != text {
            doc.text = text
            doc.isDirty = true
        }
    }

    private func reloadTabs() {
        let titles = store.documents.map(\.displayName)
        tabBar.reload(titles: titles, selectedIndex: store.activeIndex)
    }

    private func updateWindowTitle() {
        window?.title = store.activeDocument.map { "\($0.plainDisplayName) — \(AppIdentity.displayName)" } ?? AppIdentity.displayName
    }

    private func updateStatus() {
        guard let doc = store.activeDocument else { return }
        if doc.kind == .drawing {
            let fileSize: Int64? = {
                guard let path = doc.fileURL?.path else { return nil }
                return (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int64
            }()
            statusBar.update(
                line: 1,
                column: 1,
                position: 0,
                length: (doc.text as NSString).length,
                encoding: .utf8,
                eol: .lf,
                language: "Drawing",
                columnMode: false,
                recording: MacroRecorder.shared.isRecording,
                bookmarkCount: 0,
                charInfo: "",
                zoom: 100,
                selectionLength: 0,
                fileSize: fileSize
            )
            return
        }
        let metrics = editor.caretMetrics()
        let charInfo: String
        if let info = TextTransforms.characterInfo(at: metrics.position, in: editor.string) {
            let escaped = info.char.replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\t", with: "\\t")
            charInfo = "'\(escaped)'  \(info.hex)  (\(info.code))"
        } else {
            charInfo = ""
        }
        let fileSize: Int64? = {
            guard let path = doc.fileURL?.path else { return nil }
            return (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int64
        }()
        statusBar.update(
            line: metrics.line,
            column: metrics.column,
            position: metrics.position,
            length: (editor.string as NSString).length,
            encoding: doc.encoding,
            eol: doc.eol,
            language: LanguageRegistry.shared.displayName(for: doc.languageID),
            columnMode: editor.columnModeEnabled,
            recording: MacroRecorder.shared.isRecording,
            bookmarkCount: doc.bookmarks.count,
            charInfo: charInfo,
            zoom: Int(round(editor.zoomFactor * 100)),
            selectionLength: editor.selectedRange.length,
            fileSize: fileSize
        )
    }

    private func refreshSidePanels() {
        guard store.activeDocument?.kind != .drawing else { return }
        if showDocumentMap {
            documentMap.update(
                text: editor.string,
                visibleLines: editor.visibleLineRange(),
                bookmarks: store.activeDocument?.bookmarks ?? []
            )
        }
        if showFunctionList {
            functionList.reload(text: editor.string)
        }
    }

    private func showError(_ error: Error) {
        let alert = NSAlert(error: error)
        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    // MARK: - TabBar

    func tabBar(_ tabBar: TabBarView, didSelect index: Int) {
        syncActiveDocumentFromEditor()
        store.setActiveIndex(index)
        presentActiveDocument()
    }

    func tabBar(_ tabBar: TabBarView, didClose index: Int) {
        closeTab(at: index)
    }

    func tabBar(_ tabBar: TabBarView, didReorder from: Int, to: Int) {
        store.moveTab(from: from, to: to)
        reloadTabs()
    }

    func tabBarDidRequestNewTab(_ tabBar: TabBarView) {
        newDocument(nil)
    }

    func tabBar(_ tabBar: TabBarView, perform action: TabBarAction, at index: Int) {
        performTabAction(action, at: index)
    }

    @objc func closeOtherTabs(_ sender: Any? = nil) {
        performTabAction(.closeOthers, at: store.activeIndex)
    }

    @objc func closeAllTabs(_ sender: Any? = nil) {
        performTabAction(.closeAll, at: store.activeIndex)
    }

    @objc func closeTabsToLeft(_ sender: Any? = nil) {
        performTabAction(.closeLeft, at: store.activeIndex)
    }

    @objc func closeTabsToRight(_ sender: Any? = nil) {
        performTabAction(.closeRight, at: store.activeIndex)
    }

    @objc func moveTabToStart(_ sender: Any? = nil) {
        performTabAction(.moveToStart, at: store.activeIndex)
    }

    @objc func moveTabToEnd(_ sender: Any? = nil) {
        performTabAction(.moveToEnd, at: store.activeIndex)
    }

    @objc func moveTabLeft(_ sender: Any? = nil) {
        performTabAction(.moveLeft, at: store.activeIndex)
    }

    @objc func moveTabRight(_ sender: Any? = nil) {
        performTabAction(.moveRight, at: store.activeIndex)
    }

    @objc func cloneTab(_ sender: Any? = nil) {
        performTabAction(.clone, at: store.activeIndex)
    }

    @objc func copyFilePath(_ sender: Any? = nil) {
        performTabAction(.copyPath, at: store.activeIndex)
    }

    @objc func copyFilename(_ sender: Any? = nil) {
        performTabAction(.copyFilename, at: store.activeIndex)
    }

    @objc func openContainingFolder(_ sender: Any? = nil) {
        performTabAction(.openContainingFolder, at: store.activeIndex)
    }

    private func performTabAction(_ action: TabBarAction, at index: Int) {
        guard store.documents.indices.contains(index) || action == .closeAll else { return }
        syncActiveDocumentFromEditor()

        switch action {
        case .close:
            closeTab(at: index)

        case .closeOthers:
            guard store.documents.indices.contains(index) else { return }
            let keepID = store.documents[index].id
            while store.documents.count > 1 {
                guard let keepIdx = store.documents.firstIndex(where: { $0.id == keepID }) else { break }
                let closeIdx = keepIdx == 0 ? 1 : 0
                if !promptAndCloseIfNeeded(at: closeIdx) { break }
            }
            if let keepIdx = store.documents.firstIndex(where: { $0.id == keepID }) {
                store.setActiveIndex(keepIdx)
            }
            if store.isEmpty { newDocument() }
            else { presentActiveDocument() }

        case .closeAll:
            while !store.isEmpty {
                if !promptAndCloseIfNeeded(at: store.documents.count - 1) { break }
            }
            if store.isEmpty { newDocument() }
            else { presentActiveDocument() }

        case .closeLeft:
            guard index > 0 else { return }
            for i in (0..<index).reversed() {
                if !promptAndCloseIfNeeded(at: i) { return }
            }
            presentActiveDocument()

        case .closeRight:
            guard index + 1 < store.documents.count else { return }
            for i in ((index + 1)..<store.documents.count).reversed() {
                if !promptAndCloseIfNeeded(at: i) { return }
            }
            presentActiveDocument()

        case .moveToStart:
            store.moveTab(from: index, to: 0)
            presentActiveDocument()

        case .moveToEnd:
            store.moveTab(from: index, to: store.documents.count - 1)
            presentActiveDocument()

        case .moveLeft:
            guard index > 0 else { return }
            store.moveTab(from: index, to: index - 1)
            presentActiveDocument()

        case .moveRight:
            guard index + 1 < store.documents.count else { return }
            store.moveTab(from: index, to: index + 1)
            presentActiveDocument()

        case .clone:
            let src = store.documents[index]
            let clone = Document(
                fileURL: nil,
                text: src.text,
                encoding: src.encoding,
                eol: src.eol,
                languageID: src.languageID,
                kind: src.kind
            )
            clone.isDirty = true
            clone.bookmarks = src.bookmarks
            store.add(clone)
            presentActiveDocument()

        case .copyPath:
            let doc = store.documents[index]
            let path = doc.fileURL?.path ?? doc.plainDisplayName
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(path, forType: .string)

        case .copyFilename:
            let doc = store.documents[index]
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(doc.plainDisplayName, forType: .string)

        case .openContainingFolder:
            let doc = store.documents[index]
            guard let url = doc.fileURL else {
                NSSound.beep()
                return
            }
            NSWorkspace.shared.activateFileViewerSelecting([url])

        case .renameSaveAs:
            store.setActiveIndex(index)
            presentActiveDocument()
            saveDocumentAs(nil)

        case .reload:
            store.setActiveIndex(index)
            presentActiveDocument()
            reloadFromDisk(nil)
        }
    }

    /// Returns false if user cancelled a dirty-close prompt.
    @discardableResult
    private func promptAndCloseIfNeeded(at index: Int) -> Bool {
        guard store.documents.indices.contains(index) else { return true }
        let doc = store.documents[index]
        if doc.isDirty {
            let alert = NSAlert()
            alert.messageText = "Do you want to save the changes you made to \"\(doc.plainDisplayName)\"?"
            alert.informativeText = "Your changes will be lost if you don't save them."
            alert.addButton(withTitle: "Save")
            alert.addButton(withTitle: "Don't Save")
            alert.addButton(withTitle: "Cancel")
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                store.setActiveIndex(index)
                presentActiveDocument()
                saveDocument(nil)
                if doc.isDirty { return false }
            } else if response == .alertThirdButtonReturn {
                return false
            }
        }
        _ = store.close(at: index)
        autosaveSession()
        return true
    }

    // MARK: - Editor

    func editorDidChangeText(_ editor: EditorViewController) {
        guard !suppressEditorSync, let doc = store.activeDocument, doc.kind != .drawing else { return }
        doc.text = editor.string
        doc.isDirty = true
        reloadTabs()
        updateStatus()
        scheduleSessionAutosave()
        if showFunctionList { functionList.reload(text: editor.string) }
        if showDocumentMap {
            documentMap.update(text: editor.string, visibleLines: editor.visibleLineRange(), bookmarks: doc.bookmarks)
        }
        if previewIsFullscreen || markdownMode != .code {
            scheduleMarkdownRender()
        } else if !doc.isMarkdown {
            // Typing Markdown into a plain tab should light up the mode bar.
            scheduleMarkdownRender()
        }
    }

    func editorDidChangeSelection(_ editor: EditorViewController) {
        updateStatus()
        if showDocumentMap {
            documentMap.update(
                text: editor.string,
                visibleLines: editor.visibleLineRange(),
                bookmarks: store.activeDocument?.bookmarks ?? []
            )
        }
    }

    // MARK: - Find / Replace

    @objc func showFindPanel(_ sender: Any? = nil) {
        findReplace.show(focusReplace: false)
        if let selected = selectedText(), !selected.isEmpty {
            findReplace.setFindString(selected)
        }
    }

    @objc func showReplacePanel(_ sender: Any? = nil) {
        findReplace.show(focusReplace: true)
        if let selected = selectedText(), !selected.isEmpty {
            findReplace.setFindString(selected)
        }
    }

    @objc func findNext(_ sender: Any? = nil) {
        if !findReplace.isVisible { findReplace.show() }
        findReplaceFindNext(findReplace)
    }

    @objc func findPrevious(_ sender: Any? = nil) {
        if !findReplace.isVisible { findReplace.show() }
        findReplaceFindPrevious(findReplace)
    }

    private func selectedText() -> String? {
        let range = editor.selectedRange
        guard range.length > 0 else { return nil }
        return (editor.string as NSString).substring(with: range)
    }

    func findReplaceFindNext(_ controller: FindReplaceController) {
        performFind(forward: true)
        MacroRecorder.shared.record(.findNext)
    }

    func findReplaceFindPrevious(_ controller: FindReplaceController) {
        performFind(forward: false)
        MacroRecorder.shared.record(.findPrevious)
    }

    func findReplaceReplace(_ controller: FindReplaceController) {
        let engine = currentFindEngine()
        let text = editor.string
        let selection = editor.selectedRange
        if selection.length > 0, let selRange = Range(selection, in: text) {
            // Replace only when the selection *is* the match — a selection that merely
            // contains the term must not be clobbered.
            let selText = String(text[selRange])
            let isExactMatch: Bool
            if engine.useRegex {
                isExactMatch = engine.firstMatch(in: selText, from: 0, forward: true)
                    .map { selText[selText.startIndex..<$0.lowerBound].isEmpty && $0.upperBound >= selText.endIndex } ?? false
            } else {
                isExactMatch = selText.compare(
                    controller.findString,
                    options: controller.matchCase ? [] : .caseInsensitive
                ) == .orderedSame
            }
            if isExactMatch {
                let replacement = engine.replacementString(
                    in: selText,
                    match: selText.startIndex..<selText.endIndex,
                    template: controller.replaceString
                ) ?? controller.replaceString
                editor.replaceSelected(with: replacement)
                performFind(forward: true)
                return
            }
        }
        performFind(forward: true)
        let newSel = editor.selectedRange
        if newSel.length > 0, let r = Range(newSel, in: editor.string) {
            let replacement = engine.replacementString(
                in: editor.string,
                match: r,
                template: controller.replaceString
            ) ?? controller.replaceString
            editor.replaceSelected(with: replacement)
        }
    }

    func findReplaceReplaceAll(_ controller: FindReplaceController) {
        let engine = currentFindEngine()
        let text = editor.string
        let matches = engine.allMatches(in: text)
        guard !matches.isEmpty else {
            if engine.useRegex, let error = engine.regexError() {
                controller.setStatus("Invalid regular expression: \(error)")
            } else {
                controller.setStatus("No matches")
            }
            return
        }
        // Compute replacements against the original text first so $`/$' backreferences stay correct.
        var replacements: [(Range<String.Index>, String)] = []
        for range in matches {
            let replacement = engine.replacementString(in: text, match: range, template: controller.replaceString)
                ?? controller.replaceString
            replacements.append((range, replacement))
        }
        var result = text
        for (range, replacement) in replacements.reversed() {
            result.replaceSubrange(range, with: replacement)
        }
        editor.string = result
        if let doc = store.activeDocument {
            doc.text = result
            doc.isDirty = true
        }
        controller.setStatus("Replaced \(matches.count)")
        reloadTabs()
        updateStatus()
    }

    func findReplaceQueryDidChange(_ controller: FindReplaceController) {
        controller.setStatus("")
    }

    private func currentFindEngine() -> FindMatchEngine {
        FindMatchEngine(
            find: findReplace.findString,
            matchCase: findReplace.matchCase,
            wholeWord: findReplace.wholeWord,
            useRegex: findReplace.useRegex
        )
    }

    private func performFind(forward: Bool) {
        let engine = currentFindEngine()
        let text = editor.string
        guard !engine.find.isEmpty else {
            findReplace.setStatus("Empty search")
            return
        }

        let selection = editor.selectedRange
        let start: Int
        if forward {
            start = selection.location + selection.length
        } else {
            start = selection.location
        }

        if let match = engine.firstMatch(in: text, from: start, forward: forward) {
            select(match, in: text)
            findReplace.setStatus("")
            return
        }

        if findReplace.wrapAround {
            let wrapStart = forward ? 0 : (text as NSString).length
            if let match = engine.firstMatch(in: text, from: wrapStart, forward: forward) {
                select(match, in: text)
                findReplace.setStatus("Wrapped")
                return
            }
        }
        if engine.useRegex, let error = engine.regexError() {
            findReplace.setStatus("Invalid regular expression: \(error)")
        } else {
            findReplace.setStatus("Not found")
        }
        NSSound.beep()
    }

    private func select(_ match: Range<String.Index>, in text: String) {
        let nsRange = NSRange(match, in: text)
        editor.setSelectedRange(nsRange)
        updateStatus()
    }

    // MARK: - Encoding / EOL / Language

    @objc func changeEncoding(_ sender: NSMenuItem) {
        guard store.activeDocument?.kind != .drawing else { return }
        guard let encoding = TextEncodingKind(rawValue: sender.title),
              let doc = store.activeDocument else { return }
        syncActiveDocumentFromEditor()
        doc.encoding = encoding
        doc.isDirty = true
        reloadTabs()
        updateStatus()
    }

    @objc func changeEOL(_ sender: NSMenuItem) {
        guard store.activeDocument?.kind != .drawing else { return }
        guard let eol = EOLStyle(rawValue: sender.title),
              let doc = store.activeDocument else { return }
        syncActiveDocumentFromEditor()
        doc.eol = eol
        doc.text = EncodingDetector.normalizeEOL(doc.text, to: eol)
        suppressEditorSync = true
        editor.string = doc.text
        suppressEditorSync = false
        doc.isDirty = true
        reloadTabs()
        updateStatus()
    }

    @objc func changeLanguage(_ sender: NSMenuItem) {
        guard let doc = store.activeDocument, doc.kind != .drawing else { return }
        syncActiveDocumentFromEditor()
        doc.languageID = sender.representedObject as? String ?? "plaintext"
        doc.isLanguageForced = true
        editor.setLanguage(doc.languageID)
        updateStatus()
        // Switching an untitled document to Markdown makes it previewable.
        renderMarkdownPreview(force: true)
    }

    // MARK: - View / Settings

    @objc func toggleWordWrap(_ sender: Any? = nil) {
        Preferences.shared.wordWrap.toggle()
        editor.applyFontAndTheme()
    }

    @objc func toggleLineNumbers(_ sender: Any? = nil) {
        Preferences.shared.showLineNumbers.toggle()
        editor.applyFontAndTheme()
    }

    @objc func zoomIn(_ sender: Any? = nil) { editor.zoomIn() }
    @objc func zoomOut(_ sender: Any? = nil) { editor.zoomOut() }
    @objc func zoomReset(_ sender: Any? = nil) { editor.zoomReset() }

    @objc func useLightTheme(_ sender: Any? = nil) { ThemeManager.shared.setDark(false) }
    @objc func useDarkTheme(_ sender: Any? = nil) { ThemeManager.shared.setDark(true) }

    @objc func showPreferences(_ sender: Any? = nil) {
        PreferencesWindowController.shared.showWindow(nil)
    }

    @objc func showAbout(_ sender: Any? = nil) {
        let alert = NSAlert()
        alert.messageText = AppIdentity.displayName
        alert.informativeText = "A native macOS editor for Kevit.\nText, code, and drawings.\nVersion 1.0.0"
        alert.runModal()
    }

    @objc func goToLine(_ sender: Any? = nil) {
        let alert = NSAlert()
        alert.messageText = "Go to line"
        let field = NSTextField(string: "")
        field.frame = NSRect(x: 0, y: 0, width: 200, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "Go")
        alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn, let line = Int(field.stringValue), line > 0 else { return }
        moveCaret(toLine: line)
        MacroRecorder.shared.record(.goToLine(line))
    }

    private func moveCaret(toLine target: Int) {
        editor.goToLine(target)
        updateStatus()
    }

    // MARK: - Line ops / bookmarks / column

    @objc func duplicateLine(_ sender: Any? = nil) {
        syncActiveDocumentFromEditor()
        _ = editor.duplicateCurrentLine()
        syncActiveDocumentFromEditor()
        reloadTabs()
        updateStatus()
    }

    @objc func moveLineUp(_ sender: Any? = nil) {
        syncActiveDocumentFromEditor()
        _ = editor.moveCurrentLine(down: false)
        syncActiveDocumentFromEditor()
        reloadTabs()
        updateStatus()
    }

    @objc func moveLineDown(_ sender: Any? = nil) {
        syncActiveDocumentFromEditor()
        _ = editor.moveCurrentLine(down: true)
        syncActiveDocumentFromEditor()
        reloadTabs()
        updateStatus()
    }

    @objc func toggleBookmark(_ sender: Any? = nil) {
        guard let doc = store.activeDocument else { return }
        let line = editor.caretMetrics().line
        doc.toggleBookmark(atLine: line)
        MacroRecorder.shared.record(.toggleBookmark)
        refreshSidePanels()
        updateStatus()
    }

    @objc func nextBookmark(_ sender: Any? = nil) {
        guard let doc = store.activeDocument,
              let line = doc.nextBookmark(after: editor.caretMetrics().line) else {
            NSSound.beep()
            return
        }
        moveCaret(toLine: line)
    }

    @objc func previousBookmark(_ sender: Any? = nil) {
        guard let doc = store.activeDocument,
              let line = doc.previousBookmark(before: editor.caretMetrics().line) else {
            NSSound.beep()
            return
        }
        moveCaret(toLine: line)
    }

    @objc func clearBookmarks(_ sender: Any? = nil) {
        store.activeDocument?.bookmarks.removeAll()
        refreshSidePanels()
        updateStatus()
    }

    @objc func toggleColumnMode(_ sender: Any? = nil) {
        editor.columnModeEnabled.toggle()
        updateStatus()
    }

    @objc func columnDelete(_ sender: Any? = nil) {
        guard editor.columnModeEnabled else { return }
        syncActiveDocumentFromEditor()
        editor.deleteColumnSelection()
        syncActiveDocumentFromEditor()
        reloadTabs()
        updateStatus()
    }

    @objc func columnCopy(_ sender: Any? = nil) {
        guard editor.columnModeEnabled else { return }
        let text = editor.copyColumnSelection()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc func columnPaste(_ sender: Any? = nil) {
        guard editor.columnModeEnabled,
              let text = NSPasteboard.general.string(forType: .string) else { return }
        syncActiveDocumentFromEditor()
        // Paste each line into successive rows at start column
        let box = editor.currentColumnSelection().ordered
        var result = editor.string
        let lines = text.components(separatedBy: CharacterSet.newlines)
        for (idx, chunk) in lines.enumerated() {
            let line = box.startLine + idx
            if line > TextGeometry.lineCount(of: result) { break }
            var sel = box
            sel.startLine = line
            sel.endLine = line
            result = ColumnEdit.insert(chunk, selection: sel, in: result)
        }
        editor.applyText(result, selection: editor.selectedRange)
        syncActiveDocumentFromEditor()
        reloadTabs()
        updateStatus()
    }

    // MARK: - Panels

    @objc func toggleDocumentMap(_ sender: Any? = nil) {
        guard store.activeDocument?.kind != .drawing else { return }
        showDocumentMap.toggle()
        documentMap.isHidden = !showDocumentMap
        documentMapWidth.constant = showDocumentMap ? 96 : 0
        refreshSidePanels()
    }

    @objc func toggleFunctionList(_ sender: Any? = nil) {
        guard store.activeDocument?.kind != .drawing else { return }
        showFunctionList.toggle()
        functionList.isHidden = !showFunctionList
        functionListWidth.constant = showFunctionList ? 200 : 0
        refreshSidePanels()
    }

    // MARK: - Document previews (Markdown / HTML / JSON)

    /// Which viewer the preview pane hosts for a document.
    enum PreviewKind: Equatable {
        case none
        case markdown
        case html
        case json
    }

    private func previewKind(for doc: Document) -> PreviewKind {
        guard doc.kind != .drawing else { return .none }
        if doc.isMarkdown || MarkdownDetector.looksLikeMarkdown(doc.text) {
            return .markdown
        }
        if doc.isJSONDocument || doc.looksLikeJSONContent {
            return .json
        }
        if doc.isHTMLDocument || doc.looksLikeHTMLContent {
            return .html
        }
        return .none
    }

    /// True when the document may be rendered in the preview pane.
    private func isPreviewable(_ doc: Document) -> Bool {
        previewKind(for: doc) != .none
    }

    /// The pane view laid out on the preview side of the split.
    private var activePreviewView: NSView {
        guard let doc = store.activeDocument else { return markdownPreview.view }
        switch previewKind(for: doc) {
        case .html: return htmlPreview.view
        case .json: return jsonPreview.view
        default: return markdownPreview.view
        }
    }

    private func renderIntoActivePreview(_ doc: Document) {
        switch previewKind(for: doc) {
        case .markdown:
            markdownPreview.loadMarkdown(doc.text)
        case .html:
            htmlPreview.loadHTML(doc.text)
        case .json:
            jsonPreview.loadJSON(doc.text)
        case .none:
            break
        }
    }

    private func notifyActivePreview() {
        guard let doc = store.activeDocument else { return }
        switch previewKind(for: doc) {
        case .markdown: markdownPreview.notifyVisible()
        case .html: htmlPreview.notifyVisible()
        case .json: jsonPreview.notifyVisible()
        case .none: break
        }
    }

    private func activePreviewFirstResponder() -> NSResponder? {
        guard let doc = store.activeDocument else { return nil }
        switch previewKind(for: doc) {
        case .html: return htmlPreview.webView
        case .json: return jsonPreview.webView
        default: return markdownPreview.webView
        }
    }

    private func previewBadge(for doc: Document) -> (label: String, confirmed: Bool)? {
        switch previewKind(for: doc) {
        case .markdown:
            return ("Markdown", doc.isMarkdown)
        case .html:
            return ("HTML", doc.isHTMLDocument)
        case .json:
            return ("JSON", doc.isJSONDocument)
        case .none:
            return nil
        }
    }

    /// Whether Markdown UI (mode bar, preview menu items) should light up.
    private var markdownUIEnabled: Bool {
        previewIsFullscreen || markdownMode != .code
            || (store.activeDocument.map { isPreviewable($0) } ?? false)
    }

    @objc func setMarkdownModeCommand(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = MarkdownViewMode(rawValue: raw) else { return }
        setMarkdownMode(mode)
    }

    func setMarkdownMode(_ mode: MarkdownViewMode) {
        guard markdownUIEnabled else { return }
        if previewIsFullscreen {
            if mode == .code || mode == .preview {
                // Fullscreen *is* preview-only; Code exits it entirely.
                if mode == .code {
                    markdownMode = .code
                    exitFullscreenState()
                    applyMarkdownChrome()
                    window?.makeFirstResponder(editor.textView)
                    return
                }
            }
        }
        markdownMode = mode
        markdownBar.setMode(mode)
        applyMarkdownLayout()
        if mode != .code {
            renderMarkdownPreview(force: true)
            notifyActivePreview()
            window?.makeFirstResponder(activePreviewFirstResponder() ?? editor.textView)
        } else {
            window?.makeFirstResponder(editor.textView)
        }
    }

    /// ⇧⌘V — keeps the classic toggle feel: Code ↔ Split.
    @objc func toggleMarkdownPreview(_ sender: Any? = nil) {
        guard markdownUIEnabled else { return }
        if previewIsFullscreen {
            exitFullscreenPreview(nil)
            return
        }
        setMarkdownMode(markdownMode == .split ? .code : .split)
    }

    @objc func toggleFullscreenPreview(_ sender: Any? = nil) {
        guard markdownUIEnabled else { return }
        if previewIsFullscreen {
            exitFullscreenPreview(nil)
        } else {
            enterFullscreenPreview()
        }
    }

    @objc func exitFullscreenPreview(_ sender: Any? = nil) {
        guard previewIsFullscreen else { return }
        markdownMode = modeBeforeFullscreen == .code ? .split : modeBeforeFullscreen
        exitFullscreenState()
        applyMarkdownChrome()
        renderMarkdownPreview(force: true)
        notifyActivePreview()
        window?.makeFirstResponder(markdownPreviewModeFirstResponder())
    }

    private func markdownPreviewModeFirstResponder() -> NSResponder? {
        markdownMode == .code ? editor.textView : (activePreviewFirstResponder() ?? editor.textView)
    }

    private func enterFullscreenPreview() {
        modeBeforeFullscreen = markdownMode == .code ? .split : markdownMode
        markdownMode = .preview
        previewIsFullscreen = true
        markdownBar.setFullscreen(true)
        installEscMonitor()
        hadWindowToolbarBeforeFullscreen = window?.toolbar != nil
        window?.toolbar = nil
        applyMarkdownChrome()
        renderMarkdownPreview(force: true)
        notifyActivePreview()
        window?.makeFirstResponder(activePreviewFirstResponder() ?? editor.textView)
    }

    private func exitFullscreenState() {
        previewIsFullscreen = false
        markdownBar.setFullscreen(false)
        removeEscMonitor()
        if hadWindowToolbarBeforeFullscreen, window?.toolbar == nil {
            window?.toolbar = editorToolbar?.makeToolbar()
        }
        hadWindowToolbarBeforeFullscreen = false
    }

    /// Esc while fullscreen preview is active exits it.
    private func installEscMonitor() {
        guard escEventMonitor == nil else { return }
        escEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53, let self, self.previewIsFullscreen {
                self.exitFullscreenPreview(nil)
                return nil
            }
            return event
        }
    }

    private func removeEscMonitor() {
        if let monitor = escEventMonitor {
            NSEvent.removeMonitor(monitor)
            escEventMonitor = nil
        }
    }

    /// Mode bar visibility + detection badge (cheap enough for every switch).
    private func updateMarkdownChrome() {
        applyMarkdownChrome()
        renderMarkdownPreview(force: true)
        if previewIsFullscreen || markdownMode != .code {
            markdownPreview.notifyVisible()
        }
    }

    private func applyMarkdownChrome() {
        let doc = store.activeDocument
        let previewable = doc.map { isPreviewable($0) } ?? false
        markdownBar.isHidden = !(previewable && !previewIsFullscreen)
        markdownBar.setMode(markdownMode)
        if let doc, let badge = previewBadge(for: doc) {
            markdownBar.setBadge(kind: badge.label, confirmed: badge.confirmed)
        }
        applyMarkdownLayout()
    }

    /// The single place that decides which of editor / divider / preview is
    /// visible and rebuilds splitHost's constraints to match. Hidden views
    /// keep their constraints in a plain NSView, so the constraint set must
    /// be rebuilt rather than just toggling `isHidden`.
    private func applyMarkdownLayout() {
        NSLayoutConstraint.deactivate(splitConstraints)
        splitConstraints = []
        previewPaneConstraint = nil

        let drawingDoc = store.activeDocument?.kind == .drawing
        let editorVisible = drawingDoc || (!previewIsFullscreen && markdownMode != .preview)
        let previewVisible = !drawingDoc && (previewIsFullscreen || markdownMode != .code)
        let splitVisible = !drawingDoc && !previewIsFullscreen && markdownMode == .split

        let pane = activePreviewView
        editorHost.isHidden = !editorVisible
        previewDivider.isHidden = !splitVisible
        markdownPreview.view.isHidden = !previewVisible || pane !== markdownPreview.view
        htmlPreview.view.isHidden = !previewVisible || pane !== htmlPreview.view
        jsonPreview.view.isHidden = !previewVisible || pane !== jsonPreview.view
        exitFullscreenButton.isHidden = !previewIsFullscreen

        if splitVisible {
            splitOrientation = currentSplitOrientation()
            previewDivider.orientation = splitOrientation
            switch splitOrientation {
            case .horizontal:
                let paneSize = pane.widthAnchor.constraint(equalToConstant: previewPaneWidth)
                paneSize.priority = .defaultHigh
                previewPaneConstraint = paneSize
                splitConstraints = [
                    editorHost.leadingAnchor.constraint(equalTo: splitHost.leadingAnchor),
                    editorHost.topAnchor.constraint(equalTo: splitHost.topAnchor),
                    editorHost.bottomAnchor.constraint(equalTo: splitHost.bottomAnchor),
                    editorHost.trailingAnchor.constraint(equalTo: previewDivider.leadingAnchor),
                    previewDivider.widthAnchor.constraint(equalToConstant: 6),
                    previewDivider.topAnchor.constraint(equalTo: splitHost.topAnchor),
                    previewDivider.bottomAnchor.constraint(equalTo: splitHost.bottomAnchor),
                    previewDivider.trailingAnchor.constraint(equalTo: pane.leadingAnchor),
                    pane.trailingAnchor.constraint(equalTo: splitHost.trailingAnchor),
                    pane.topAnchor.constraint(equalTo: splitHost.topAnchor),
                    pane.bottomAnchor.constraint(equalTo: splitHost.bottomAnchor),
                    paneSize
                ]
            case .vertical:
                let paneSize = pane.heightAnchor.constraint(equalToConstant: previewPaneHeight)
                paneSize.priority = .defaultHigh
                previewPaneConstraint = paneSize
                splitConstraints = [
                    editorHost.leadingAnchor.constraint(equalTo: splitHost.leadingAnchor),
                    editorHost.trailingAnchor.constraint(equalTo: splitHost.trailingAnchor),
                    editorHost.topAnchor.constraint(equalTo: splitHost.topAnchor),
                    editorHost.bottomAnchor.constraint(equalTo: previewDivider.topAnchor),
                    previewDivider.heightAnchor.constraint(equalToConstant: 6),
                    previewDivider.leadingAnchor.constraint(equalTo: splitHost.leadingAnchor),
                    previewDivider.trailingAnchor.constraint(equalTo: splitHost.trailingAnchor),
                    previewDivider.bottomAnchor.constraint(equalTo: pane.topAnchor),
                    pane.leadingAnchor.constraint(equalTo: splitHost.leadingAnchor),
                    pane.trailingAnchor.constraint(equalTo: splitHost.trailingAnchor),
                    pane.bottomAnchor.constraint(equalTo: splitHost.bottomAnchor),
                    paneSize
                ]
            @unknown default:
                break
            }
            splitConstraints.append(
                editorHost.widthAnchor.constraint(greaterThanOrEqualToConstant: 240)
            )
        } else if previewVisible {
            splitConstraints = [
                pane.leadingAnchor.constraint(equalTo: splitHost.leadingAnchor),
                pane.trailingAnchor.constraint(equalTo: splitHost.trailingAnchor),
                pane.topAnchor.constraint(equalTo: splitHost.topAnchor),
                pane.bottomAnchor.constraint(equalTo: splitHost.bottomAnchor)
            ]
        } else {
            splitConstraints = [
                editorHost.leadingAnchor.constraint(equalTo: splitHost.leadingAnchor),
                editorHost.trailingAnchor.constraint(equalTo: splitHost.trailingAnchor),
                editorHost.topAnchor.constraint(equalTo: splitHost.topAnchor),
                editorHost.bottomAnchor.constraint(equalTo: splitHost.bottomAnchor)
            ]
        }
        NSLayoutConstraint.activate(splitConstraints)
        // Fullscreen preview takes over the whole window: hide app chrome.
        classicToolbar.isHidden = previewIsFullscreen
        tabBar.isHidden = previewIsFullscreen
        statusBar.view.isHidden = previewIsFullscreen
        functionList.isHidden = previewIsFullscreen ? true : !showFunctionList
        documentMap.isHidden = previewIsFullscreen ? true : !showDocumentMap
    }

    private func currentSplitOrientation() -> NSUserInterfaceLayoutOrientation {
        // Account for the side panels so the split flips before it gets cramped.
        let reserved: CGFloat = (showFunctionList ? 200 : 0) + (showDocumentMap ? 96 : 0)
        let available = (window?.frame.width ?? 1100) - reserved
        return available < 760 ? .vertical : .horizontal
    }

    /// Internal for the layout stress test; drag deltas come through here.
    /// Positive delta = drag toward the preview (right / down). The preview is
    /// pinned to the trailing/bottom edge, so dragging toward it shrinks it.
    var previewPaneDebug: (constant: CGFloat?, stored: CGFloat, mode: String, orientation: String) {
        (
            previewPaneConstraint?.constant,
            splitOrientation == .horizontal ? previewPaneWidth : previewPaneHeight,
            markdownMode.rawValue,
            splitOrientation == .horizontal ? "h" : "v"
        )
    }

    var splitHostDebug: CGFloat { splitHost.bounds.width }

    func adjustPreviewPane(by delta: CGFloat) {
        guard markdownMode == .split, !previewIsFullscreen else { return }
        let total: CGFloat
        let current: CGFloat
        if splitOrientation == .horizontal {
            // Re-sync from the live frame so a shrunk window doesn't make the
            // first drag jump.
            current = markdownPreview.view.bounds.width
            total = splitHost.bounds.width
            previewPaneWidth = clampPaneSize(current - delta, total: total)
            previewPaneConstraint?.constant = previewPaneWidth
        } else {
            current = markdownPreview.view.bounds.height
            total = splitHost.bounds.height
            previewPaneHeight = clampPaneSize(current - delta, total: total)
            previewPaneConstraint?.constant = previewPaneHeight
        }
    }

    private func clampPaneSize(_ value: CGFloat, total: CGFloat) -> CGFloat {
        min(max(value, 220), max(220, total - 240))
    }

    private func clampPreviewPaneToBounds() {
        guard markdownMode == .split, !previewIsFullscreen else { return }
        if splitOrientation == .horizontal {
            previewPaneWidth = clampPaneSize(markdownPreview.view.bounds.width, total: splitHost.bounds.width)
            previewPaneConstraint?.constant = previewPaneWidth
        } else {
            previewPaneHeight = clampPaneSize(markdownPreview.view.bounds.height, total: splitHost.bounds.height)
            previewPaneConstraint?.constant = previewPaneHeight
        }
    }

    /// Pushes the active document through the preview pane. Non-previewable
    /// documents show a friendly placeholder instead of raw text.
    private func renderMarkdownPreview(force: Bool = false) {
        guard let doc = store.activeDocument else { return }
        guard previewKind(for: doc) != .none else {
            markdownPreview.showPlaceholder(
                glyph: "✎",
                title: "Nothing to preview",
                message: "Open a .md, .html, or .json document — or set its language — to see the rendered preview."
            )
            return
        }
        if !force, doc.text == lastRenderedMarkdown { return }
        lastRenderedMarkdown = doc.text
        renderIntoActivePreview(doc)
    }

    private func scheduleMarkdownRender() {
        markdownRenderWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // Re-run detection first: typing Markdown into an untitled tab
            // should light up the mode bar without a mode switch.
            self.applyMarkdownChrome()
            self.renderMarkdownPreview()
        }
        markdownRenderWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    func documentMap(_ map: DocumentMapView, didRequestLine line: Int) {
        moveCaret(toLine: line)
    }

    func functionList(_ list: FunctionListView, didSelectLine line: Int) {
        moveCaret(toLine: line)
    }

    // MARK: - Session

    func captureSession() -> EditorSession {
        syncActiveDocumentFromEditor()
        pullActiveDrawingIntoDocument()
        let tabs: [SessionTab] = store.documents.map { doc in
            SessionTab(
                path: doc.fileURL?.path,
                // Keep unsaved text so a crash/quit doesn't lose it (restore re-reads disk for clean docs).
                untitledText: doc.isDirty ? doc.text : nil,
                languageID: doc.languageID,
                encoding: doc.encoding.rawValue,
                eol: doc.eol.rawValue,
                caret: store.activeDocument?.id == doc.id && doc.kind != .drawing ? editor.selectedRange.location : 0,
                bookmarks: Array(doc.bookmarks).sorted(),
                kind: doc.kind.rawValue
            )
        }
        return EditorSession(
            tabs: tabs,
            activeIndex: max(0, store.activeIndex),
            columnMode: editor.columnModeEnabled,
            showDocumentMap: showDocumentMap,
            showFunctionList: showFunctionList,
            showMarkdownPreview: markdownMode != .code
        )
    }

    func restoreSession(_ session: EditorSession) {
        // Close existing
        while !store.isEmpty {
            _ = store.close(at: 0)
        }
        for tab in session.tabs {
            let kind = DocumentKind(rawValue: tab.kind) ?? .text
            let doc: Document
            if let path = tab.path {
                let url = URL(fileURLWithPath: path)
                if FileManager.default.fileExists(atPath: path),
                   let opened = try? Document.open(url: url) {
                    doc = opened
                    // A dirty tab stores its unsaved text in the session — prefer it over disk.
                    if let unsaved = tab.untitledText, !unsaved.isEmpty {
                        doc.text = unsaved
                        doc.isDirty = true
                    }
                } else {
                    // File vanished — keep the path so Save recreates it, and keep any unsaved text.
                    let fallback = kind == .drawing ? Document.emptyDrawingJSON : ""
                    doc = Document(fileURL: url, text: tab.untitledText ?? fallback, kind: kind)
                    doc.isDirty = !(tab.untitledText ?? "").isEmpty
                }
            } else {
                doc = kind == .drawing ? Document.newUntitledDrawing() : Document.newUntitled()
                if let unsaved = tab.untitledText {
                    doc.text = unsaved
                }
                doc.isDirty = !(tab.untitledText ?? "").isEmpty
            }
            doc.languageID = tab.languageID
            doc.encoding = TextEncodingKind(rawValue: tab.encoding) ?? .utf8
            doc.eol = EOLStyle(rawValue: tab.eol) ?? .lf
            doc.bookmarks = Set(tab.bookmarks)
            store.add(doc, makeActive: false)
        }
        if store.isEmpty {
            newDocument()
        } else {
            store.setActiveIndex(min(session.activeIndex, store.documents.count - 1))
            editor.columnModeEnabled = session.columnMode
            showDocumentMap = session.showDocumentMap
            showFunctionList = session.showFunctionList
            markdownMode = session.showMarkdownPreview ? .split : .code
            documentMap.isHidden = !showDocumentMap
            functionList.isHidden = !showFunctionList
            documentMapWidth.constant = showDocumentMap ? 96 : 0
            functionListWidth.constant = showFunctionList ? 200 : 0
            presentActiveDocument()
            if store.activeDocument?.kind != .drawing,
               let caret = session.tabs[safe: store.activeIndex]?.caret {
                editor.setSelectedRange(NSRange(location: caret, length: 0))
            }
        }
        updateStatus()
    }

    @objc func saveSession(_ sender: Any? = nil) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "session.json"
        panel.beginSheetModal(for: window!) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            do {
                try SessionManager.save(self.captureSession(), to: url)
            } catch {
                self.showError(error)
            }
        }
    }

    @objc func loadSession(_ sender: Any? = nil) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.beginSheetModal(for: window!) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            do {
                let session = try SessionManager.load(from: url)
                self.restoreSession(session)
            } catch {
                self.showError(error)
            }
        }
    }

    @objc func restoreLastSession(_ sender: Any? = nil) {
        do {
            let session = try SessionManager.load()
            restoreSession(session)
        } catch {
            showError(error)
        }
    }

    func autosaveSession() {
        guard SessionManager.automaticAutosaveEnabled else { return }
        try? SessionManager.save(captureSession())
    }

    private func scheduleSessionAutosave() {
        guard SessionManager.automaticAutosaveEnabled else { return }
        sessionDebounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.autosaveSession()
        }
        sessionDebounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + SessionManager.debounceInterval, execute: work)
    }

    private func pullActiveDrawingIntoDocument() {
        guard let doc = store.activeDocument, doc.kind == .drawing else { return }
        drawing.flushPendingChanges()
        let json = drawing.lastSceneJSON
        guard json != doc.text else { return }
        doc.text = json
        doc.isDirty = true
    }

    // MARK: - Macros

    @objc func startMacroRecording(_ sender: Any? = nil) {
        MacroRecorder.shared.start()
        editor.resetMacroSnapshot()
        updateStatus()
    }

    @objc func stopMacroRecording(_ sender: Any? = nil) {
        MacroRecorder.shared.stop()
        updateStatus()
    }

    @objc func playbackMacro(_ sender: Any? = nil) {
        let actions = MacroRecorder.shared.playbackActions
        guard !actions.isEmpty else {
            NSSound.beep()
            return
        }
        let wasRecording = MacroRecorder.shared.isRecording
        if wasRecording { MacroRecorder.shared.stop() }
        for action in actions {
            play(action)
        }
        updateStatus()
    }

    private func play(_ action: MacroAction) {
        switch action {
        case .insertText(let text):
            if editor.columnModeEnabled {
                editor.insertInColumnMode(text)
            } else {
                editor.replaceSelected(with: text)
            }
        case .deleteBackward, .deleteForward:
            if editor.columnModeEnabled {
                editor.deleteColumnSelection()
            } else {
                let sel = editor.selectedRange
                let deletingBackward = action == .deleteBackward
                if sel.length > 0 {
                    editor.replaceSelected(with: "")
                } else if deletingBackward, sel.location > 0 {
                    editor.setSelectedRange(NSRange(location: sel.location - 1, length: 1))
                    editor.replaceSelected(with: "")
                } else if !deletingBackward, sel.location < (editor.string as NSString).length {
                    editor.setSelectedRange(NSRange(location: sel.location, length: 1))
                    editor.replaceSelected(with: "")
                }
            }
        case .newLine:
            editor.replaceSelected(with: "\n")
        case .duplicateLine:
            _ = editor.duplicateCurrentLine()
        case .moveLineUp:
            _ = editor.moveCurrentLine(down: false)
        case .moveLineDown:
            _ = editor.moveCurrentLine(down: true)
        case .findNext:
            performFind(forward: true)
        case .findPrevious:
            performFind(forward: false)
        case .toggleBookmark:
            toggleBookmark(nil)
        case .goToLine(let line):
            moveCaret(toLine: line)
        }
        syncActiveDocumentFromEditor()
    }

    // MARK: - Drag and drop / window

    func window(_ window: NSWindow, willHandle path: String) -> Bool {
        true
    }

    func windowWillClose(_ notification: Notification) {
        sessionDebounceWork?.cancel()
        sessionHeartbeatTimer?.invalidate()
        autosaveSession()
        mapRefreshTimer?.invalidate()
        fileMonitorTimer?.invalidate()
    }

    // MARK: - File monitor / print / tabs

    private func checkExternalFileChanges() {
        guard Preferences.shared.autoReloadFiles else { return }
        let changed = FileMonitor.shared.changedDocuments(in: store.documents)
        for doc in changed where !pendingReloadPrompt.contains(doc.id) {
            pendingReloadPrompt.insert(doc.id)
            let alert = NSAlert()
            alert.messageText = "File changed on disk"
            alert.informativeText = "\"\(doc.plainDisplayName)\" was modified by another program. Reload?"
            alert.addButton(withTitle: "Reload")
            alert.addButton(withTitle: "Ignore")
            alert.beginSheetModal(for: window!) { [weak self] response in
                guard let self else { return }
                self.pendingReloadPrompt.remove(doc.id)
                if response == .alertFirstButtonReturn {
                    self.reloadDocumentFromDisk(doc)
                } else {
                    FileMonitor.shared.refreshSnapshot(document: doc)
                }
            }
        }
    }

    private func reloadDocumentFromDisk(_ doc: Document) {
        guard let url = doc.fileURL, let index = store.index(of: doc) else { return }
        if doc.isDirty {
            let alert = NSAlert()
            alert.messageText = "Reload \"\(doc.plainDisplayName)\"?"
            alert.informativeText = "This file has unsaved changes. Reloading will discard them."
            alert.addButton(withTitle: "Reload")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        do {
            let fresh = try Document.open(url: url)
            doc.text = fresh.text
            doc.encoding = fresh.encoding
            doc.eol = fresh.eol
            doc.isDirty = false
            if !doc.isLanguageForced {
                doc.languageID = fresh.languageID
            }
            doc.noteOpenedOnDisk()
            if store.activeIndex == index {
                presentActiveDocument()
            } else {
                reloadTabs()
            }
        } catch {
            showError(error)
        }
    }

    @objc func reloadFromDisk(_ sender: Any? = nil) {
        guard let doc = store.activeDocument else { return }
        reloadDocumentFromDisk(doc)
    }

    @objc func printDocument(_ sender: Any? = nil) {
        syncActiveDocumentFromEditor()
        if store.activeDocument?.kind == .drawing {
            drawing.exportPNG { [weak self] data in
                guard let self else { return }
                guard let data, let image = NSImage(data: data) else {
                    NSSound.beep()
                    return
                }
                let imageView = NSImageView(image: image)
                imageView.frame = NSRect(origin: .zero, size: image.size)
                imageView.imageScaling = .scaleProportionallyDown
                let printInfo = NSPrintInfo.shared
                let op = NSPrintOperation(view: imageView, printInfo: printInfo)
                op.showsPrintPanel = true
                op.showsProgressPanel = true
                op.runModal(for: self.window!, delegate: nil, didRun: nil, contextInfo: nil)
            }
            return
        }
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 612, height: 792))
        textView.isEditable = false
        textView.font = Preferences.shared.editorFont
        textView.string = editor.string
        let printInfo = NSPrintInfo.shared
        let op = NSPrintOperation(view: textView, printInfo: printInfo)
        op.showsPrintPanel = true
        op.showsProgressPanel = true
        op.runModal(for: window!, delegate: nil, didRun: nil, contextInfo: nil)
    }

    @objc func exportDrawingPNG(_ sender: Any? = nil) {
        guard store.activeDocument?.kind == .drawing else { return }
        syncActiveDocumentFromEditor()
        drawing.exportPNG { [weak self] data in
            guard let self else { return }
            guard let data else {
                NSSound.beep()
                return
            }
            self.saveExportedData(data, ext: "png", contentType: .png)
        }
    }

    @objc func exportDrawingSVG(_ sender: Any? = nil) {
        guard store.activeDocument?.kind == .drawing else { return }
        syncActiveDocumentFromEditor()
        drawing.exportSVG { [weak self] svg in
            guard let self else { return }
            guard let svg, let data = svg.data(using: .utf8) else {
                NSSound.beep()
                return
            }
            self.saveExportedData(data, ext: "svg", contentType: .svg)
        }
    }

    /// Exports through the same renderer the preview pane uses, so the file
    /// matches the on-screen rendering exactly.
    @objc func exportMarkdownHTML(_ sender: Any? = nil) {
        guard let doc = store.activeDocument, doc.kind != .drawing, doc.isMarkdown else { return }
        syncActiveDocumentFromEditor()
        markdownPreview.exportHTML(doc.text) { [weak self] html in
            guard let self else { return }
            guard let html, let data = html.data(using: .utf8) else {
                NSSound.beep()
                return
            }
            self.saveExportedData(data, ext: "html", contentType: .html)
        }
    }

    private func saveExportedData(_ data: Data, ext: String, contentType: UTType) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [contentType]
        panel.nameFieldStringValue = exportBasename() + ".\(ext)"
        panel.beginSheetModal(for: window!) { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                self.showError(error)
            }
        }
    }

    private func exportBasename() -> String {
        let name = store.activeDocument?.plainDisplayName ?? "Drawing"
        let ns = name as NSString
        if ns.pathExtension.lowercased() == "excalidraw" {
            return ns.deletingPathExtension
        }
        return name
    }

    @objc func nextTab(_ sender: Any? = nil) {
        guard store.documents.count > 1 else { return }
        syncActiveDocumentFromEditor()
        let next = (store.activeIndex + 1) % store.documents.count
        store.setActiveIndex(next)
        presentActiveDocument()
    }

    @objc func previousTab(_ sender: Any? = nil) {
        guard store.documents.count > 1 else { return }
        syncActiveDocumentFromEditor()
        let prev = store.activeIndex <= 0 ? store.documents.count - 1 : store.activeIndex - 1
        store.setActiveIndex(prev)
        presentActiveDocument()
    }

    @objc func joinLines(_ sender: Any? = nil) {
        syncActiveDocumentFromEditor()
        let result = TextTransforms.joinLines(at: editor.selectedRange.location, in: editor.string)
        editor.applyText(result.text, selection: result.selection)
        syncActiveDocumentFromEditor()
        reloadTabs()
    }

    @objc func splitLine(_ sender: Any? = nil) {
        syncActiveDocumentFromEditor()
        let result = TextTransforms.splitLine(at: editor.selectedRange.location, in: editor.string, columns: [])
        editor.applyText(result.text, selection: result.selection)
        syncActiveDocumentFromEditor()
        reloadTabs()
    }

    @objc func removeBlankLines(_ sender: Any? = nil) {
        syncActiveDocumentFromEditor()
        let text = TextTransforms.removeBlankLines(editor.string)
        editor.applyText(text, selection: NSRange(location: 0, length: 0))
        syncActiveDocumentFromEditor()
        reloadTabs()
    }

    @objc func transposeLine(_ sender: Any? = nil) {
        syncActiveDocumentFromEditor()
        guard let result = TextTransforms.transposeLine(at: editor.selectedRange.location, in: editor.string) else {
            NSSound.beep()
            return
        }
        editor.applyText(result.text, selection: result.selection)
        syncActiveDocumentFromEditor()
        reloadTabs()
    }

    @objc func toggleToolbar(_ sender: Any? = nil) {
        Preferences.shared.showToolbar.toggle()
    }

    // MARK: - Edit extras

    @objc func toggleComment(_ sender: Any? = nil) {
        guard let doc = store.activeDocument else { return }
        syncActiveDocumentFromEditor()
        let style = CommentStyle.forLanguage(doc.languageID)
        let result = TextTransforms.toggleLineComments(
            in: editor.string,
            selection: editor.selectedRange,
            style: style
        )
        editor.applyText(result.text, selection: result.selection)
        syncActiveDocumentFromEditor()
        reloadTabs()
    }

    @objc func uppercaseSelection(_ sender: Any? = nil) {
        transformSelectionOrDocument { TextTransforms.uppercase($0) }
    }

    @objc func lowercaseSelection(_ sender: Any? = nil) {
        transformSelectionOrDocument { TextTransforms.lowercase($0) }
    }

    @objc func invertCaseSelection(_ sender: Any? = nil) {
        transformSelectionOrDocument { TextTransforms.invertCase($0) }
    }

    @objc func trimTrailingSpaces(_ sender: Any? = nil) {
        syncActiveDocumentFromEditor()
        let text = TextTransforms.trimTrailingSpaces(editor.string)
        editor.applyText(text, selection: editor.selectedRange)
        syncActiveDocumentFromEditor()
        reloadTabs()
    }

    @objc func sortLinesAscending(_ sender: Any? = nil) {
        sortLines(descending: false, unique: false)
    }

    @objc func sortLinesDescending(_ sender: Any? = nil) {
        sortLines(descending: true, unique: false)
    }

    @objc func sortLinesUnique(_ sender: Any? = nil) {
        sortLines(descending: false, unique: true)
    }

    private func sortLines(descending: Bool, unique: Bool) {
        syncActiveDocumentFromEditor()
        let text = TextTransforms.sortLines(editor.string, descending: descending, unique: unique)
        editor.applyText(text, selection: NSRange(location: 0, length: 0))
        syncActiveDocumentFromEditor()
        reloadTabs()
    }

    private func transformSelectionOrDocument(_ transform: (String) -> String) {
        syncActiveDocumentFromEditor()
        let selection = editor.selectedRange
        let text = editor.string as NSString
        if selection.length > 0 {
            let mid = transform(text.substring(with: selection))
            let mutable = NSMutableString(string: editor.string)
            mutable.replaceCharacters(in: selection, with: mid)
            editor.applyText(mutable as String, selection: NSRange(location: selection.location, length: (mid as NSString).length))
        } else {
            let all = transform(editor.string)
            editor.applyText(all, selection: selection)
        }
        syncActiveDocumentFromEditor()
        reloadTabs()
    }

    @objc func toggleInvisibleCharacters(_ sender: Any? = nil) {
        editor.setInvisibleCharacters(!editor.showsInvisibleCharacters)
    }

    @objc func matchBrace(_ sender: Any? = nil) {
        editor.highlightBrace(at: editor.selectedRange.location)
        if let range = BraceMatcher.matchingRange(at: editor.selectedRange.location, in: editor.string) {
            // Jump to opposite end
            let caret = editor.selectedRange.location
            if abs(caret - range.location) < abs(caret - (range.location + range.length - 1)) {
                editor.setSelectedRange(NSRange(location: range.location + range.length - 1, length: 0))
            } else {
                editor.setSelectedRange(NSRange(location: range.location, length: 0))
            }
        } else {
            NSSound.beep()
        }
    }

    @objc func selectToBrace(_ sender: Any? = nil) {
        guard let range = BraceMatcher.matchingRange(at: editor.selectedRange.location, in: editor.string) else {
            NSSound.beep()
            return
        }
        editor.setSelectedRange(range)
        updateStatus()
    }

    @objc func deleteLine(_ sender: Any? = nil) {
        syncActiveDocumentFromEditor()
        let line = editor.caretMetrics().line
        let text = editor.string
        guard line >= 1, line <= TextGeometry.lineCount(of: text) else {
            NSSound.beep()
            return
        }
        let result = TextGeometry.deleteLines(from: line, through: line, in: text)
        let caret = min(editor.selectedRange.location, (result as NSString).length)
        editor.applyText(result, selection: NSRange(location: caret, length: 0))
        syncActiveDocumentFromEditor()
        reloadTabs()
        updateStatus()
    }

    @objc func insertDateTime(_ sender: Any? = nil) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let stamp = formatter.string(from: Date())
        editor.replaceSelected(with: stamp)
        syncActiveDocumentFromEditor()
        updateStatus()
    }

    // MARK: - Search extras

    @objc func markAll(_ sender: Any? = nil) {
        if !findReplace.isVisible { findReplace.show() }
        let engine = currentFindEngine()
        let text = editor.string
        guard !engine.find.isEmpty else {
            findReplace.setStatus("Empty search")
            return
        }
        let matches = engine.allMatches(in: text)
        let ranges = matches.map { NSRange($0, in: text) }
        editor.markRanges(ranges)
        findReplace.setStatus("Marked \(ranges.count)")
        updateStatus()
    }

    @objc func clearMarks(_ sender: Any? = nil) {
        editor.clearMarks()
        findReplace.setStatus("")
    }

    @objc func findInFiles(_ sender: Any? = nil) {
        let panel = FindInFilesWindowController.shared
        panel.onOpenHit = { [weak self] hit in
            self?.openFile(at: hit.fileURL)
            self?.moveCaret(toLine: hit.line)
        }
        panel.showWindow(nil)
    }

    // MARK: - Compare

    @objc func compareWithNextTab(_ sender: Any? = nil) {
        syncActiveDocumentFromEditor()
        guard store.documents.count >= 2 else {
            NSSound.beep()
            return
        }
        let leftIndex = store.activeIndex
        let rightIndex = (leftIndex + 1) % store.documents.count
        let left = store.documents[leftIndex]
        let right = store.documents[rightIndex]
        let wc = CompareWindowController(
            leftTitle: left.plainDisplayName,
            rightTitle: right.plainDisplayName,
            left: left.text,
            right: right.text
        )
        compareWindows.append(wc)
        wc.showWindow(nil)
    }

    @objc func compareOpenFiles(_ sender: Any? = nil) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.item]
        panel.message = "Select exactly two files to compare"
        panel.beginSheetModal(for: window!) { [weak self] response in
            guard response == .OK, panel.urls.count == 2, let self else {
                if response == .OK { NSSound.beep() }
                return
            }
            guard let leftData = try? Data(contentsOf: panel.urls[0]),
                  let rightData = try? Data(contentsOf: panel.urls[1]),
                  let left = EncodingDetector.detect(data: leftData)?.text,
                  let right = EncodingDetector.detect(data: rightData)?.text
            else {
                NSSound.beep()
                return
            }
            let wc = CompareWindowController(
                leftTitle: panel.urls[0].lastPathComponent,
                rightTitle: panel.urls[1].lastPathComponent,
                left: left,
                right: right
            )
            self.compareWindows.append(wc)
            wc.showWindow(nil)
        }
    }

    /// General-purpose comparator: paste two snippets and diff them live.
    @objc func compareSnippets(_ sender: Any? = nil) {
        let wc = CompareWindowController.snippets()
        compareWindows.append(wc)
        wc.showWindow(nil)
    }

    // MARK: - JSON tools

    @objc func formatJSON(_ sender: Any? = nil) {
        syncActiveDocumentFromEditor()
        guard let doc = store.activeDocument, doc.kind != .drawing, isJSONish(doc) else {
            NSSound.beep()
            return
        }
        do {
            let pretty = try JsonFormatter.pretty(doc.text)
            editor.replaceDocument(pretty)
            syncActiveDocumentFromEditor()
            reloadTabs()
            renderMarkdownPreview(force: true)
        } catch {
            showError(error)
        }
    }

    @objc func minifyJSON(_ sender: Any? = nil) {
        syncActiveDocumentFromEditor()
        guard let doc = store.activeDocument, doc.kind != .drawing, isJSONish(doc) else {
            NSSound.beep()
            return
        }
        do {
            let minified = try JsonFormatter.minify(doc.text)
            editor.replaceDocument(minified)
            syncActiveDocumentFromEditor()
            reloadTabs()
            renderMarkdownPreview(force: true)
        } catch {
            showError(error)
        }
    }

    @objc func validateJSON(_ sender: Any? = nil) {
        syncActiveDocumentFromEditor()
        guard let doc = store.activeDocument, doc.kind != .drawing, isJSONish(doc) else {
            NSSound.beep()
            return
        }
        let alert = NSAlert()
        if let error = JsonFormatter.validate(doc.text) {
            alert.alertStyle = .critical
            alert.messageText = "Invalid JSON"
            alert.informativeText = error
        } else {
            alert.alertStyle = .informational
            alert.messageText = "Valid JSON"
            alert.informativeText = "The document parses successfully."
        }
        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    /// Format/minify/validate apply to .json files, forced language, or any
    /// document whose content actually parses as JSON.
    private func isJSONish(_ doc: Document) -> Bool {
        doc.isJSONDocument || doc.looksLikeJSONContent
    }

    // MARK: - Plugins

    func refreshPluginsMenu(_ menu: NSMenu) {
        pluginsMenu = menu
        menu.removeAllItems()
        let plugins = PluginHost.availablePlugins()
        if plugins.isEmpty {
            let empty = NSMenuItem(title: "No Plugins", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for plugin in plugins {
                let item = NSMenuItem(title: plugin.name, action: #selector(runPlugin(_:)), keyEquivalent: "")
                item.representedObject = plugin.id
                item.target = self
                menu.addItem(item)
            }
        }
        menu.addItem(NSMenuItem.separator())
        let openFolder = NSMenuItem(title: "Open Plugins Folder", action: #selector(openPluginsFolder(_:)), keyEquivalent: "")
        openFolder.target = self
        menu.addItem(openFolder)
        let reload = NSMenuItem(title: "Reload Plugins", action: #selector(reloadPlugins(_:)), keyEquivalent: "")
        reload.target = self
        menu.addItem(reload)
    }

    @objc func runPlugin(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let plugin = PluginHost.availablePlugins().first(where: { $0.id == id }),
              let doc = store.activeDocument else { return }
        syncActiveDocumentFromEditor()
        do {
            let result = try PluginHost.run(
                plugin: plugin,
                text: editor.string,
                selection: editor.selectedRange,
                languageID: doc.languageID
            )
            editor.applyText(result.text, selection: result.selection)
            syncActiveDocumentFromEditor()
            reloadTabs()
        } catch {
            showError(error)
        }
    }

    @objc func openPluginsFolder(_ sender: Any? = nil) {
        PluginHost.installBundledPluginsIfNeeded()
        NSWorkspace.shared.open(PluginHost.pluginsDirectory)
    }

    @objc func reloadPlugins(_ sender: Any? = nil) {
        if let menu = pluginsMenu {
            refreshPluginsMenu(menu)
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let drawing = store.activeDocument?.kind == .drawing
        switch menuItem.action {
        case #selector(exportDrawingPNG(_:)), #selector(exportDrawingSVG(_:)):
            return drawing
        case #selector(exportMarkdownHTML(_:)):
            return !drawing && (store.activeDocument?.isMarkdown ?? false)
        case #selector(toggleMarkdownPreview(_:)), #selector(toggleFullscreenPreview(_:)):
            return !drawing && markdownUIEnabled
        case #selector(formatJSON(_:)), #selector(minifyJSON(_:)), #selector(validateJSON(_:)):
            return !drawing && (store.activeDocument.map { isJSONish($0) } ?? false)
        case #selector(setMarkdownModeCommand(_:)):
            guard !drawing, markdownUIEnabled else { return false }
            if let raw = menuItem.representedObject as? String {
                menuItem.state = (markdownMode == MarkdownViewMode(rawValue: raw) && !previewIsFullscreen)
                    || (previewIsFullscreen && raw == MarkdownViewMode.preview.rawValue)
                    ? .on : .off
            }
            return true
        default:
            break
        }
        guard drawing else { return true }
        switch menuItem.action {
        case #selector(changeEncoding(_:)),
             #selector(changeEOL(_:)),
             #selector(changeLanguage(_:)),
             #selector(toggleColumnMode(_:)),
             #selector(columnCopy(_:)),
             #selector(columnPaste(_:)),
             #selector(columnDelete(_:)),
             #selector(showFindPanel(_:)),
             #selector(showReplacePanel(_:)),
             #selector(findNext(_:)),
             #selector(findPrevious(_:)),
             #selector(toggleBookmark(_:)),
             #selector(nextBookmark(_:)),
             #selector(previousBookmark(_:)),
             #selector(clearBookmarks(_:)),
             #selector(toggleWordWrap(_:)),
             #selector(toggleLineNumbers(_:)),
             #selector(toggleDocumentMap(_:)),
             #selector(toggleFunctionList(_:)),
             #selector(zoomIn(_:)),
             #selector(zoomOut(_:)),
             #selector(zoomReset(_:)),
             #selector(toggleComment(_:)),
             #selector(uppercaseSelection(_:)),
             #selector(lowercaseSelection(_:)),
             #selector(invertCaseSelection(_:)),
             #selector(trimTrailingSpaces(_:)),
             #selector(sortLinesAscending(_:)),
             #selector(sortLinesDescending(_:)),
             #selector(sortLinesUnique(_:)),
             #selector(matchBrace(_:)),
             #selector(selectToBrace(_:)),
             #selector(deleteLine(_:)),
             #selector(insertDateTime(_:)),
             #selector(toggleInvisibleCharacters(_:)),
             #selector(markAll(_:)),
             #selector(clearMarks(_:)),
             #selector(duplicateLine(_:)),
             #selector(moveLineUp(_:)),
             #selector(moveLineDown(_:)),
             #selector(joinLines(_:)),
             #selector(splitLine(_:)),
             #selector(transposeLine(_:)),
             #selector(removeBlankLines(_:)),
             #selector(goToLine(_:)),
             #selector(startMacroRecording(_:)),
             #selector(stopMacroRecording(_:)),
             #selector(playbackMacro(_:)):
            return false
        default:
            return true
        }
    }

    // MARK: - FTP

    @objc func showFTP(_ sender: Any? = nil) {
        let ftp = ftpWindow ?? FTPWindowController()
        ftpWindow = ftp
        ftp.onDownloaded = { [weak self] text, name, _ in
            guard let self else { return }
            let doc = Document.newUntitled()
            doc.text = text
            // Best-effort name via temp feel: language from extension
            doc.languageID = LanguageRegistry.shared.languageID(forExtension: (name as NSString).pathExtension)
            if !text.isEmpty { doc.isDirty = true }
            self.store.add(doc)
            self.presentActiveDocument()
        }
        ftp.onUploadRequest = { [weak self] in
            guard let self, let doc = self.store.activeDocument else { return nil }
            self.syncActiveDocumentFromEditor()
            return (
                text: doc.text,
                credentials: FTPCredentials(host: "", username: "", password: "", remotePath: "/")
            )
        }
        ftp.showWindow(nil)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
