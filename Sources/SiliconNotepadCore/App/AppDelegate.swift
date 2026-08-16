import AppKit

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindowController: MainWindowController?

    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MenuBuilder.buildMainMenu(target: nil)

        let controller = MainWindowController()
        mainWindowController = controller
        MenuBuilder.setActionTarget(controller)
        RecentMenuDelegate.shared.windowController = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(themeDidChange),
            name: .themeDidChange,
            object: nil
        )
    }

    /// We manage documents in MainWindowController — block NSDocumentController auto-new.
    public func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        false
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// Unsaved buffers live in the session snapshot — quit without a Save prompt.
    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        mainWindowController?.autosaveSession()
        return .terminateNow
    }

    public func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    public func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        let url = URL(fileURLWithPath: filename)
        mainWindowController?.openFile(at: url)
        return true
    }

    public func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            mainWindowController?.openFile(at: url)
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        mainWindowController?.autosaveSession()
    }

    @objc private func themeDidChange() {
        mainWindowController?.applyTheme()
    }
}
