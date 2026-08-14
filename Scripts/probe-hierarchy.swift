import AppKit
import WebKit

final class Nav: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    var done: (() -> Void)?
    var log: [String] = []
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            webView.evaluateJavaScript("document.body.innerText.slice(0,80)") { r, e in
                self.log.append("JS \(String(describing: r))")
                self.done?()
            }
        }
    }
    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        log.append("MSG \(message.body)")
    }
}

let dir = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("Resources/Excalidraw")
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let nav = Nav()
let config = WKWebViewConfiguration()
config.setURLSchemeHandler(LocalDummy(), forURLScheme: "snpphost")
config.defaultWebpagePreferences.allowsContentJavaScript = true
config.userContentController.add(nav, name: "drawingReady")

final class LocalDummy: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        let url = task.request.url!
        let rel = String(url.path.dropFirst())
        let file = dir.appendingPathComponent(rel)
        let data = (try? Data(contentsOf: file)) ?? Data()
        let mime = file.pathExtension == "html" ? "text/html" : (file.pathExtension == "woff2" ? "font/woff2" : "text/javascript")
        let resp = URLResponse(url: url, mimeType: mime, expectedContentLength: data.count, textEncodingName: "utf-8")
        task.didReceive(resp); task.didReceive(data); task.didFinish()
    }
    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

let win = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 1100, height: 720), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
win.title = "PROBE-HIERARCHY"
let root = NSView(frame: .zero)
root.translatesAutoresizingMaskIntoConstraints = false
let stack = NSStackView()
stack.orientation = .vertical
stack.translatesAutoresizingMaskIntoConstraints = false
let top = NSView(); top.translatesAutoresizingMaskIntoConstraints = false
top.heightAnchor.constraint(equalToConstant: 40).isActive = true
let host = NSView(); host.translatesAutoresizingMaskIntoConstraints = false
stack.addArrangedSubview(top)
stack.addArrangedSubview(host)

let web = WKWebView(frame: .zero, configuration: config)
web.translatesAutoresizingMaskIntoConstraints = false
web.navigationDelegate = nav

win.contentView = root
root.addSubview(stack)
root.addSubview(web)
NSLayoutConstraint.activate([
    root.leadingAnchor.constraint(equalTo: win.contentView!.leadingAnchor),
    root.trailingAnchor.constraint(equalTo: win.contentView!.trailingAnchor),
    root.topAnchor.constraint(equalTo: win.contentView!.topAnchor),
    root.bottomAnchor.constraint(equalTo: win.contentView!.bottomAnchor),
    stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
    stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
    stack.topAnchor.constraint(equalTo: root.topAnchor),
    stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
    web.leadingAnchor.constraint(equalTo: host.leadingAnchor),
    web.trailingAnchor.constraint(equalTo: host.trailingAnchor),
    web.topAnchor.constraint(equalTo: host.topAnchor),
    web.bottomAnchor.constraint(equalTo: host.bottomAnchor)
])
win.makeKeyAndOrderFront(nil)
var c = URLComponents(); c.scheme = "snpphost"; c.host = "host"; c.path = "/index.html"
web.load(URLRequest(url: c.url!))

DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) {
    print("WIN webbounds \(Int(web.bounds.width))x\(Int(web.bounds.height))")
    let img = NSImage(size: web.bounds.size)
    img.lockFocus()
    if web.draw(from: web.bounds, to: web.bounds, operation: .copy, fraction: 1) {
        print("DRAW ok")
    } else {
        print("DRAW fail")
    }
    img.unlockFocus()
    let tiff = img.tiffRepresentation
    let rep = tiff.flatMap { NSBitmapImageRep(data: $0) }
    let png = rep?.representation(using: .png, properties: [:])
    try? png?.write(to: URL(fileURLWithPath: "/tmp/probe-hierarchy.png"))
    print("pixels \(rep?.size ?? .zero)")
    if let r = rep {
        var white=0, other=0
        for y in stride(from: 0, to: r.pixelsHigh, by: 8) {
            for x in stride(from: 0, to: r.pixelsWide, by: 8) {
                var p = [Int](repeating: 0, count: 4)
                r.getPixel(&p, atX: x, y: y)
                if p[0]>240 && p[1]>240 && p[2]>240 { white += 1 } else { other += 1 }
            }
        }
        print("sample white=\(white) other=\(other)")
    }
    for line in nav.log { print(line) }
    exit(0)
}
app.run()
