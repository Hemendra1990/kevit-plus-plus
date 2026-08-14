import AppKit
import UniformTypeIdentifiers
import WebKit

final class Handler: NSObject, WKURLSchemeHandler {
    let dir: URL
    var log: [String] = []
    init(dir: URL) { self.dir = dir }
    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else { return }
        let relative = url.path.hasPrefix("/") ? String(url.path.dropFirst()) : url.path
        let file = dir.appendingPathComponent(relative)
        log.append("REQ \(relative)")
        guard let data = try? Data(contentsOf: file) else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let mime = file.pathExtension.lowercased() == "html" ? "text/html" : "text/javascript"
        let resp = URLResponse(url: url, mimeType: mime, expectedContentLength: data.count, textEncodingName: "utf-8")
        task.didReceive(resp)
        task.didReceive(data)
        task.didFinish()
    }
    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

final class Nav: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    var log: [String] = []
    var done: (() -> Void)?
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        log.append("DIDFINISH bounds=\(Int(webView.bounds.width))x\(Int(webView.bounds.height)) hidden=\(webView.isHidden)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            webView.evaluateJavaScript(
                "({children:document.getElementById('root')?.childElementCount, snpp:typeof window.snppSetScene, text:(document.getElementById('root')?.innerText||'').slice(0,80)})"
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
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        log.append("MSG \(message.name) \(message.body)")
    }
}

let root = URL(fileURLWithPath: CommandLine.arguments[1])
let dir = root.appendingPathComponent("Resources/Excalidraw")
let mode = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "hidden-zero"

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let handler = Handler(dir: dir)
let nav = Nav()
let config = WKWebViewConfiguration()
config.setURLSchemeHandler(handler, forURLScheme: "snpphost")
config.defaultWebpagePreferences.allowsContentJavaScript = true
config.userContentController.add(nav, name: "drawingReady")

let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
let host = NSView(frame: .zero)
host.translatesAutoresizingMaskIntoConstraints = false
win.contentView!.addSubview(host)
NSLayoutConstraint.activate([
    host.leadingAnchor.constraint(equalTo: win.contentView!.leadingAnchor),
    host.trailingAnchor.constraint(equalTo: win.contentView!.trailingAnchor),
    host.topAnchor.constraint(equalTo: win.contentView!.topAnchor),
    host.bottomAnchor.constraint(equalTo: win.contentView!.bottomAnchor)
])

let web: WKWebView
if mode == "hidden-zero" {
    web = WKWebView(frame: .zero, configuration: config)
    web.translatesAutoresizingMaskIntoConstraints = false
    host.addSubview(web)
    NSLayoutConstraint.activate([
        web.leadingAnchor.constraint(equalTo: host.leadingAnchor),
        web.trailingAnchor.constraint(equalTo: host.trailingAnchor),
        web.topAnchor.constraint(equalTo: host.topAnchor),
        web.bottomAnchor.constraint(equalTo: host.bottomAnchor)
    ])
    web.isHidden = true
    win.orderFront(nil)
    win.contentView?.layoutSubtreeIfNeeded()
    print("PRELOAD bounds=\(Int(web.bounds.width))x\(Int(web.bounds.height)) host=\(Int(host.bounds.width))x\(Int(host.bounds.height))")
    web.isHidden = false
    win.contentView?.layoutSubtreeIfNeeded()
    print("UNHIDE bounds=\(Int(web.bounds.width))x\(Int(web.bounds.height))")
} else {
    web = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: config)
    win.contentView = web
    win.orderFront(nil)
}

web.navigationDelegate = nav
var comps = URLComponents()
comps.scheme = "snpphost"
comps.host = "host"
comps.path = "/index.html"
web.load(URLRequest(url: comps.url!))

let timeout = DispatchWorkItem {
    print("TIMEOUT")
    nav.done?()
}
DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: timeout)
nav.done = {
    timeout.cancel()
    for line in handler.log + nav.log { print(line) }
    fflush(stdout)
    exit(0)
}
app.run()
