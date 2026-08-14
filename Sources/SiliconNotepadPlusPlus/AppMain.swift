import AppKit
import SiliconNotepadCore

@main
enum AppMain {
    static func main() {
        UserDefaults.standard.set(false, forKey: "WebKitAcceleratedCompositingEnabled")
        UserDefaults.standard.set(false, forKey: "WebKitAcceleratedDrawingEnabled")
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}
