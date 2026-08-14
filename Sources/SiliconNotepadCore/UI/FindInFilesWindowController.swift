import AppKit

final class FindInFilesWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    static let shared = FindInFilesWindowController()

    var onOpenHit: ((FindInFilesHit) -> Void)?

    private let queryField = NSTextField(string: "")
    private let folderField = NSTextField(string: "")
    private let caseButton = NSButton(checkboxWithTitle: "Match case", target: nil, action: nil)
    private let regexButton = NSButton(checkboxWithTitle: "Regex", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")
    private let table = NSTableView()
    private var hits: [FindInFilesHit] = []
    private var searchGeneration = 0

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 420),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Find in Files"
        window.center()
        super.init(window: window)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        guard let content = window?.contentView else { return }
        queryField.placeholderString = "Search"
        folderField.placeholderString = "Folder path"
        folderField.stringValue = NSHomeDirectory()

        let browse = NSButton(title: "Browse…", target: self, action: #selector(browse))
        let search = NSButton(title: "Find All", target: self, action: #selector(runSearch))
        search.keyEquivalent = "\r"

        let colFile = NSTableColumn(identifier: .init("file")); colFile.title = "File"; colFile.width = 220
        let colLine = NSTableColumn(identifier: .init("line")); colLine.title = "Line"; colLine.width = 50
        let colPrev = NSTableColumn(identifier: .init("preview")); colPrev.title = "Preview"; colPrev.width = 400
        table.addTableColumn(colFile)
        table.addTableColumn(colLine)
        table.addTableColumn(colPrev)
        table.delegate = self
        table.dataSource = self
        table.doubleAction = #selector(openSelected)
        table.target = self

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder

        let top = NSStackView(views: [
            labeled("Find:", queryField),
            labeled("In:", folderField),
            browse,
            caseButton,
            regexButton,
            search
        ])
        top.orientation = .horizontal
        top.spacing = 8

        let stack = NSStackView(views: [top, scroll, statusLabel])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            queryField.widthAnchor.constraint(greaterThanOrEqualToConstant: 160),
            folderField.widthAnchor.constraint(greaterThanOrEqualToConstant: 200)
        ])
    }

    private func labeled(_ title: String, _ field: NSTextField) -> NSView {
        let label = NSTextField(labelWithString: title)
        let box = NSStackView(views: [label, field])
        box.orientation = .horizontal
        box.spacing = 4
        return box
    }

    @objc private func browse() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.beginSheetModal(for: window!) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.folderField.stringValue = url.path
        }
    }

    @objc private func runSearch() {
        let root = URL(fileURLWithPath: folderField.stringValue)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            statusLabel.stringValue = "Folder not found: \(root.path)"
            return
        }
        statusLabel.stringValue = "Searching…"
        let query = queryField.stringValue
        let matchCase = caseButton.state == .on
        let regex = regexButton.state == .on
        searchGeneration += 1
        let generation = searchGeneration
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let results = FindInFiles.search(
                query: query,
                root: root,
                matchCase: matchCase,
                useRegex: regex,
                fileExtensions: ["swift", "py", "js", "ts", "tsx", "jsx", "json", "md", "txt", "html", "css", "c", "cpp", "h", "java", "go", "rs", "rb", "php", "yml", "yaml", "toml", "sh"]
            )
            DispatchQueue.main.async { [weak self] in
                guard let self, generation == self.searchGeneration else { return }
                self.hits = results
                self.table.reloadData()
                self.statusLabel.stringValue = "\(results.count) hit(s)"
            }
        }
    }

    @objc private func openSelected() {
        let row = table.clickedRow >= 0 ? table.clickedRow : table.selectedRow
        guard hits.indices.contains(row) else { return }
        onOpenHit?(hits[row])
    }

    func numberOfRows(in tableView: NSTableView) -> Int { hits.count }

    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        let hit = hits[row]
        switch tableColumn?.identifier.rawValue {
        case "file": return hit.fileURL.lastPathComponent
        case "line": return hit.line
        case "preview": return hit.preview
        default: return nil
        }
    }
}
