import AppKit

final class CompareWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let table = NSTableView()
    private var hunks: [DiffHunk] = []

    init(leftTitle: String, rightTitle: String, left: String, right: String) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 560),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Compare — \(leftTitle) ↔ \(rightTitle)"
        window.center()
        super.init(window: window)
        hunks = DiffEngine.diff(left: left, right: right)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        guard let content = window?.contentView else { return }
        let kind = NSTableColumn(identifier: .init("kind")); kind.title = ""; kind.width = 28
        let left = NSTableColumn(identifier: .init("left")); left.title = "Left"; left.width = 60
        let right = NSTableColumn(identifier: .init("right")); right.title = "Right"; right.width = 60
        let text = NSTableColumn(identifier: .init("text")); text.title = "Text"; text.width = 700
        table.addTableColumn(kind)
        table.addTableColumn(left)
        table.addTableColumn(right)
        table.addTableColumn(text)
        table.delegate = self
        table.dataSource = self
        table.rowHeight = 20
        table.usesAlternatingRowBackgroundColors = false

        let scroll = NSScrollView(frame: content.bounds)
        scroll.autoresizingMask = [.width, .height]
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        content.addSubview(scroll)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { hunks.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let hunk = hunks[row]
        let field = NSTextField(labelWithString: "")
        field.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        field.drawsBackground = true
        switch hunk.kind {
        case .same:
            field.backgroundColor = .clear
            field.textColor = .labelColor
        case .added:
            field.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.2)
            field.textColor = .labelColor
        case .removed:
            field.backgroundColor = NSColor.systemRed.withAlphaComponent(0.2)
            field.textColor = .labelColor
        }
        switch tableColumn?.identifier.rawValue {
        case "kind":
            field.stringValue = hunk.kind == .added ? "+" : (hunk.kind == .removed ? "-" : " ")
        case "left":
            field.stringValue = hunk.leftLine.map(String.init) ?? ""
        case "right":
            field.stringValue = hunk.rightLine.map(String.init) ?? ""
        default:
            field.stringValue = hunk.text
        }
        return field
    }
}
