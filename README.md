# Kevit++

Native macOS editor named for Kevit. Text, code, and drawings.

Built with **Swift + AppKit**, **STTextView** (TextKit 2), and **Tree-sitter** syntax highlighting via the Neon plugin.

## Features (v1.4 Notepad++ Look)

- Classic Notepad++ chrome: grey tab strip, orange active tab accent, orange gutter edge
- Classic icon toolbar (New/Open/Save/Save All/Close/Edit/Find/Zoom/Macro)
- Multi-tab with ×, file icon, right-click tab menu
- Language menu A–Z groups: 40+ languages (Tree-sitter highlight for ~20)
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
