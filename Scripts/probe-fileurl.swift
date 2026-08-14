import AppKit
import WebKit

final class Nav: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    var log: [String] = []
    var done: (() -> Void)?
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        log.append("DIDFINISH \(webView.url?.absoluteString ?? "nil")")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            webView.evaluateJavaScript(
                "({children:document.getElementById('root')?.childElementCount, snpp:typeof window.snppSetScene, href:location.href, text:(document.getElementById('root')?.innerText||'').slice(0,60)})"
            ) { result, error in
                self.log.append("JS \(String(describing: result)) err=\(String(describing: error))")
                self.done?()
            }
        }
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        self.log.append("FAILPROV \(error)")
        self.done?()
    }
    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        log.append("MSG \(message.name) \(message.body)")
    }
}

let dir = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("Resources/Excalidraw")
let index = dir.appendingPathComponent("index.html")
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let nav = Nav()
let config = WKWebViewConfiguration()
config.defaultWebpagePreferences.allowsContentJavaScript = true
config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
config.setValue(true, forKey: "allowUniversalAccessFromFileURLs")
config.userContentController.add(nav, name: "drawingReady")
let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: config)
web.navigationDelegate = nav
let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
win.contentView = web
win.orderFront(nil)
web.loadFileURL(index, allowingReadAccessTo: dir)
DispatchQueue.main.asyncAfter(deadline: .now() + 8) { print("TIMEOUT"); nav.done?() }
nav.done = {
    for line in nav.log { print(line) }
    fflush(stdout)
    exit(0)
}
app.run()
