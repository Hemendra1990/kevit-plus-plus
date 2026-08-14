import AppKit
import UniformTypeIdentifiers
import WebKit

final class Probe: NSObject, WKURLSchemeHandler, WKNavigationDelegate, WKScriptMessageHandler {
    static let scheme = "snpphost"
    let dir: URL
    var log: [String] = []
    var done: (() -> Void)?

    init(dir: URL) { self.dir = dir }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else {
            task.didFailWithError(URLError(.badURL))
            return
        }
        log.append("REQ \(url.absoluteString)")
        let relative = url.path.hasPrefix("/") ? String(url.path.dropFirst()) : url.path
        let file = dir.appendingPathComponent(relative).standardizedFileURL
        guard file.path.hasPrefix(dir.standardizedFileURL.path) else {
            log.append("REJECT \(relative)")
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        guard let data = try? Data(contentsOf: file) else {
            log.append("MISS \(relative)")
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let ext = file.pathExtension.lowercased()
        let mime: String
        switch ext {
        case "html": mime = "text/html"
        case "js", "mjs": mime = "text/javascript"
        case "css": mime = "text/css"
        case "woff2": mime = "font/woff2"
        default: mime = UTType(filenameExtension: ext)?.preferredMIMEType ?? "application/octet-stream"
        }
        let headers = [
            "Content-Type": mime.hasPrefix("text/") || mime.contains("javascript") ? "\(mime); charset=utf-8" : mime,
            "Access-Control-Allow-Origin": "*",
            "Content-Length": "\(data.count)"
        ]
        guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers) else {
            log.append("NOHTTP \(relative)")
            task.didFailWithError(URLError(.cannotParseResponse))
            return
        }
        log.append("OK \(relative) \(mime) \(data.count)")
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        log.append("DIDFINISH")
        webView.evaluateJavaScript(
            """
            ({
              href: location.href,
              root: (document.getElementById('root')||{}).innerHTML?.length || 0,
              scripts: [...document.scripts].map(s => s.src || s.type),
              snpp: typeof window.snppSetScene,
              children: document.getElementById('root') ? document.getElementById('root').childElementCount : -1
            })
            """
        ) { [weak self] result, error in
            self?.log.append("JS \(String(describing: result)) err=\(String(describing: error))")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                webView.evaluateJavaScript(
                    "({ rootLen: (document.getElementById('root')||{}).innerHTML?.length||0, children: document.getElementById('root')?.childElementCount, snpp: typeof window.snppSetScene, lastErr: window.__SNPP_ERR__ })"
                ) { result2, error2 in
                    self?.log.append("JS2 \(String(describing: result2)) err=\(String(describing: error2))")
                    self?.done?()
                }
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        log.append("FAIL \(error.localizedDescription)")
        done?()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        log.append("FAILPROV \(error.localizedDescription) \(error)")
        done?()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        log.append("MSG \(message.name) \(message.body)")
    }
}

let root = URL(fileURLWithPath: CommandLine.arguments[1])
let dir = root.appendingPathComponent("Resources/Excalidraw")
precondition(FileManager.default.fileExists(atPath: dir.appendingPathComponent("index.html").path), "missing host")

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let probe = Probe(dir: dir)
let config = WKWebViewConfiguration()
config.setURLSchemeHandler(probe, forURLScheme: Probe.scheme)
config.defaultWebpagePreferences.allowsContentJavaScript = true
let ucc = config.userContentController
ucc.add(probe, name: "probe")
ucc.addUserScript(WKUserScript(source: """
window.__SNPP_ERR__ = [];
window.addEventListener('error', e => {
  window.__SNPP_ERR__.push(String(e.message)+' @'+e.filename+':'+e.lineno);
  try { webkit.messageHandlers.probe.postMessage('error '+e.message+' '+e.filename); } catch (x) {}
});
window.addEventListener('unhandledrejection', e => {
  window.__SNPP_ERR__.push('rej '+String(e.reason));
  try { webkit.messageHandlers.probe.postMessage('rej '+String(e.reason)); } catch (x) {}
});
const c = console;
['error','warn','log'].forEach(k => {
  const orig = c[k].bind(c);
  c[k] = (...args) => {
    try { webkit.messageHandlers.probe.postMessage(k+' '+args.map(String).join(' ')); } catch (x) {}
    orig(...args);
  };
});
""", injectionTime: .atDocumentStart, forMainFrameOnly: false))

let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: config)
web.navigationDelegate = probe

let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
win.contentView = web
win.orderFront(nil)

var comps = URLComponents()
comps.scheme = Probe.scheme
comps.host = "host"
comps.path = "/index.html"
web.load(URLRequest(url: comps.url!))

let timeout = DispatchWorkItem {
    probe.log.append("TIMEOUT")
    probe.done?()
}
DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: timeout)

probe.done = {
    timeout.cancel()
    for line in probe.log { print(line) }
    fflush(stdout)
    exit(0)
}

app.run()
