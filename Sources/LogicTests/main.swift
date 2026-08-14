import Foundation
import AppKit
import WebKit
@testable import SiliconNotepadCore

@main
enum LogicTestsMain {
    static func main() {
        // Opt-in: loads the bundled Excalidraw host in the embedded canvas and waits
        // for it to paint. Needs a window server, so it stays out of the default run.
        if CommandLine.arguments.contains("--drawing-render") {
            runDrawingRenderCheck()
            return
        }

        var failed = 0

        func check(_ name: String, _ condition: () -> Bool) {
            if condition() {
                print("PASS \(name)")
            } else {
                print("FAIL \(name)")
                failed += 1
            }
        }

        var bom = Data([0xEF, 0xBB, 0xBF])
        bom.append(contentsOf: "hello".utf8)
        let detected = EncodingDetector.detect(data: bom)
        check("utf8-bom") { detected?.encoding == .utf8BOM && detected?.text == "hello" }
        check("eol-lf") { EOLStyle.detect(in: "a\nb") == .lf }
        check("eol-crlf") { EOLStyle.detect(in: "a\r\nb") == .crlf }
        check("normalize-crlf") { EncodingDetector.normalizeEOL("a\nb", to: .crlf) == "a\r\nb" }
        check("lang-swift") { LanguageRegistry.shared.languageID(forExtension: "swift") == "swift" }
        check("lang-py") { LanguageRegistry.shared.languageID(forExtension: "py") == "python" }
        check("lang-plain") { LanguageRegistry.shared.languageID(forExtension: "zzz") == "plaintext" }

        let engine = FindMatchEngine(find: "bar", matchCase: true, wholeWord: false, useRegex: false)
        let text = "foo bar baz"
        let match = engine.firstMatch(in: text, from: 0, forward: true)
        check("find-plain") { match != nil && String(text[match!]) == "bar" }

        let regex = FindMatchEngine(find: #"b\w+"#, matchCase: true, wholeWord: false, useRegex: true)
        let rmatch = regex.firstMatch(in: text, from: 0, forward: true)
        check("find-regex") { rmatch != nil && String(text[rmatch!]) == "bar" }

        let dup = TextGeometry.duplicateLine(at: 0, in: "one\ntwo\n")
        check("dup-line") { dup.text.contains("one\none\ntwo\n") || dup.text.hasPrefix("one\none") }

        let col = ColumnSelection(startLine: 1, endLine: 2, startColumn: 1, endColumn: 2)
        let inserted = ColumnEdit.insert("X", selection: col, in: "ab\ncd\n")
        check("col-insert") { inserted.contains("X") }

        let symbols = FunctionListIndexer.symbols(in: "func hello() {}\ndef world():\n  pass\n")
        check("func-list") { symbols.contains(where: { $0.name == "hello" }) && symbols.contains(where: { $0.name == "world" }) }

        let upper = TextTransforms.uppercase("AbC")
        check("upper") { upper == "ABC" }
        let trimmed = TextTransforms.trimTrailingSpaces("a  \nb\t\n")
        check("trim") { trimmed == "a\nb\n" || trimmed.hasPrefix("a\nb") }
        let brace = BraceMatcher.matchingRange(at: 0, in: "(hi)")
        check("brace") { brace == NSRange(location: 0, length: 4) }
        let diff = DiffEngine.diff(left: "a\nb\n", right: "a\nc\n")
        check("diff") { diff.contains(where: { $0.kind == .removed && $0.text == "b" }) && diff.contains(where: { $0.kind == .added && $0.text == "c" }) }

        let joined = TextTransforms.joinLines(at: 0, in: "hello\nworld\n")
        check("join") { joined.text.contains("hello world") }
        let blank = TextTransforms.removeBlankLines("a\n\n\nb\n")
        check("blank") { blank == "a\nb" }
        let info = TextTransforms.characterInfo(at: 0, in: "A")
        check("char") { info?.code == 65 }

        failed += runTabSwitchTests()
        failed += runGapFixTests()
        failed += runDrawingSurfaceTests()

        if failed == 0 {
            print("All logic tests passed.")
        } else {
            print("\(failed) test(s) failed.")
            exit(1)
        }
    }

    static func runTabSwitchTests() -> Int {
        var failed = 0

        func check(_ name: String, _ condition: () -> Bool) {
            if condition() {
                print("PASS \(name)")
            } else {
                print("FAIL \(name)")
                failed += 1
            }
        }

        _ = NSApplication.shared

        let controller = MainWindowController()
        controller.store.closeAll()
        controller.newDocument(nil)

        guard let untitled0 = controller.store.activeDocument else {
            print("FAIL tabswitch-setup: no active document")
            return failed + 1
        }

        // Simulate typing into tab 0.
        controller.editor.applyText("hello", selection: NSRange(location: 5, length: 0))
        check("tabswitch-type-sync") { untitled0.text == "hello" && controller.editor.string == "hello" }

        // A new tab must NOT inherit tab 0's content.
        controller.newDocument(nil)
        let untitled1 = controller.store.documents.last!
        check("tabswitch-new-tab-empty") {
            untitled1.text == "" && controller.editor.string == ""
        }

        // Open two files with distinct content; each tab must keep its own text.
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let aa = dir.appendingPathComponent("aa.txt")
        let bb = dir.appendingPathComponent("bb.txt")
        try? "alpha\nbeta\n".write(to: aa, atomically: true, encoding: .utf8)
        try? "gamma\ndelta\n".write(to: bb, atomically: true, encoding: .utf8)

        controller.openFile(at: aa)
        let docAA = controller.store.documents.last!
        check("tabswitch-open-a") {
            docAA.text == "alpha\nbeta\n" && controller.editor.string == "alpha\nbeta\n"
        }

        controller.openFile(at: bb)
        let docBB = controller.store.documents.last!
        check("tabswitch-open-b") {
            docBB.text == "gamma\ndelta\n" && controller.editor.string == "gamma\ndelta\n"
        }

        // Switch tabs back and forth; contents must stay distinct.
        let idxAA = controller.store.index(of: docAA)!
        let idxBB = controller.store.index(of: docBB)!
        controller.tabBar(controller.tabBar, didSelect: idxAA)
        check("tabswitch-back-a") {
            controller.editor.string == "alpha\nbeta\n"
                && docAA.text == "alpha\nbeta\n"
                && docBB.text == "gamma\ndelta\n"
        }
        controller.tabBar(controller.tabBar, didSelect: idxBB)
        check("tabswitch-back-b") {
            controller.editor.string == "gamma\ndelta\n"
                && docAA.text == "alpha\nbeta\n"
                && docBB.text == "gamma\ndelta\n"
        }

        return failed
    }

    /// End-to-end: does the embedded canvas actually mount Excalidraw and paint?
    /// Structural tests alone passed while the canvas lived in a stray detached window.
    static func runDrawingRenderCheck() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let controller = MainWindowController()
        controller.store.closeAll()
        // Installed before the host loads so load-time console output is captured.
        controller.drawing.webView.configuration.userContentController.addUserScript(
            WKUserScript(
                source: """
                window.__LOG = [];
                ['log','warn','error'].forEach(function (k) {
                  var o = console[k].bind(console);
                  console[k] = function () {
                    try { window.__LOG.push(k + ': ' + Array.prototype.map.call(arguments, String).join(' ')); } catch (e) {}
                    o.apply(console, arguments);
                  };
                });
                window.addEventListener('error', function (e) {
                  window.__LOG.push('ERR ' + e.message + ' @' + e.filename + ':' + e.lineno);
                }, true);
                window.addEventListener('unhandledrejection', function (e) {
                  window.__LOG.push('REJ ' + String((e.reason && (e.reason.stack || e.reason.message)) || e.reason));
                });
                """,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        controller.newDrawing(nil)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        controller.window?.contentView?.layoutSubtreeIfNeeded()

        guard controller.drawing.webView.window === controller.window else {
            print("FAIL render-canvas-in-main-window")
            exit(1)
        }
        print("PASS render-canvas-in-main-window")

        let probe = """
        (function () {
          var root = document.getElementById('root');
          var canvas = document.querySelector('canvas');
          var rect = canvas ? canvas.getBoundingClientRect() : null;
          return JSON.stringify({
            children: root ? root.childElementCount : -1,
            excalidraw: !!document.querySelector('.excalidraw'),
            canvasW: rect ? Math.round(rect.width) : 0,
            canvasH: rect ? Math.round(rect.height) : 0,
            api: typeof window.snppSetScene,
            state: document.readyState,
            log: (window.__LOG || []).slice(0, 12)
          });
        })()
        """

        let deadline = Date().addingTimeInterval(30)
        func poll() {
            controller.drawing.webView.evaluateJavaScript(probe) { result, _ in
                let json = (result as? String) ?? "{}"
                let info = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] ?? [:]
                let mounted = (info["excalidraw"] as? Bool) == true
                let width = (info["canvasW"] as? Int) ?? 0
                let height = (info["canvasH"] as? Int) ?? 0
                if mounted, width > 200, height > 200 {
                    print("PASS render-excalidraw-mounted \(width)x\(height) api=\((info["api"] as? String) ?? "?")")
                    verifyExport(controller: controller)
                    return
                }
                guard Date() < deadline else {
                    print("FAIL render-excalidraw-mounted \(json)")
                    for sub in controller.drawing.webView.subviews {
                        if let label = sub as? NSTextField {
                            print("OVERLAY \(label.stringValue)")
                        }
                    }
                    exit(1)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: poll)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: poll)
        app.run()
    }

    /// One rectangle, so the export has something to draw and the scene round-trip is real.
    private static let sampleScene = """
    {"type":"excalidraw","version":2,"source":"app://kevitplusplus","elements":[{"id":"probe-rect","type":"rectangle","x":100,"y":100,"width":220,"height":140,"angle":0,"strokeColor":"#1e1e1e","backgroundColor":"#ffc9c9","fillStyle":"solid","strokeWidth":2,"strokeStyle":"solid","roughness":1,"opacity":100,"groupIds":[],"frameId":null,"roundness":null,"seed":12345,"version":1,"versionNonce":1,"isDeleted":false,"boundElements":null,"updated":1,"link":null,"locked":false}],"appState":{"gridSize":null,"viewBackgroundColor":"#ffffff"},"files":{}}
    """

    /// Pushes a scene through the real Swift -> JS path, reads it back, then exports.
    private static func verifyExport(controller: MainWindowController) {
        controller.drawing.loadScene(sampleScene)
        let deadline = Date().addingTimeInterval(15)

        func pollScene() {
            controller.drawing.webView.evaluateJavaScript("window.snppGetScene ? window.snppGetScene() : ''") { result, _ in
                let scene = (result as? String) ?? ""
                if scene.contains("probe-rect") {
                    print("PASS render-scene-roundtrip")
                    exportCheck(controller: controller)
                    return
                }
                guard Date() < deadline else {
                    print("FAIL render-scene-roundtrip \(scene.prefix(200))")
                    exit(1)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: pollScene)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: pollScene)
    }

    /// A real PNG/SVG only comes back if the canvas actually rendered in the embedded web view.
    private static func exportCheck(controller: MainWindowController) {
        controller.drawing.exportPNG { data in
            guard let data, data.count > 1000, let image = NSImage(data: data), image.size.width > 50 else {
                print("FAIL render-export-png bytes=\(String(describing: data?.count))")
                exit(1)
            }
            print("PASS render-export-png \(data.count) bytes \(Int(image.size.width))x\(Int(image.size.height))")
            controller.drawing.exportSVG { svg in
                guard let svg, svg.contains("<svg") else {
                    print("FAIL render-export-svg \(String(describing: svg?.prefix(80)))")
                    exit(1)
                }
                print("PASS render-export-svg \(svg.count) chars")
                // Mount fires several onChange events; none of them may dirty the tab.
                if controller.store.activeDocument?.isDirty == true {
                    print("FAIL render-untouched-drawing-clean")
                    exit(1)
                }
                print("PASS render-untouched-drawing-clean")
                print("All drawing render checks passed.")
                exit(0)
            }
        }
    }

    /// The drawing canvas must be embedded in the main window's view hierarchy.
    /// It used to live in a detached 800x600 NSWindow pinned to the screen edge.
    static func runDrawingSurfaceTests() -> Int {
        var failed = 0

        func check(_ name: String, _ condition: () -> Bool) {
            if condition() {
                print("PASS \(name)")
            } else {
                print("FAIL \(name)")
                failed += 1
            }
        }

        _ = NSApplication.shared

        let controller = MainWindowController()
        controller.store.closeAll()
        controller.newDocument(nil)

        check("drawing-text-tab-hides-canvas") {
            controller.editor.view.isHidden == false && controller.drawing.view.isHidden == true
        }

        controller.newDrawing(nil)
        guard controller.store.activeDocument?.kind == .drawing else {
            print("FAIL drawing-setup: active document is not a drawing")
            return failed + 1
        }

        check("drawing-canvas-in-main-window") {
            controller.drawing.webView.window === controller.window
        }
        check("drawing-canvas-descends-from-content") {
            var node: NSView? = controller.drawing.webView
            while let current = node {
                if current === controller.window?.contentView { return true }
                node = current.superview
            }
            return false
        }
        check("drawing-tab-shows-canvas") {
            controller.drawing.view.isHidden == false && controller.editor.view.isHidden == true
        }
        check("drawing-canvas-has-size") {
            controller.window?.contentView?.layoutSubtreeIfNeeded()
            return controller.drawing.view.bounds.width > 100 && controller.drawing.view.bounds.height > 100
        }

        controller.tabBar(controller.tabBar, didSelect: 0)
        check("drawing-switch-back-to-text") {
            controller.editor.view.isHidden == false && controller.drawing.view.isHidden == true
        }

        return failed
    }

    static func runGapFixTests() -> Int {
        var failed = 0

        func check(_ name: String, _ condition: () -> Bool) {
            if condition() {
                print("PASS \(name)")
            } else {
                print("FAIL \(name)")
                failed += 1
            }
        }

        // --- Line ops: no trailing newline must not merge lines ---
        if let m = TextGeometry.moveLine(at: 0, in: "a\r\nb", down: true) {
            print("DEBUG move-down-crlf:", m.text.debugDescription)
        } else {
            print("DEBUG move-down-crlf: nil")
        }
        print("DEBUG sort-crlf:", TextTransforms.sortLines("b\r\na\r\n", descending: false, unique: false).debugDescription)
        check("move-down-no-eol") { TextGeometry.moveLine(at: 0, in: "a\nb", down: true)?.text == "b\na" }
        check("move-up-no-eol") { TextGeometry.moveLine(at: 3, in: "a\nb", down: false)?.text == "b\na" }
        check("move-down-crlf") { TextGeometry.moveLine(at: 0, in: "a\r\nb", down: true)?.text == "b\r\na" }
        check("move-last-line-noop") { TextGeometry.moveLine(at: 2, in: "a\nb\n", down: true) == nil }
        check("transpose-no-eol") { TextTransforms.transposeLine(at: 0, in: "a\nb")?.text == "b\na" }

        // --- CRLF-safe transforms ---
        check("trim-crlf") { TextTransforms.trimTrailingSpaces("a \r\nb \r\n") == "a\r\nb\r\n" }
        check("trim-lf") { TextTransforms.trimTrailingSpaces("a  \nb\t\n") == "a\nb\n" }
        check("sort-crlf") { TextTransforms.sortLines("b\r\na\r\n", descending: false, unique: false) == "a\r\nb\r\n" }
        check("sort-no-eol") { TextTransforms.sortLines("b\na", descending: false, unique: false) == "a\nb" }
        check("removeblank-crlf") { TextTransforms.removeBlankLines("a\r\n\r\nb\r\n") == "a\r\nb" }

        // --- Join lines at EOF ---
        check("join-no-eol") { TextTransforms.joinLines(at: 0, in: "a\nb").text == "a b" }
        check("join-phantom-noop") { TextTransforms.joinLines(at: 2, in: "a\nb\n").text == "a\nb\n" }
        check("join-normal") { TextTransforms.joinLines(at: 0, in: "a\nb\n").text == "a b\n" }

        // --- Encoding / BOM ---
        var bom16le = Data([0xFF, 0xFE])
        bom16le.append("hi".data(using: .utf16LittleEndian)!)
        check("utf16le-open") {
            let d = EncodingDetector.detect(data: bom16le)
            return d?.encoding == .utf16LE && d?.text == "hi"
        }
        var bom16be = Data([0xFE, 0xFF])
        bom16be.append("hi".data(using: .utf16BigEndian)!)
        check("utf16be-open") {
            let d = EncodingDetector.detect(data: bom16be)
            return d?.encoding == .utf16BE && d?.text == "hi"
        }
        var bom32le = Data([0xFF, 0xFE, 0x00, 0x00])
        bom32le.append("hi".data(using: .utf32LittleEndian)!)
        check("utf32le-open") {
            let d = EncodingDetector.detect(data: bom32le)
            return d?.encoding == .utf32LE && d?.text == "hi"
        }
        var bom32be = Data([0x00, 0x00, 0xFE, 0xFF])
        bom32be.append("hi".data(using: .utf32BigEndian)!)
        check("utf32be-open") {
            let d = EncodingDetector.detect(data: bom32be)
            return d?.encoding == .utf32BE && d?.text == "hi"
        }
        check("utf16le-save") {
            let data = EncodingDetector.encode("hi", encoding: .utf16LE)
            return data?.starts(with: [0xFF, 0xFE]) == true && EncodingDetector.detect(data: data!)?.text == "hi"
        }
        check("utf32le-save") {
            let data = EncodingDetector.encode("hi", encoding: .utf32LE)
            return data?.starts(with: [0xFF, 0xFE, 0x00, 0x00]) == true && EncodingDetector.detect(data: data!)?.text == "hi"
        }

        // --- Diff with CRLF ---
        let crlfDiff = DiffEngine.diff(left: "a\r\nb", right: "a\r\nc")
        check("diff-crlf-identical") {
            let same = DiffEngine.diff(left: "a\r\nb", right: "a\r\nb")
            return same.allSatisfy { $0.kind == .same } && same.count == 2
        }
        check("diff-crlf-change") {
            crlfDiff.contains(where: { $0.kind == .removed && $0.text == "b" }) &&
                crlfDiff.contains(where: { $0.kind == .added && $0.text == "c" })
        }

        // --- Find engine: UTF-16 offsets + regex errors + backreferences ---
        check("find-emoji-offset") {
            FindMatchEngine(find: "x", matchCase: true, wholeWord: false, useRegex: false)
                .firstMatch(in: "😀x", from: 2, forward: true) != nil
        }
        check("find-all-emoji-no-dup") {
            FindMatchEngine(find: "a", matchCase: true, wholeWord: false, useRegex: false)
                .allMatches(in: "😀a").count == 1
        }
        check("regex-error") {
            FindMatchEngine(find: "(foo", matchCase: true, wholeWord: false, useRegex: true)
                .regexError() != nil
        }
        check("regex-backref") {
            let engine = FindMatchEngine(find: "(bar)", matchCase: true, wholeWord: false, useRegex: true)
            let text = "bar"
            return engine.replacementString(in: text, match: text.startIndex..<text.endIndex, template: "$1!") == "bar!"
        }

        // --- Find in files: binary skip + excluded dirs ---
        let fifDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: fifDir, withIntermediateDirectories: true)
        let binaryFile = fifDir.appendingPathComponent("bin.dat")
        try? Data("needle\u{0}bytes".utf8).write(to: binaryFile)
        let excluded = fifDir.appendingPathComponent("node_modules")
        try? FileManager.default.createDirectory(at: excluded, withIntermediateDirectories: true)
        try? "needle here\n".write(to: excluded.appendingPathComponent("x.txt"), atomically: true, encoding: .utf8)
        let plainFile = fifDir.appendingPathComponent("ok.txt")
        try? "needle found\n".write(to: plainFile, atomically: true, encoding: .utf8)
        let fifHits = FindInFiles.search(query: "needle", root: fifDir, matchCase: true, useRegex: false, fileExtensions: [])
        let ok = { (u: URL) in u.standardizedFileURL }
        check("fif-binary-skip") { !fifHits.contains { ok($0.fileURL) == ok(binaryFile) } }
        check("fif-exclude-dirs") { !fifHits.contains { $0.fileURL.path.contains("node_modules") } }
        check("fif-finds-plain") { fifHits.contains { ok($0.fileURL) == ok(plainFile) } }

        // --- Session: dirty file-backed text + missing-file restore ---
        let sDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: sDir, withIntermediateDirectories: true)
        let sessionFile = sDir.appendingPathComponent("aa.txt")
        try? "hello".write(to: sessionFile, atomically: true, encoding: .utf8)

        let sController = MainWindowController()
        sController.store.closeAll()
        sController.newDocument(nil)
        sController.openFile(at: sessionFile)
        sController.editor.applyText("hello world", selection: NSRange(location: 11, length: 0))
        let session = sController.captureSession()
        check("session-dirty-text") {
            session.tabs.first(where: { $0.path == sessionFile.path })?.untitledText == "hello world"
        }

        let missing = sDir.appendingPathComponent("missing.txt")
        let restore = EditorSession(
            tabs: [SessionTab(
                path: missing.path,
                untitledText: "restored content",
                languageID: "plaintext",
                encoding: "utf8",
                eol: "lf",
                caret: 0,
                bookmarks: []
            )],
            activeIndex: 0
        )
        let rController = MainWindowController()
        rController.store.closeAll()
        rController.restoreSession(restore)
        let restoredDoc = rController.store.documents.first
        check("restore-missing-file") {
            restoredDoc?.fileURL == missing && restoredDoc?.text == "restored content"
        }

        let untitledRestore = EditorSession(
            tabs: [SessionTab(
                untitledText: "keep me",
                languageID: "plaintext",
                encoding: "UTF-8",
                eol: "Unix (LF)",
                caret: 0,
                bookmarks: []
            )],
            activeIndex: 0
        )
        let uController = MainWindowController()
        uController.store.closeAll()
        uController.restoreSession(untitledRestore)
        check("restore-untitled-dirty") {
            uController.store.documents.first?.text == "keep me"
                && uController.store.documents.first?.isDirty == true
        }

        // --- Drawing documents ---
        check("drawing-empty-json") {
            (try? JSONSerialization.jsonObject(with: Data(Document.emptyDrawingJSON.utf8)) as? [String: Any])?["type"] as? String == "excalidraw"
        }
        let dDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dDir, withIntermediateDirectories: true)
        let drawingURL = dDir.appendingPathComponent("sketch.excalidraw")
        try? Document.emptyDrawingJSON.write(to: drawingURL, atomically: true, encoding: .utf8)
        let openedDrawing = try? Document.open(url: drawingURL)
        check("drawing-open-kind") { openedDrawing?.kind == .drawing }
        check("drawing-open-text") { openedDrawing?.text.contains("\"type\":\"excalidraw\"") == true }

        let typedJSON = dDir.appendingPathComponent("also.json")
        try? Document.emptyDrawingJSON.write(to: typedJSON, atomically: true, encoding: .utf8)
        check("drawing-open-by-type") { (try? Document.open(url: typedJSON))?.kind == .drawing }

        let txtURL = dDir.appendingPathComponent("note.txt")
        try? "hello".write(to: txtURL, atomically: true, encoding: .utf8)
        check("text-open-kind") { (try? Document.open(url: txtURL))?.kind == .text }

        let drawDoc = Document.newUntitledDrawing()
        drawDoc.eol = .crlf
        drawDoc.text = "{\"type\":\"excalidraw\",\"version\":2,\"source\":\"t\",\"elements\":[],\"appState\":{},\"files\":{}}\n"
        let saveURL = dDir.appendingPathComponent("saved.excalidraw")
        try? drawDoc.save(to: saveURL)
        let saved = (try? String(contentsOf: saveURL, encoding: .utf8)) ?? ""
        check("drawing-save-no-crlf") { saved.contains("\r\n") == false && saved.contains("\"type\":\"excalidraw\"") }
        check("drawing-save-utf8") { drawDoc.encoding == .utf8 && drawDoc.isDirty == false }

        let drawSession = EditorSession(
            tabs: [SessionTab(
                untitledText: drawDoc.text,
                languageID: "plaintext",
                encoding: "UTF-8",
                eol: "Unix (LF)",
                caret: 0,
                bookmarks: [],
                kind: "drawing"
            )],
            activeIndex: 0
        )
        let dController = MainWindowController()
        dController.store.closeAll()
        dController.restoreSession(drawSession)
        check("session-untitled-drawing") {
            dController.store.documents.first?.kind == .drawing
                && dController.store.documents.first?.isDirty == true
                && dController.store.documents.first?.text.contains("excalidraw") == true
        }
        dController.newDrawing(nil)
        check("new-drawing-kind") { dController.store.activeDocument?.kind == .drawing }

        check("host-mime-js") { LocalHostSchemeHandler.mimeType(forExtension: "js") == "text/javascript" }
        check("host-mime-woff2") { LocalHostSchemeHandler.mimeType(forExtension: "woff2") == "font/woff2" }
        check("host-mime-html") { LocalHostSchemeHandler.mimeType(forExtension: "html") == "text/html" }
        check("host-cors-header") {
            LocalHostSchemeHandler.httpHeaders(mimeType: "text/javascript", contentLength: 12)["Access-Control-Allow-Origin"] == "*"
        }
        check("host-content-type-js") {
            LocalHostSchemeHandler.httpHeaders(mimeType: "text/javascript", contentLength: 12)["Content-Type"] == "text/javascript; charset=utf-8"
        }
        let hostDir = dDir.appendingPathComponent("Excalidraw")
        try? FileManager.default.createDirectory(at: hostDir.appendingPathComponent("assets"), withIntermediateDirectories: true)
        try? Data("ok".utf8).write(to: hostDir.appendingPathComponent("index.html"))
        try? Data("js".utf8).write(to: hostDir.appendingPathComponent("assets/app.js"))
        check("host-resolve-index") {
            LocalHostSchemeHandler.fileURL(
                for: URL(string: "snpphost://host/index.html")!,
                hostDirectory: hostDir
            )?.lastPathComponent == "index.html"
        }
        check("host-resolve-asset") {
            LocalHostSchemeHandler.fileURL(
                for: URL(string: "snpphost://host/assets/app.js")!,
                hostDirectory: hostDir
            )?.lastPathComponent == "app.js"
        }
        check("host-reject-escape") {
            LocalHostSchemeHandler.fileURL(
                for: URL(string: "snpphost://host/../secret.txt")!,
                hostDirectory: hostDir
            ) == nil
        }
        if let bundled = DrawingViewController.hostDirectory() {
            let html = (try? String(contentsOf: bundled.appendingPathComponent("index.html"), encoding: .utf8)) ?? ""
            check("host-has-loading-placeholder") { html.contains("Loading drawing") }
            check("host-no-crossorigin") { !html.contains("crossorigin") }
        } else {
            check("host-has-loading-placeholder") { false }
            check("host-no-crossorigin") { false }
        }

        check("encode-no-lossy") {
            EncodingDetector.encode("€", encoding: .isoLatin1) == nil
        }

        // --- Macro: typing is recorded ---
        let mController = MainWindowController()
        mController.store.closeAll()
        mController.newDocument(nil)
        MacroRecorder.shared.start()
        mController.editor.applyText("hello", selection: NSRange(location: 5, length: 0))
        MacroRecorder.shared.stop()
        check("macro-typing") {
            MacroRecorder.shared.savedMacro.contains(.insertText("hello"))
        }
        MacroRecorder.shared.savedMacro = []
        MacroRecorder.shared.start()
        MacroRecorder.shared.stop()

        return failed
    }
}
