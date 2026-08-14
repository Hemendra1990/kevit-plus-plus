import AppKit
import STTextView

protocol EditorViewControllerDelegate: AnyObject {
    func editorDidChangeText(_ editor: EditorViewController)
    func editorDidChangeSelection(_ editor: EditorViewController)
}

final class EditorViewController: NSViewController, STTextViewDelegate {
    weak var delegate: EditorViewControllerDelegate?

    private(set) var textView: STTextView!
    private(set) var scrollView: NSScrollView!
    private(set) var currentLanguageID: String = "plaintext"
    private(set) var zoomFactor: CGFloat = 1.0
    var columnModeEnabled = false
    var showsInvisibleCharacters = false
    private var markedRanges: [NSRange] = []
    private var braceHighlightRange: NSRange?
    private var macroSnapshot: String = ""

    var string: String {
        get { textView?.text ?? "" }
        set { textView?.text = newValue }
    }

    var selectedRange: NSRange {
        textView?.textSelection ?? NSRange(location: 0, length: 0)
    }

    override func loadView() {
        view = NSView()
        rebuildEditor(languageID: currentLanguageID)
    }

    func rebuildEditor(languageID: String) {
        currentLanguageID = languageID
        let existing = textView?.text ?? ""
        let selection = textView?.textSelection ?? NSRange(location: 0, length: 0)

        scrollView?.removeFromSuperview()

        scrollView = STTextView.scrollableTextView()
        textView = scrollView.documentView as? STTextView
        textView.delegate = self
        textView.text = existing
        textView.showsLineNumbers = Preferences.shared.showLineNumbers
        textView.highlightSelectedLine = true
        textView.showsInvisibleCharacters = showsInvisibleCharacters
        textView.isHorizontallyResizable = !Preferences.shared.wordWrap
        textView.isVerticallyResizable = true
        applyFontAndTheme()
        attachSyntaxPlugin(languageID: languageID)
        reapplyMarks()

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        let length = (textView.text as NSString?)?.length ?? 0
        if selection.location <= length {
            textView.textSelection = selection
        }
        macroSnapshot = textView.text ?? ""
    }

    func resetMacroSnapshot() {
        macroSnapshot = string
    }

    func applyFontAndTheme() {
        let theme = ThemeManager.shared.current
        let size = Preferences.shared.fontSize * zoomFactor
        textView.font = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        textView.textColor = theme.foreground
        textView.backgroundColor = theme.background
        textView.insertionPointColor = theme.foreground
        textView.selectedLineHighlightColor = theme.lineHighlight
        scrollView.backgroundColor = theme.background
        if let gutter = textView.gutterView {
            gutter.drawSeparator = true
            gutter.textColor = theme.gutterForeground
            gutter.selectedLineTextColor = theme.foreground
            gutter.selectedLineHighlightColor = theme.lineHighlight
            gutter.separatorColor = theme.gutterSeparator
        }

        let paragraph = NSParagraphStyle.default.mutableCopy() as! NSMutableParagraphStyle
        let charWidth = textView.font.maximumAdvancement.width
        paragraph.defaultTabInterval = CGFloat(Preferences.shared.tabWidth) * (charWidth > 0 ? charWidth : 8)
        textView.defaultParagraphStyle = paragraph
        textView.showsLineNumbers = Preferences.shared.showLineNumbers
        textView.isHorizontallyResizable = !Preferences.shared.wordWrap
    }

    func setLanguage(_ languageID: String) {
        guard languageID != currentLanguageID else { return }
        rebuildEditor(languageID: languageID)
    }

    func zoomIn() {
        zoomFactor = min(zoomFactor + 0.1, 3.0)
        applyFontAndTheme()
    }

    func zoomOut() {
        zoomFactor = max(zoomFactor - 0.1, 0.5)
        applyFontAndTheme()
    }

    func zoomReset() {
        zoomFactor = 1.0
        applyFontAndTheme()
    }

    func caretMetrics() -> (line: Int, column: Int, position: Int) {
        let text = textView.text ?? ""
        let location = min(selectedRange.location, (text as NSString).length)
        return (
            TextGeometry.lineNumber(at: location, in: text),
            TextGeometry.column(at: location, in: text),
            location
        )
    }

    func visibleLineRange() -> ClosedRange<Int> {
        let text = string
        let total = max(1, TextGeometry.lineCount(of: text))
        let clip = scrollView.contentView
        let visible = clip.documentVisibleRect
        let lineHeight = max(textView.font.boundingRectForFont.height, 14)
        let first = max(1, Int(visible.minY / lineHeight) + 1)
        let count = max(1, Int(visible.height / lineHeight))
        let last = min(total, first + count)
        return first...last
    }

    func replaceSelected(with replacement: String) {
        let range = selectedRange
        textView.insertText(replacement, replacementRange: range)
    }

    func setSelectedRange(_ range: NSRange) {
        textView.textSelection = range
        textView.scrollRangeToVisible(range)
    }

    func goToLine(_ line: Int) {
        let text = string
        let offset = TextGeometry.offset(line: line, column: 1, in: text)
        setSelectedRange(NSRange(location: offset, length: 0))
    }

    func applyText(_ newText: String, selection: NSRange) {
        string = newText
        let len = (newText as NSString).length
        let loc = min(selection.location, len)
        let length = min(selection.length, max(0, len - loc))
        setSelectedRange(NSRange(location: loc, length: length))
        delegate?.editorDidChangeText(self)
    }

    @discardableResult
    func duplicateCurrentLine() -> Bool {
        let result = TextGeometry.duplicateLine(at: selectedRange.location, in: string)
        applyText(result.text, selection: result.newSelection)
        MacroRecorder.shared.record(.duplicateLine)
        return true
    }

    @discardableResult
    func moveCurrentLine(down: Bool) -> Bool {
        guard let result = TextGeometry.moveLine(at: selectedRange.location, in: string, down: down) else {
            return false
        }
        applyText(result.text, selection: result.newSelection)
        MacroRecorder.shared.record(down ? .moveLineDown : .moveLineUp)
        return true
    }

    func currentColumnSelection() -> ColumnSelection {
        ColumnSelection.from(selection: selectedRange, in: string)
    }

    func insertInColumnMode(_ textToInsert: String) {
        let box = currentColumnSelection()
        let newText = ColumnEdit.insert(textToInsert, selection: box, in: string)
        applyText(newText, selection: NSRange(location: selectedRange.location + textToInsert.utf16.count, length: 0))
        MacroRecorder.shared.record(.insertText(textToInsert))
    }

    func deleteColumnSelection() {
        let box = currentColumnSelection()
        let newText = ColumnEdit.delete(selection: box, in: string)
        let caret = TextGeometry.offset(line: box.ordered.startLine, column: box.ordered.startColumn, in: newText)
        applyText(newText, selection: NSRange(location: caret, length: 0))
    }

    func copyColumnSelection() -> String {
        ColumnEdit.extract(selection: currentColumnSelection(), in: string)
    }

    private func attachSyntaxPlugin(languageID: String) {
        guard let plugin = SyntaxService.makePlugin(for: languageID) else { return }
        textView.addPlugin(plugin)
    }

    func setInvisibleCharacters(_ enabled: Bool) {
        showsInvisibleCharacters = enabled
        textView.showsInvisibleCharacters = enabled
    }

    func markRanges(_ ranges: [NSRange]) {
        markedRanges = ranges
        reapplyMarks()
    }

    func clearMarks() {
        markedRanges = []
        reapplyMarks()
    }

    func highlightBrace(at location: Int) {
        if let old = braceHighlightRange {
            textView.addAttributes([.backgroundColor: NSColor.clear], range: old)
        }
        braceHighlightRange = BraceMatcher.matchingRange(at: location, in: string)
        if let range = braceHighlightRange {
            textView.addAttributes([
                .backgroundColor: NSColor.systemYellow.withAlphaComponent(0.35)
            ], range: range)
        }
    }

    private func reapplyMarks() {
        let full = NSRange(location: 0, length: (string as NSString).length)
        if full.length > 0 {
            textView.addAttributes([.backgroundColor: NSColor.clear], range: full)
        }
        for range in markedRanges {
            textView.addAttributes([
                .backgroundColor: NSColor.systemOrange.withAlphaComponent(0.35)
            ], range: range)
        }
        if let brace = braceHighlightRange {
            textView.addAttributes([
                .backgroundColor: NSColor.systemYellow.withAlphaComponent(0.35)
            ], range: brace)
        }
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        highlightBrace(at: selectedRange.location)
        delegate?.editorDidChangeSelection(self)
    }

    // MARK: - STTextViewDelegate

    func textViewDidChangeText(_ notification: Notification) {
        if MacroRecorder.shared.isRecording {
            recordMacroDelta()
        } else {
            macroSnapshot = string
        }
        delegate?.editorDidChangeText(self)
    }

    /// Records typed/edited deltas while a macro is being recorded.
    private func recordMacroDelta() {
        let old = macroSnapshot
        let new = string
        macroSnapshot = new

        let oldChars = Array(old)
        let newChars = Array(new)
        var prefix = 0
        while prefix < oldChars.count, prefix < newChars.count, oldChars[prefix] == newChars[prefix] {
            prefix += 1
        }
        var suffix = 0
        while suffix < oldChars.count - prefix, suffix < newChars.count - prefix,
              oldChars[oldChars.count - 1 - suffix] == newChars[newChars.count - 1 - suffix] {
            suffix += 1
        }
        let removedCount = oldChars.count - prefix - suffix
        let insertedCount = newChars.count - prefix - suffix
        if removedCount == 0, insertedCount > 0 {
            let inserted = String(newChars[prefix..<(prefix + insertedCount)])
            if inserted == "\n" {
                MacroRecorder.shared.record(.newLine)
            } else {
                MacroRecorder.shared.record(.insertText(inserted))
            }
        } else if removedCount > 0, insertedCount == 0 {
            // Direction is ambiguous from the diff alone — backspace is the dominant case.
            MacroRecorder.shared.record(.deleteBackward)
        }
    }
}
