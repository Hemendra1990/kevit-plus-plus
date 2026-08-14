import AppKit

/// Builds File → Open Recent from NSDocumentController recent URLs.
final class RecentMenuDelegate: NSObject, NSMenuDelegate {
    static let shared = RecentMenuDelegate()

    weak var windowController: MainWindowController?

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let urls = NSDocumentController.shared.recentDocumentURLs
        if urls.isEmpty {
            let empty = NSMenuItem(title: "No Recent Documents", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for url in urls.prefix(15) {
                let item = NSMenuItem(
                    title: url.lastPathComponent,
                    action: #selector(MainWindowController.openRecentDocument(_:)),
                    keyEquivalent: ""
                )
                item.representedObject = url
                item.target = windowController
                item.toolTip = url.path
                menu.addItem(item)
            }
        }
        menu.addItem(NSMenuItem.separator())
        let clear = NSMenuItem(
            title: "Clear Menu",
            action: #selector(NSDocumentController.clearRecentDocuments(_:)),
            keyEquivalent: ""
        )
        clear.target = NSDocumentController.shared
        menu.addItem(clear)
    }
}
