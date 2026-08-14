import AppKit

protocol FunctionListViewDelegate: AnyObject {
    func functionList(_ list: FunctionListView, didSelectLine line: Int)
}

final class FunctionListView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    weak var delegate: FunctionListViewDelegate?

    private let scroll = NSScrollView()
    private let table = NSTableView()
    private var symbols: [FunctionSymbol] = []
    private let titleLabel = NSTextField(labelWithString: "Function List")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        titleLabel.font = .boldSystemFont(ofSize: 11)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        column.title = "Symbol"
        column.width = 160
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 20
        table.dataSource = self
        table.delegate = self
        table.allowsEmptySelection = true

        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false

        addSubview(titleLabel)
        addSubview(scroll)
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            scroll.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func applyTheme(_ theme: EditorTheme) {
        layer?.backgroundColor = theme.gutterBackground.cgColor
        titleLabel.textColor = theme.statusForeground
        table.backgroundColor = theme.gutterBackground
        scroll.backgroundColor = theme.gutterBackground
    }

    func reload(text: String) {
        symbols = FunctionListIndexer.symbols(in: text)
        table.reloadData()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        symbols.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("cell")
        let view = (tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView) ?? {
            let cell = NSTableCellView()
            cell.identifier = id
            let field = NSTextField(labelWithString: "")
            field.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            field.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(field)
            cell.textField = field
            NSLayoutConstraint.activate([
                field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                field.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
            return cell
        }()
        let symbol = symbols[row]
        view.textField?.stringValue = "\(symbol.name)  :\(symbol.line)"
        view.textField?.textColor = ThemeManager.shared.current.foreground
        return view
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = table.selectedRow
        guard symbols.indices.contains(row) else { return }
        delegate?.functionList(self, didSelectLine: symbols[row].line)
    }
}
