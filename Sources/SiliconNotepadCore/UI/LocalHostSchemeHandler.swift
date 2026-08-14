import AppKit
import UniformTypeIdentifiers
import WebKit

/// Serves the bundled Excalidraw host over a custom `snpphost://` scheme so the
/// page can load its module bundles and assets as same-origin resources.
/// (file:// module fetches require private WebKit keys that newer macOS removes.)
final class LocalHostSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "snpphost"

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        if ProcessInfo.processInfo.environment["SNPP_DEBUG_HOST"] != nil {
            FileHandle.standardError.write(Data("SCHEME-REQ \(task.request.url?.absoluteString ?? "nil")\n".utf8))
        }
        guard
            let url = task.request.url,
            url.scheme == Self.scheme,
            let dir = DrawingViewController.hostDirectory(),
            let file = Self.fileURL(for: url, hostDirectory: dir),
            let data = try? Data(contentsOf: file)
        else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }

        let mime = Self.mimeType(forExtension: file.pathExtension)
        let headers = Self.httpHeaders(mimeType: mime, contentLength: data.count)
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        ) else {
            task.didFailWithError(URLError(.cannotParseResponse))
            return
        }

        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}

    static func mimeType(forExtension ext: String) -> String {
        switch ext.lowercased() {
        case "html", "htm": return "text/html"
        case "js", "mjs": return "text/javascript"
        case "css": return "text/css"
        case "json": return "application/json"
        case "svg": return "image/svg+xml"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "woff2": return "font/woff2"
        case "woff": return "font/woff"
        case "ttf": return "font/ttf"
        case "otf": return "font/otf"
        case "wasm": return "application/wasm"
        case "map": return "application/json"
        default:
            return UTType(filenameExtension: ext)?.preferredMIMEType ?? "application/octet-stream"
        }
    }

    static func httpHeaders(mimeType: String, contentLength: Int) -> [String: String] {
        let needsCharset =
            mimeType.hasPrefix("text/")
            || mimeType == "application/json"
            || mimeType == "application/javascript"
            || mimeType == "text/javascript"
        let contentType = needsCharset ? "\(mimeType); charset=utf-8" : mimeType
        return [
            "Content-Type": contentType,
            "Access-Control-Allow-Origin": "*",
            "Content-Length": "\(contentLength)",
            "Cache-Control": "no-cache"
        ]
    }

    static func fileURL(for request: URL, hostDirectory: URL) -> URL? {
        let path = request.path
        let relative = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard !relative.isEmpty else { return nil }

        let base = hostDirectory.standardizedFileURL
        let file = base.appendingPathComponent(relative).standardizedFileURL
        let basePath = base.path
        let filePath = file.path
        guard filePath == basePath || filePath.hasPrefix(basePath + "/") else {
            return nil
        }
        guard FileManager.default.fileExists(atPath: filePath) else {
            return nil
        }
        return file
    }
}
