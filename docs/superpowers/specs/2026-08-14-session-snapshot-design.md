# Session snapshot (unsaved buffers)

Date: 2026-08-14

## Goal

Untitled and dirty tabs survive app quit/crash like Notepad++ session snapshot. Save As still writes a real path anywhere on disk.

## Behavior

- Quit / last window / Cmd+Q: write `LastSession.json`, exit. No Save / Don't Save / Cancel.
- Close one tab: keep Save / Don't Save / Cancel. Don't Save drops that tab from the next snapshot.
- While running: debounce ~2s after edits + ~7s heartbeat. Atomic write to Application Support (`KevitPlusPlus/LastSession.json`).
- Launch: restore tabs, dirty text, drawing JSON, caret, encoding/EOL.
- Empty untitled tabs restore as empty Untitled.
- Corrupt file: existing quarantine path.
- LogicTests must not write the user's real autosave (`SessionManager.automaticAutosaveEnabled = false`).

## Out of scope

- Separate per-tab backup folder
- Preference toggle
- macOS Versions / NSDocument autosave
