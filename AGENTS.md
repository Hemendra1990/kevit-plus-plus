# AGENTS.md

Guidance for coding agents working in this repository. Long-form detail lives in `CLAUDE.md` (architecture notes) and `HANDOFF.md` (session log: feature inventory, fixed bugs, open work) — read those before large changes.

## Project

**Kevit++** — native macOS Notepad++-style editor. Swift + AppKit (not SwiftUI/Electron/Qt), SwiftPM only (no `.xcodeproj`). Editor is **STTextView** (TextKit 2) with Tree-sitter highlighting via the Neon plugin. Drawing tabs embed **Excalidraw** in a `WKWebView` (source in `Scripts/excalidraw-host/`). Plugins run in JavaScriptCore; FTP/SFTP shells out to `curl`. macOS 14+.

## Commands

```bash
./Scripts/bundle-app.sh              # debug build + assemble .build/Kevit++.app
./Scripts/bundle-app.sh release      # release variant
swift build                          # compile only
swift run LogicTests                 # headless test suite
swift run LogicTests --drawing-render  # opt-in canvas render test (needs window server, slow)
```

- Run the binary directly for console output: `.build/Kevit++.app/Contents/MacOS/KevitPlusPlus`
- Rebuild the Excalidraw host only when `Scripts/excalidraw-host/` changes (built output in `Resources/Excalidraw/` is committed): `./Scripts/build-excalidraw.sh`. **Editing `App.jsx` does nothing until this is re-run** — asset filenames are content-hashed.
- Broken launch / stale state: `rm ~/Library/Application\ Support/KevitPlusPlus/LastSession.json`; `pkill -f KevitPlusPlus` before retesting.

### Tests

`Sources/LogicTests/main.swift` is a hand-rolled `@main` executable, **not XCTest**. Assertions are `check("name") { … }` printing `PASS`/`FAIL`; process exits 1 on any failure. No name filter — comment out other checks or the `run*Tests()` calls to isolate one. UI-level tests instantiate `MainWindowController` headlessly after `_ = NSApplication.shared`. Tests must not write the user's real autosave: keep `SessionManager.automaticAutosaveEnabled = false`.

## Architecture

Three SPM targets: `SiliconNotepadCore` (library, all logic/UI) ← `SiliconNotepadPlusPlus` (`@main`, ~15 lines) and `LogicTests`.

- **Single window, many documents.** `MainWindowController` is the god-controller: owns `TabDocumentStore` (`[Document]` + active index), one `EditorViewController`, one `DrawingViewController`, panels, and nearly every `@objc` menu action. `MenuBuilder` builds the whole menu bar in code and needs `setActionTarget(controller)` after the window controller exists.
- `Document` is a plain `NSObject`, **not** `NSDocument`. `AppDelegate.applicationShouldOpenUntitledFile` returns `false` to stop `NSDocumentController` popping an error (Info.plist declares `CFBundleDocumentTypes`).
- `Document.kind` is `.text` or `.drawing`; `.excalidraw` files (or JSON with `"type":"excalidraw"`) open as drawings and save as raw UTF-8/LF, bypassing encoding + EOL normalization.
- Session JSON at `~/Library/Application Support/KevitPlusPlus/LastSession.json` (`SessionManager`): dirty-tab text, per-tab caret/bookmarks/encoding/EOL, panel visibility. Design spec for the in-progress snapshot work: `docs/superpowers/specs/2026-08-14-session-snapshot-design.md`.
- Adding a syntax language: add `LanguageInfo` in `LanguageRegistry.swift` → add the case in `SyntaxService.treeSitterLanguage(for:)` if a grammar exists → otherwise alias in `treeSitterLanguageName(for:)` or return `nil`. The menu regenerates from `LanguageRegistry.categories`.

### The tab-switch invariant (most common source of regressions)

`presentActiveDocument()` calls `editor.rebuildEditor(...)` then sets `editor.string`. STTextView's setter fires `textViewDidChangeText`, which would write the *outgoing* tab's text into the already-switched document. Guard: `suppressEditorSync = true` around programmatic mutation of `editor.string` during a switch; `syncActiveDocumentFromEditor()` bails when set. Regression coverage: `tabswitch-*` checks in LogicTests. Known consequence: undo stack is wiped per tab switch; programmatic edits (Replace All, transforms) are not undoable.

### Drawing canvas

Assets are served via the custom `snpphost://` scheme (`LocalHostSchemeHandler`), not `file://` (ES-module fetches over `file://` need removed private WebKit keys). Paths resolve against the bundle `Resources/` root first (`snpphost://…/Markdown/index.html` → `Resources/Markdown/`), then fall back to `Resources/Excalidraw/` for the drawing host's root-relative asset URLs. Swift↔JS bridge: `window.snppSetScene / snppGetScene / snppSetTheme / snppRefresh / snppExportPNG / snppExportSVG` in `Scripts/excalidraw-host/src/App.jsx`; JS posts back on `drawingReady` / `drawingChanged` / `drawingError`. `SNPP_DEBUG_HOST=1` traces asset requests to stderr. `Scripts/probe-*.swift` are standalone WebKit harnesses (`probe-hierarchy.swift` currently does not compile).

### Markdown preview

`MarkdownPreviewViewController` + `Resources/Markdown/` (markdown-it + highlight.js vendored in `vendor/`, committed). Host files (`index.html`, `markdown.css`, `preview.js`) are edited in place — **no build step**, unlike the Excalidraw host. `Scripts/build-markdown-host.sh` only re-vendors the pinned libraries. The same renderer pipeline (`preview.js`) drives the preview pane, fullscreen preview, and File → Export HTML…, so preview and export are byte-identical — keep it that way (tests assert it via `swift run LogicTests --markdown-render`, opt-in like `--drawing-render`). Theme sync goes through `snppSetTheme`; task lists and `[!NOTE]`-style callouts are small local markdown-it plugins inside `preview.js`.

View modes (`MarkdownViewMode`: code/split/preview) live in `MarkdownSupport.swift` with the `MarkdownDetector` heuristic (weighted rules, threshold 4 — keep it conservative so prose/C/Python don't trip it) and the draggable `MarkdownDividerView` (reused by the comparator window). `MainWindowController.applyMarkdownLayout()` is the single place that rebuilds `splitHost` constraints per mode — hidden views keep constraints in a plain NSView, so visibility changes must go through it, never raw `isHidden` flips. Narrow windows (<760pt effective) flip the split vertical. **Never mutate constraints synchronously from `NSWindow.didResizeNotification`** — during live window dragging it's delivered inside the layout pass and throws `NSInternalInconsistencyException` (this shipped a crash once); defer to the next runloop turn like `splitWindowDidResize` does. `swift run LogicTests --md-stress` (opt-in, window server) replays mode/fullscreen/resize fuzz + live-resize drags. Tests rely on `SessionManager.automaticAutosaveEnabled = false` making `MainWindowController` hermetic — it must guard the launch-time session *read* too, not just writes.

The preview pane is kind-aware: `previewKind(for:)` routes Markdown / HTML / JSON documents to `markdownPreview` / `htmlPreview` / `jsonPreview`; all share the mode bar, divider, and fullscreen machinery. The JSON viewer host lives in `Resources/JsonView/` (edited in place, no build step, same conventions as the Markdown host). `JsonTools.swift` holds the JSON formatter and `JsonDiff` (structural, order-insensitive, `$.path[0]`-style paths). `DiffEngine` is trim + patience anchors + capped LCS — never reintroduce an unbounded n×m DP. The comparator (`CompareWindowController`) shows Text and JSON modes; its test hooks (`recomputeNow`, `setJSONModeForTesting`) exist because the diff path is async. `EditorViewController.replaceDocument` swaps the whole text view for programmatic rewrites because stale attribute ranges crash NSTextStorage (`highlightBrace` clamps for the same reason).

## Landmines

- **`"\r\n"` is one Swift grapheme cluster.** `String.hasSuffix("\n")` is false on CRLF text and `dropLast(2)` eats both characters. Use `NSString.hasSuffix`/`substring` for every EOL check.
- **Do not re-add `window.fullSizeContentView`** — it draws toolbar/tab strip under the title bar. Layout is `window.contentView = root` (a `FileDropView`) with `contentStack` pinned to all edges.
- **STTextView gutter internals are off-limits** (`gutterView.backgroundColor` is `internal`); only `drawSeparator`, `separatorColor`, `textColor`, `selectedLineHighlightColor` are public. Selection highlight color is hardcoded upstream.
- `EncodingDetector` strips BOMs on decode, rewrites on encode, and must check UTF-32 before UTF-16 (UTF-32 LE otherwise passes the 2-byte UTF-16 test).
- Classic toolbar Cut/Copy/Paste/Undo/Redo intentionally target `nil` so they travel the responder chain.
- **Never spread a saved scene's `appState` over Excalidraw's live state key-by-key** — writing `undefined` onto a key it depends on makes it throw and unmount itself (empty `#root`, no error overlay). Use `safeAppState` in `App.jsx`.
- **`snppExportPNG` / `snppExportSVG` return promises** — they need `callAsyncJavaScript`; `evaluateJavaScript` hands back the unresolved promise and casts silently yield `nil`.
- A nested WKWebView renders fine inside `editorHost`; any "paints blank" comment + detached-`NSWindow` workaround you find was a bug, not a constraint.

## Conventions

- No DI framework, no Combine — plain delegates, closures, `NotificationCenter`.
- Commit only when explicitly asked. Never force-push `main`.
- STTextView is GPL/commercial while this app's code is MIT — flag the license question before anything resembling binary redistribution.
