# Kevit++

Native macOS editor named for Kevit. Text, code, and drawings.

Built with **Swift + AppKit**, **STTextView** (TextKit 2), and **Tree-sitter** syntax highlighting via the Neon plugin.

## Features (v1.4 Notepad++ Look)

- Classic Notepad++ chrome: grey tab strip, orange active tab accent, orange gutter edge
- Classic icon toolbar (New/Open/Save/Save All/Close/Edit/Find/Zoom/Macro)
- Multi-tab with ×, file icon, right-click tab menu
- Language menu A–Z groups: 40+ languages (Tree-sitter highlight for ~20)
- Markdown preview (⇧⌘V) with live re-render, syntax-highlighted code blocks, styled tables, callouts, checklists, light/dark themes — and Export HTML… that matches the preview exactly
- Markdown modes: Code / Split / Preview (⌥⌘1–3), draggable divider, vertical split on narrow windows, fullscreen preview (⌥⌘F), and automatic Markdown detection for extension-less files
- HTML viewer and JSON tree viewer in the same preview pane (with search, collapse/expand, and type badges)
- Side-by-side comparator with synced scrolling, add/remove/modify highlighting, and structural JSON diffing with change paths (Compare Snippets…, Text/JSON modes)
- Format / Minify / Validate JSON (⌥⌘L, ⌥⌘M)
- Click the empty area of the tab strip to open a new tab
- String Workbench (⌥⌘T): 36 chained string operations — case, lines, regex, affixes, encodings, counts — with live output, undo, and per-step parameters
- Plus all v1.3 features (FTP, plugins, compare, sessions, macros, …)

## Requirements

- macOS 14.0+
- Swift 5.10+ / Xcode 15+ (or Command Line Tools with macOS SDK)

## Build & run

```bash
# Debug build + .app bundle
./Scripts/bundle-app.sh

# Or release
./Scripts/bundle-app.sh release

# Launch
open ".build/Kevit++.app"
```

Build only (no bundle):

```bash
swift build
swift run KevitPlusPlus
```

Run logic tests:

```bash
swift run LogicTests
```

## Keyboard shortcuts

| Action | Shortcut |
| --- | --- |
| New | ⌘N |
| Open | ⌘O |
| Save | ⌘S |
| Save As | ⇧⌘S |
| Close tab | ⌘W |
| Find | ⌘F |
| Replace | ⌘R |
| Find Next | ⌘G |
| Find Previous | ⇧⌘G |
| Go to line | ⌘L |
| Preferences | ⌘, |
| Duplicate line | ⌘D |
| Column mode | ⇧⌘C |
| Document map | ⇧⌘M |
| Function list | ⇧⌘F |
| Markdown: toggle split | ⇧⌘V |
| Markdown: Code / Split / Preview | ⌥⌘1 / ⌥⌘2 / ⌥⌘3 |
| Markdown: fullscreen preview | ⌥⌘F (Esc exits) |
| Format JSON | ⌥⌘L |
| Minify JSON | ⌥⌘M |
| String Workbench | ⌥⌘T |
| Toggle bookmark | ⇧⌘B |
| Playback macro | ⇧⌘P |
| Print | ⌘P |
| Reload from disk | ⇧⌘R |
| Next tab | ⌃Tab |
| Join lines | ⌘J |

## Not in this release

Binary Notepad++ DLL plugin ABI compatibility (Windows-only). JS plugins cover scripting instead.

## Project layout

```
Sources/SiliconNotepadCore/   # AppKit UI, documents, syntax, themes
Sources/SiliconNotepadPlusPlus/  # @main entry
Resources/Info.plist          # Bundle metadata
Resources/AppIcon.icns        # App icon
Scripts/bundle-app.sh         # Assemble .app
```

## License

MIT (app code). Third-party packages retain their own licenses (STTextView is GPL/commercial — review before redistribution).
