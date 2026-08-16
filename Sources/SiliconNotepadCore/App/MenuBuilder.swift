import AppKit

enum MenuBuilder {
    static func setActionTarget(_ target: AnyObject) {
        NSApp.mainMenu = buildMainMenu(target: target)
    }

    static func buildMainMenu(target: AnyObject?) -> NSMenu {
        let main = NSMenu()

        // App
        let appMenuItem = NSMenuItem()
        main.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(withTitle: "About \(AppIdentity.displayName)", action: #selector(MainWindowController.showAbout(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Preferences…", action: #selector(MainWindowController.showPreferences(_:)), keyEquivalent: ",")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Hide \(AppIdentity.displayName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit \(AppIdentity.displayName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // File
        let fileItem = NSMenuItem()
        main.addItem(fileItem)
        let file = NSMenu(title: "File")
        fileItem.submenu = file
        file.addItem(withTitle: "New", action: #selector(MainWindowController.newDocument(_:)), keyEquivalent: "n")
        let newDrawing = NSMenuItem(
            title: "New Drawing",
            action: #selector(MainWindowController.newDrawing(_:)),
            keyEquivalent: "n"
        )
        newDrawing.keyEquivalentModifierMask = [.command, .shift]
        file.addItem(newDrawing)
        file.addItem(withTitle: "Open…", action: #selector(MainWindowController.openDocument(_:)), keyEquivalent: "o")
        file.addItem(NSMenuItem.separator())
        let openRecent = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
        let recentMenu = NSMenu(title: "Open Recent")
        recentMenu.autoenablesItems = true
        openRecent.submenu = recentMenu
        recentMenu.delegate = RecentMenuDelegate.shared
        file.addItem(openRecent)
        file.addItem(NSMenuItem.separator())
        file.addItem(withTitle: "Close Tab", action: #selector(MainWindowController.closeDocument(_:)), keyEquivalent: "w")
        file.addItem(withTitle: "Save", action: #selector(MainWindowController.saveDocument(_:)), keyEquivalent: "s")
        file.addItem(withTitle: "Save All", action: #selector(MainWindowController.saveAllDocuments(_:)), keyEquivalent: "s")
        if let item = file.items.last { item.keyEquivalentModifierMask = [.command, .shift] }
        file.addItem(NSMenuItem(title: "Save As…", action: #selector(MainWindowController.saveDocumentAs(_:)), keyEquivalent: "S"))
        file.addItem(NSMenuItem.separator())
        file.addItem(withTitle: "Export PNG…", action: #selector(MainWindowController.exportDrawingPNG(_:)), keyEquivalent: "")
        file.addItem(withTitle: "Export SVG…", action: #selector(MainWindowController.exportDrawingSVG(_:)), keyEquivalent: "")
        file.addItem(withTitle: "Export HTML…", action: #selector(MainWindowController.exportMarkdownHTML(_:)), keyEquivalent: "")
        file.addItem(NSMenuItem.separator())
        file.addItem(withTitle: "Save Session…", action: #selector(MainWindowController.saveSession(_:)), keyEquivalent: "")
        file.addItem(withTitle: "Load Session…", action: #selector(MainWindowController.loadSession(_:)), keyEquivalent: "")
        file.addItem(withTitle: "Restore Last Session", action: #selector(MainWindowController.restoreLastSession(_:)), keyEquivalent: "")
        file.addItem(NSMenuItem.separator())
        file.addItem(withTitle: "FTP / SFTP…", action: #selector(MainWindowController.showFTP(_:)), keyEquivalent: "")
        file.addItem(NSMenuItem.separator())
        file.addItem(withTitle: "Reload from Disk", action: #selector(MainWindowController.reloadFromDisk(_:)), keyEquivalent: "r")
        if let item = file.items.last { item.keyEquivalentModifierMask = [.command, .shift] }
        file.addItem(withTitle: "Print…", action: #selector(MainWindowController.printDocument(_:)), keyEquivalent: "p")

        // Tab
        let tabItem = NSMenuItem()
        main.addItem(tabItem)
        let tab = NSMenu(title: "Tab")
        tabItem.submenu = tab
        tab.addItem(withTitle: "Close", action: #selector(MainWindowController.closeDocument(_:)), keyEquivalent: "w")
        tab.addItem(withTitle: "Close Others", action: #selector(MainWindowController.closeOtherTabs(_:)), keyEquivalent: "")
        tab.addItem(withTitle: "Close All", action: #selector(MainWindowController.closeAllTabs(_:)), keyEquivalent: "")
        tab.addItem(withTitle: "Close All to the Left", action: #selector(MainWindowController.closeTabsToLeft(_:)), keyEquivalent: "")
        tab.addItem(withTitle: "Close All to the Right", action: #selector(MainWindowController.closeTabsToRight(_:)), keyEquivalent: "")
        tab.addItem(NSMenuItem.separator())
        tab.addItem(withTitle: "Next Tab", action: #selector(MainWindowController.nextTab(_:)), keyEquivalent: "\u{09}")
        if let item = tab.items.last { item.keyEquivalentModifierMask = [.control] }
        tab.addItem(withTitle: "Previous Tab", action: #selector(MainWindowController.previousTab(_:)), keyEquivalent: "\u{09}")
        if let item = tab.items.last { item.keyEquivalentModifierMask = [.control, .shift] }
        tab.addItem(NSMenuItem.separator())
        tab.addItem(withTitle: "Move Tab to Start", action: #selector(MainWindowController.moveTabToStart(_:)), keyEquivalent: "")
        tab.addItem(withTitle: "Move Tab to End", action: #selector(MainWindowController.moveTabToEnd(_:)), keyEquivalent: "")
        tab.addItem(withTitle: "Move Tab Left", action: #selector(MainWindowController.moveTabLeft(_:)), keyEquivalent: "")
        tab.addItem(withTitle: "Move Tab Right", action: #selector(MainWindowController.moveTabRight(_:)), keyEquivalent: "")
        tab.addItem(NSMenuItem.separator())
        tab.addItem(withTitle: "Clone to New Tab", action: #selector(MainWindowController.cloneTab(_:)), keyEquivalent: "")
        tab.addItem(withTitle: "Copy File Path", action: #selector(MainWindowController.copyFilePath(_:)), keyEquivalent: "")
        tab.addItem(withTitle: "Copy Filename", action: #selector(MainWindowController.copyFilename(_:)), keyEquivalent: "")
        tab.addItem(withTitle: "Open Containing Folder", action: #selector(MainWindowController.openContainingFolder(_:)), keyEquivalent: "")

        // Edit
        let editItem = NSMenuItem()
        main.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        editItem.submenu = edit
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(NSMenuItem.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.addItem(NSMenuItem.separator())
        edit.addItem(withTitle: "Duplicate Current Line", action: #selector(MainWindowController.duplicateLine(_:)), keyEquivalent: "d")
        edit.addItem(withTitle: "Move Line Up", action: #selector(MainWindowController.moveLineUp(_:)), keyEquivalent: "[")
        if let item = edit.items.last { item.keyEquivalentModifierMask = [.command, .option] }
        edit.addItem(withTitle: "Move Line Down", action: #selector(MainWindowController.moveLineDown(_:)), keyEquivalent: "]")
        if let item = edit.items.last { item.keyEquivalentModifierMask = [.command, .option] }
        edit.addItem(NSMenuItem.separator())
        edit.addItem(withTitle: "Column Mode", action: #selector(MainWindowController.toggleColumnMode(_:)), keyEquivalent: "c")
        if let item = edit.items.last { item.keyEquivalentModifierMask = [.command, .shift] }
        edit.addItem(withTitle: "Column Copy", action: #selector(MainWindowController.columnCopy(_:)), keyEquivalent: "")
        edit.addItem(withTitle: "Column Paste", action: #selector(MainWindowController.columnPaste(_:)), keyEquivalent: "")
        edit.addItem(withTitle: "Column Delete", action: #selector(MainWindowController.columnDelete(_:)), keyEquivalent: "")
        edit.addItem(NSMenuItem.separator())
        edit.addItem(withTitle: "Go to Line…", action: #selector(MainWindowController.goToLine(_:)), keyEquivalent: "l")
        edit.addItem(NSMenuItem.separator())
        edit.addItem(withTitle: "Toggle Comment", action: #selector(MainWindowController.toggleComment(_:)), keyEquivalent: "/")
        if let item = edit.items.last { item.keyEquivalentModifierMask = [.command] }
        edit.addItem(withTitle: "Format JSON", action: #selector(MainWindowController.formatJSON(_:)), keyEquivalent: "l")
        if let item = edit.items.last { item.keyEquivalentModifierMask = [.command, .option] }
        edit.addItem(withTitle: "Minify JSON", action: #selector(MainWindowController.minifyJSON(_:)), keyEquivalent: "m")
        if let item = edit.items.last { item.keyEquivalentModifierMask = [.command, .option] }
        edit.addItem(withTitle: "Validate JSON", action: #selector(MainWindowController.validateJSON(_:)), keyEquivalent: "")
        edit.addItem(withTitle: "Delete Line", action: #selector(MainWindowController.deleteLine(_:)), keyEquivalent: "l")
        if let item = edit.items.last { item.keyEquivalentModifierMask = [.command, .shift] }
        edit.addItem(withTitle: "UPPERCASE", action: #selector(MainWindowController.uppercaseSelection(_:)), keyEquivalent: "u")
        if let item = edit.items.last { item.keyEquivalentModifierMask = [.command, .shift] }
        edit.addItem(withTitle: "lowercase", action: #selector(MainWindowController.lowercaseSelection(_:)), keyEquivalent: "u")
        if let item = edit.items.last { item.keyEquivalentModifierMask = [.command, .option] }
        edit.addItem(withTitle: "inVERT cASE", action: #selector(MainWindowController.invertCaseSelection(_:)), keyEquivalent: "")
        edit.addItem(withTitle: "Trim Trailing Space", action: #selector(MainWindowController.trimTrailingSpaces(_:)), keyEquivalent: "")
        edit.addItem(withTitle: "Sort Lines A→Z", action: #selector(MainWindowController.sortLinesAscending(_:)), keyEquivalent: "")
        edit.addItem(withTitle: "Sort Lines Z→A", action: #selector(MainWindowController.sortLinesDescending(_:)), keyEquivalent: "")
        edit.addItem(withTitle: "Sort Lines Unique", action: #selector(MainWindowController.sortLinesUnique(_:)), keyEquivalent: "")
        edit.addItem(NSMenuItem.separator())
        edit.addItem(withTitle: "Match Brace", action: #selector(MainWindowController.matchBrace(_:)), keyEquivalent: "b")
        if let item = edit.items.last { item.keyEquivalentModifierMask = [.control] }
        edit.addItem(withTitle: "Select to Matching Brace", action: #selector(MainWindowController.selectToBrace(_:)), keyEquivalent: "")
        edit.addItem(NSMenuItem.separator())
        edit.addItem(withTitle: "Insert Date/Time", action: #selector(MainWindowController.insertDateTime(_:)), keyEquivalent: "\u{F708}")
        edit.addItem(withTitle: "Join Lines", action: #selector(MainWindowController.joinLines(_:)), keyEquivalent: "j")
        if let item = edit.items.last { item.keyEquivalentModifierMask = [.command] }
        edit.addItem(withTitle: "Split Line", action: #selector(MainWindowController.splitLine(_:)), keyEquivalent: "")
        edit.addItem(withTitle: "Transpose Line", action: #selector(MainWindowController.transposeLine(_:)), keyEquivalent: "")
        edit.addItem(withTitle: "Remove Blank Lines", action: #selector(MainWindowController.removeBlankLines(_:)), keyEquivalent: "")

        // Search
        let searchItem = NSMenuItem()
        main.addItem(searchItem)
        let search = NSMenu(title: "Search")
        searchItem.submenu = search
        search.addItem(withTitle: "Find…", action: #selector(MainWindowController.showFindPanel(_:)), keyEquivalent: "f")
        search.addItem(withTitle: "Replace…", action: #selector(MainWindowController.showReplacePanel(_:)), keyEquivalent: "r")
        search.addItem(withTitle: "Find Next", action: #selector(MainWindowController.findNext(_:)), keyEquivalent: "g")
        search.addItem(NSMenuItem(title: "Find Previous", action: #selector(MainWindowController.findPrevious(_:)), keyEquivalent: "G"))
        search.addItem(NSMenuItem.separator())
        search.addItem(withTitle: "Toggle Bookmark", action: #selector(MainWindowController.toggleBookmark(_:)), keyEquivalent: "b")
        if let item = search.items.last { item.keyEquivalentModifierMask = [.command, .shift] }
        search.addItem(withTitle: "Next Bookmark", action: #selector(MainWindowController.nextBookmark(_:)), keyEquivalent: ".")
        if let item = search.items.last { item.keyEquivalentModifierMask = [.command, .shift] }
        search.addItem(withTitle: "Previous Bookmark", action: #selector(MainWindowController.previousBookmark(_:)), keyEquivalent: ",")
        if let item = search.items.last { item.keyEquivalentModifierMask = [.command, .shift] }
        search.addItem(withTitle: "Clear All Bookmarks", action: #selector(MainWindowController.clearBookmarks(_:)), keyEquivalent: "")
        search.addItem(NSMenuItem.separator())
        search.addItem(withTitle: "Mark All", action: #selector(MainWindowController.markAll(_:)), keyEquivalent: "a")
        if let item = search.items.last { item.keyEquivalentModifierMask = [.command, .option] }
        search.addItem(withTitle: "Clear Marks", action: #selector(MainWindowController.clearMarks(_:)), keyEquivalent: "")
        search.addItem(withTitle: "Find in Files…", action: #selector(MainWindowController.findInFiles(_:)), keyEquivalent: "f")
        if let item = search.items.last { item.keyEquivalentModifierMask = [.command, .shift, .option] }

        // View
        let viewItem = NSMenuItem()
        main.addItem(viewItem)
        let view = NSMenu(title: "View")
        viewItem.submenu = view
        view.addItem(withTitle: "Word Wrap", action: #selector(MainWindowController.toggleWordWrap(_:)), keyEquivalent: "")
        view.addItem(withTitle: "Show Line Numbers", action: #selector(MainWindowController.toggleLineNumbers(_:)), keyEquivalent: "")
        view.addItem(withTitle: "Document Map", action: #selector(MainWindowController.toggleDocumentMap(_:)), keyEquivalent: "m")
        if let item = view.items.last { item.keyEquivalentModifierMask = [.command, .shift] }
        view.addItem(withTitle: "Function List", action: #selector(MainWindowController.toggleFunctionList(_:)), keyEquivalent: "f")
        if let item = view.items.last { item.keyEquivalentModifierMask = [.command, .shift] }
        view.addItem(withTitle: "Toggle Markdown Split", action: #selector(MainWindowController.toggleMarkdownPreview(_:)), keyEquivalent: "v")
        if let item = view.items.last { item.keyEquivalentModifierMask = [.command, .shift] }

        let mdModeItem = NSMenuItem(title: "Markdown Mode", action: nil, keyEquivalent: "")
        let mdModeMenu = NSMenu(title: "Markdown Mode")
        for (index, mode) in MarkdownViewMode.allCases.enumerated() {
            let item = NSMenuItem(
                title: mode.label,
                action: #selector(MainWindowController.setMarkdownModeCommand(_:)),
                keyEquivalent: String(index + 1)
            )
            item.keyEquivalentModifierMask = [.command, .option]
            item.representedObject = mode.rawValue
            mdModeMenu.addItem(item)
        }
        mdModeMenu.addItem(NSMenuItem.separator())
        let fullscreen = NSMenuItem(
            title: "Fullscreen Preview",
            action: #selector(MainWindowController.toggleFullscreenPreview(_:)),
            keyEquivalent: "f"
        )
        fullscreen.keyEquivalentModifierMask = [.command, .option]
        mdModeMenu.addItem(fullscreen)
        mdModeItem.submenu = mdModeMenu
        view.addItem(mdModeItem)
        view.addItem(withTitle: "Show Symbol Characters", action: #selector(MainWindowController.toggleInvisibleCharacters(_:)), keyEquivalent: "")
        view.addItem(withTitle: "Show Toolbar", action: #selector(MainWindowController.toggleToolbar(_:)), keyEquivalent: "")
        view.addItem(NSMenuItem.separator())
        view.addItem(withTitle: "Compare with Next Tab", action: #selector(MainWindowController.compareWithNextTab(_:)), keyEquivalent: "")
        view.addItem(withTitle: "Compare Two Files…", action: #selector(MainWindowController.compareOpenFiles(_:)), keyEquivalent: "")
        view.addItem(withTitle: "Compare Snippets…", action: #selector(MainWindowController.compareSnippets(_:)), keyEquivalent: "")
        view.addItem(NSMenuItem.separator())
        view.addItem(withTitle: "Zoom In", action: #selector(MainWindowController.zoomIn(_:)), keyEquivalent: "=")
        view.addItem(withTitle: "Zoom Out", action: #selector(MainWindowController.zoomOut(_:)), keyEquivalent: "-")
        view.addItem(withTitle: "Reset Zoom", action: #selector(MainWindowController.zoomReset(_:)), keyEquivalent: "0")
        view.addItem(NSMenuItem.separator())
        view.addItem(withTitle: "Light Theme", action: #selector(MainWindowController.useLightTheme(_:)), keyEquivalent: "")
        view.addItem(withTitle: "Dark Theme", action: #selector(MainWindowController.useDarkTheme(_:)), keyEquivalent: "")

        // Macro
        let macroItem = NSMenuItem()
        main.addItem(macroItem)
        let macro = NSMenu(title: "Macro")
        macroItem.submenu = macro
        macro.addItem(withTitle: "Start Recording", action: #selector(MainWindowController.startMacroRecording(_:)), keyEquivalent: "")
        macro.addItem(withTitle: "Stop Recording", action: #selector(MainWindowController.stopMacroRecording(_:)), keyEquivalent: "")
        macro.addItem(withTitle: "Playback", action: #selector(MainWindowController.playbackMacro(_:)), keyEquivalent: "p")
        if let item = macro.items.last { item.keyEquivalentModifierMask = [.command, .shift] }

        // Tools
        let toolsItem = NSMenuItem()
        main.addItem(toolsItem)
        let tools = NSMenu(title: "Tools")
        toolsItem.submenu = tools
        tools.addItem(withTitle: "String Workbench…", action: #selector(MainWindowController.showStringWorkbench(_:)), keyEquivalent: "t")
        if let item = tools.items.last { item.keyEquivalentModifierMask = [.command, .option] }
        tools.addItem(withTitle: "Compare Snippets…", action: #selector(MainWindowController.compareSnippets(_:)), keyEquivalent: "")

        // Plugins
        let pluginsItem = NSMenuItem()
        main.addItem(pluginsItem)
        let plugins = NSMenu(title: "Plugins")
        pluginsItem.submenu = plugins
        if let target = target as? MainWindowController {
            target.refreshPluginsMenu(plugins)
        } else {
            plugins.addItem(withTitle: "Open Plugins Folder", action: #selector(MainWindowController.openPluginsFolder(_:)), keyEquivalent: "")
        }

        // Encoding
        let encodingItem = NSMenuItem()
        main.addItem(encodingItem)
        let encoding = NSMenu(title: "Encoding")
        encodingItem.submenu = encoding
        for kind in TextEncodingKind.allCases {
            encoding.addItem(withTitle: kind.rawValue, action: #selector(MainWindowController.changeEncoding(_:)), keyEquivalent: "")
        }
        encoding.addItem(NSMenuItem.separator())
        let eolMenu = NSMenu(title: "EOL Conversion")
        let eolItem = NSMenuItem(title: "EOL Conversion", action: nil, keyEquivalent: "")
        eolItem.submenu = eolMenu
        encoding.addItem(eolItem)
        for eol in EOLStyle.allCases {
            eolMenu.addItem(withTitle: eol.rawValue, action: #selector(MainWindowController.changeEOL(_:)), keyEquivalent: "")
        }

        // Language (Notepad++ style A–Z groups)
        let languageItem = NSMenuItem()
        main.addItem(languageItem)
        let language = NSMenu(title: "Language")
        languageItem.submenu = language
        for category in LanguageRegistry.shared.categories {
            let group = NSMenuItem(title: category, action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: category)
            for info in LanguageRegistry.shared.languages(in: category) {
                let item = NSMenuItem(
                    title: info.displayName,
                    action: #selector(MainWindowController.changeLanguage(_:)),
                    keyEquivalent: ""
                )
                item.representedObject = info.id
                submenu.addItem(item)
            }
            group.submenu = submenu
            language.addItem(group)
        }

        // Settings
        let settingsItem = NSMenuItem()
        main.addItem(settingsItem)
        let settings = NSMenu(title: "Settings")
        settingsItem.submenu = settings
        settings.addItem(withTitle: "Preferences…", action: #selector(MainWindowController.showPreferences(_:)), keyEquivalent: "")

        // Help
        let helpItem = NSMenuItem()
        main.addItem(helpItem)
        let help = NSMenu(title: "Help")
        helpItem.submenu = help
        help.addItem(withTitle: "About \(AppIdentity.displayName)", action: #selector(MainWindowController.showAbout(_:)), keyEquivalent: "")

        let customSelectors: [Selector] = [
            #selector(MainWindowController.showAbout(_:)),
            #selector(MainWindowController.showPreferences(_:)),
            #selector(MainWindowController.newDocument(_:)),
            #selector(MainWindowController.newDrawing(_:)),
            #selector(MainWindowController.openDocument(_:)),
            #selector(MainWindowController.openRecentDocument(_:)),
            #selector(MainWindowController.closeDocument(_:)),
            #selector(MainWindowController.saveDocument(_:)),
            #selector(MainWindowController.saveAllDocuments(_:)),
            #selector(MainWindowController.saveDocumentAs(_:)),
            #selector(MainWindowController.exportDrawingPNG(_:)),
            #selector(MainWindowController.exportDrawingSVG(_:)),
            #selector(MainWindowController.saveSession(_:)),
            #selector(MainWindowController.loadSession(_:)),
            #selector(MainWindowController.restoreLastSession(_:)),
            #selector(MainWindowController.goToLine(_:)),
            #selector(MainWindowController.duplicateLine(_:)),
            #selector(MainWindowController.moveLineUp(_:)),
            #selector(MainWindowController.moveLineDown(_:)),
            #selector(MainWindowController.toggleColumnMode(_:)),
            #selector(MainWindowController.columnCopy(_:)),
            #selector(MainWindowController.columnPaste(_:)),
            #selector(MainWindowController.columnDelete(_:)),
            #selector(MainWindowController.showFindPanel(_:)),
            #selector(MainWindowController.showReplacePanel(_:)),
            #selector(MainWindowController.findNext(_:)),
            #selector(MainWindowController.findPrevious(_:)),
            #selector(MainWindowController.toggleBookmark(_:)),
            #selector(MainWindowController.nextBookmark(_:)),
            #selector(MainWindowController.previousBookmark(_:)),
            #selector(MainWindowController.clearBookmarks(_:)),
            #selector(MainWindowController.toggleWordWrap(_:)),
            #selector(MainWindowController.toggleLineNumbers(_:)),
            #selector(MainWindowController.toggleDocumentMap(_:)),
            #selector(MainWindowController.toggleFunctionList(_:)),
            #selector(MainWindowController.toggleMarkdownPreview(_:)),
            #selector(MainWindowController.setMarkdownModeCommand(_:)),
            #selector(MainWindowController.toggleFullscreenPreview(_:)),
            #selector(MainWindowController.zoomIn(_:)),
            #selector(MainWindowController.zoomOut(_:)),
            #selector(MainWindowController.zoomReset(_:)),
            #selector(MainWindowController.useLightTheme(_:)),
            #selector(MainWindowController.useDarkTheme(_:)),
            #selector(MainWindowController.startMacroRecording(_:)),
            #selector(MainWindowController.stopMacroRecording(_:)),
            #selector(MainWindowController.playbackMacro(_:)),
            #selector(MainWindowController.changeEncoding(_:)),
            #selector(MainWindowController.changeEOL(_:)),
            #selector(MainWindowController.changeLanguage(_:)),
            #selector(MainWindowController.toggleComment(_:)),
            #selector(MainWindowController.uppercaseSelection(_:)),
            #selector(MainWindowController.lowercaseSelection(_:)),
            #selector(MainWindowController.invertCaseSelection(_:)),
            #selector(MainWindowController.trimTrailingSpaces(_:)),
            #selector(MainWindowController.sortLinesAscending(_:)),
            #selector(MainWindowController.sortLinesDescending(_:)),
            #selector(MainWindowController.sortLinesUnique(_:)),
            #selector(MainWindowController.matchBrace(_:)),
            #selector(MainWindowController.selectToBrace(_:)),
            #selector(MainWindowController.deleteLine(_:)),
            #selector(MainWindowController.insertDateTime(_:)),
            #selector(MainWindowController.toggleInvisibleCharacters(_:)),
            #selector(MainWindowController.markAll(_:)),
            #selector(MainWindowController.clearMarks(_:)),
            #selector(MainWindowController.findInFiles(_:)),
            #selector(MainWindowController.compareWithNextTab(_:)),
            #selector(MainWindowController.compareOpenFiles(_:)),
            #selector(MainWindowController.openPluginsFolder(_:)),
            #selector(MainWindowController.reloadPlugins(_:)),
            #selector(MainWindowController.showFTP(_:)),
            #selector(MainWindowController.reloadFromDisk(_:)),
            #selector(MainWindowController.printDocument(_:)),
            #selector(MainWindowController.nextTab(_:)),
            #selector(MainWindowController.previousTab(_:)),
            #selector(MainWindowController.joinLines(_:)),
            #selector(MainWindowController.splitLine(_:)),
            #selector(MainWindowController.transposeLine(_:)),
            #selector(MainWindowController.removeBlankLines(_:)),
            #selector(MainWindowController.toggleToolbar(_:)),
            #selector(MainWindowController.formatJSON(_:)),
            #selector(MainWindowController.minifyJSON(_:)),
            #selector(MainWindowController.validateJSON(_:)),
            #selector(MainWindowController.closeOtherTabs(_:)),
            #selector(MainWindowController.closeAllTabs(_:)),
            #selector(MainWindowController.closeTabsToLeft(_:)),
            #selector(MainWindowController.closeTabsToRight(_:)),
            #selector(MainWindowController.moveTabToStart(_:)),
            #selector(MainWindowController.moveTabToEnd(_:)),
            #selector(MainWindowController.moveTabLeft(_:)),
            #selector(MainWindowController.moveTabRight(_:)),
            #selector(MainWindowController.cloneTab(_:)),
            #selector(MainWindowController.copyFilePath(_:)),
            #selector(MainWindowController.copyFilename(_:)),
            #selector(MainWindowController.openContainingFolder(_:))
        ]

        if let target {
            setTargets(in: main, selectors: Set(customSelectors), target: target)
        }

        return main
    }

    private static func setTargets(in menu: NSMenu, selectors: Set<Selector>, target: AnyObject) {
        for item in menu.items {
            if let action = item.action, selectors.contains(action) {
                item.target = target
            }
            if let submenu = item.submenu {
                setTargets(in: submenu, selectors: selectors, target: target)
            }
        }
    }
}
