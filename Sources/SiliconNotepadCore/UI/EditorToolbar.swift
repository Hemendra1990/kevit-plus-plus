import AppKit

final class EditorToolbar: NSObject, NSToolbarDelegate {
    static let identifier = NSToolbar.Identifier("KevitPlusPlusToolbar")

    private weak var target: MainWindowController?

    init(target: MainWindowController) {
        self.target = target
        super.init()
    }

    func makeToolbar() -> NSToolbar {
        let toolbar = NSToolbar(identifier: Self.identifier)
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = true
        toolbar.autosavesConfiguration = true
        return toolbar
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .newDoc, .newDrawing, .openDoc, .saveDoc, .flexibleSpace,
            .find, .replace, .comment, .bookmark, .flexibleSpace,
            .printDoc
        ]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        switch itemIdentifier {
        case .newDoc:
            item.label = "New"; item.image = NSImage(systemSymbolName: "doc", accessibilityDescription: nil)
            item.action = #selector(MainWindowController.newDocument(_:)); item.target = target
        case .newDrawing:
            item.label = "New Drawing"; item.image = NSImage(systemSymbolName: "square.and.pencil", accessibilityDescription: nil)
            item.action = #selector(MainWindowController.newDrawing(_:)); item.target = target
        case .openDoc:
            item.label = "Open"; item.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
            item.action = #selector(MainWindowController.openDocument(_:)); item.target = target
        case .saveDoc:
            item.label = "Save"; item.image = NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: nil)
            item.action = #selector(MainWindowController.saveDocument(_:)); item.target = target
        case .find:
            item.label = "Find"; item.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
            item.action = #selector(MainWindowController.showFindPanel(_:)); item.target = target
        case .replace:
            item.label = "Replace"; item.image = NSImage(systemSymbolName: "arrow.left.arrow.right", accessibilityDescription: nil)
            item.action = #selector(MainWindowController.showReplacePanel(_:)); item.target = target
        case .comment:
            item.label = "Comment"; item.image = NSImage(systemSymbolName: "number", accessibilityDescription: nil)
            item.action = #selector(MainWindowController.toggleComment(_:)); item.target = target
        case .bookmark:
            item.label = "Bookmark"; item.image = NSImage(systemSymbolName: "bookmark", accessibilityDescription: nil)
            item.action = #selector(MainWindowController.toggleBookmark(_:)); item.target = target
        case .printDoc:
            item.label = "Print"; item.image = NSImage(systemSymbolName: "printer", accessibilityDescription: nil)
            item.action = #selector(MainWindowController.printDocument(_:)); item.target = target
        default:
            break
        }
        return item
    }
}

private extension NSToolbarItem.Identifier {
    static let newDoc = NSToolbarItem.Identifier("newDoc")
    static let newDrawing = NSToolbarItem.Identifier("newDrawing")
    static let openDoc = NSToolbarItem.Identifier("openDoc")
    static let saveDoc = NSToolbarItem.Identifier("saveDoc")
    static let find = NSToolbarItem.Identifier("find")
    static let replace = NSToolbarItem.Identifier("replace")
    static let comment = NSToolbarItem.Identifier("comment")
    static let bookmark = NSToolbarItem.Identifier("bookmark")
    static let printDoc = NSToolbarItem.Identifier("printDoc")
}
