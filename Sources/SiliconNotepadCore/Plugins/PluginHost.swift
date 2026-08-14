import Foundation
import JavaScriptCore

public struct PluginInfo: Equatable {
    public let id: String
    public let name: String
    public let scriptURL: URL
}

public enum PluginHost {
    public static var pluginsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("\(AppIdentity.supportFolder)/Plugins", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public static func installBundledPluginsIfNeeded() {
        let dest = pluginsDirectory
        let samples: [(String, String)] = [
            ("UppercaseSelection.js", """
            // Kevit++ plugin
            // Must define transform(text, selectionStart, selectionLength, languageID) -> {text, selectionStart, selectionLength}
            function transform(text, selectionStart, selectionLength, languageID) {
              if (selectionLength > 0) {
                const before = text.substring(0, selectionStart);
                const mid = text.substring(selectionStart, selectionStart + selectionLength).toUpperCase();
                const after = text.substring(selectionStart + selectionLength);
                return { text: before + mid + after, selectionStart: selectionStart, selectionLength: selectionLength };
              }
              return { text: text.toUpperCase(), selectionStart: 0, selectionLength: text.length };
            }
            """),
            ("TimestampInsert.js", """
            function transform(text, selectionStart, selectionLength, languageID) {
              const stamp = new Date().toISOString();
              const before = text.substring(0, selectionStart);
              const after = text.substring(selectionStart + selectionLength);
              const out = before + stamp + after;
              return { text: out, selectionStart: selectionStart + stamp.length, selectionLength: 0 };
            }
            """),
            ("StripHTML.js", """
            function transform(text, selectionStart, selectionLength, languageID) {
              const source = selectionLength > 0
                ? text.substring(selectionStart, selectionStart + selectionLength)
                : text;
              const stripped = source.replace(/<[^>]+>/g, '');
              if (selectionLength > 0) {
                const before = text.substring(0, selectionStart);
                const after = text.substring(selectionStart + selectionLength);
                return { text: before + stripped + after, selectionStart: selectionStart, selectionLength: stripped.length };
              }
              return { text: stripped, selectionStart: 0, selectionLength: stripped.length };
            }
            """)
        ]
        for (name, body) in samples {
            let url = dest.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: url.path) {
                try? body.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }

    public static func availablePlugins() -> [PluginInfo] {
        installBundledPluginsIfNeeded()
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: pluginsDirectory,
            includingPropertiesForKeys: nil
        )) ?? []
        return urls
            .filter { $0.pathExtension.lowercased() == "js" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map {
                PluginInfo(
                    id: $0.deletingPathExtension().lastPathComponent,
                    name: $0.deletingPathExtension().lastPathComponent,
                    scriptURL: $0
                )
            }
    }

    public struct Result {
        public let text: String
        public let selection: NSRange
    }

    public static func run(
        plugin: PluginInfo,
        text: String,
        selection: NSRange,
        languageID: String
    ) throws -> Result {
        guard let source = try? String(contentsOf: plugin.scriptURL, encoding: .utf8) else {
            throw NSError(domain: "PluginHost", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot read plugin."])
        }
        guard let context = JSContext() else {
            throw NSError(domain: "PluginHost", code: 2, userInfo: [NSLocalizedDescriptionKey: "JSContext unavailable."])
        }
        var jsError: String?
        context.exceptionHandler = { _, exception in
            jsError = exception?.toString()
        }
        context.evaluateScript(source)
        if let jsError { throw NSError(domain: "PluginHost", code: 3, userInfo: [NSLocalizedDescriptionKey: jsError]) }

        guard let fn = context.objectForKeyedSubscript("transform"), fn.isObject else {
            throw NSError(domain: "PluginHost", code: 4, userInfo: [NSLocalizedDescriptionKey: "Plugin missing transform()."])
        }
        let value = fn.call(withArguments: [
            text,
            selection.location,
            selection.length,
            languageID
        ])
        if let jsError { throw NSError(domain: "PluginHost", code: 5, userInfo: [NSLocalizedDescriptionKey: jsError]) }
        guard let obj = value, let newText = obj.objectForKeyedSubscript("text")?.toString() else {
            throw NSError(domain: "PluginHost", code: 6, userInfo: [NSLocalizedDescriptionKey: "Plugin returned invalid result."])
        }
        let start = Int(obj.objectForKeyedSubscript("selectionStart")?.toInt32() ?? Int32(selection.location))
        let length = Int(obj.objectForKeyedSubscript("selectionLength")?.toInt32() ?? 0)
        return Result(text: newText, selection: NSRange(location: start, length: max(0, length)))
    }
}
