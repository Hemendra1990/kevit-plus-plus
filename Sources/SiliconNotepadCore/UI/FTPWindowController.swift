import AppKit

final class FTPWindowController: NSWindowController {
    var onDownloaded: ((String, String, FTPCredentials) -> Void)?
    var onUploadRequest: (() -> (text: String, credentials: FTPCredentials)?)?

    private let hostField = NSTextField(string: "")
    private let portField = NSTextField(string: "21")
    private let userField = NSTextField(string: "")
    private let passField = NSSecureTextField(string: "")
    private let pathField = NSTextField(string: "/")
    private let sftpButton = NSButton(checkboxWithTitle: "SFTP", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")
    private let listingView = NSTextView()

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "FTP / SFTP"
        window.center()
        super.init(window: window)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        guard let content = window?.contentView else { return }
        hostField.placeholderString = "Host"
        userField.placeholderString = "Username"
        pathField.placeholderString = "/remote/path/file.txt"
        sftpButton.target = self
        sftpButton.action = #selector(sftpToggled)

        let listBtn = NSButton(title: "List", target: self, action: #selector(listRemote))
        let openBtn = NSButton(title: "Open / Download", target: self, action: #selector(downloadRemote))
        let saveBtn = NSButton(title: "Save / Upload Active", target: self, action: #selector(uploadRemote))

        listingView.isEditable = false
        listingView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        let scroll = NSScrollView()
        scroll.documentView = listingView
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder

        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Host"), hostField],
            [NSTextField(labelWithString: "Port"), portField],
            [NSTextField(labelWithString: "User"), userField],
            [NSTextField(labelWithString: "Password"), passField],
            [NSTextField(labelWithString: "Remote path"), pathField],
            [NSTextField(labelWithString: ""), sftpButton]
        ])

        let buttons = NSStackView(views: [listBtn, openBtn, saveBtn, statusLabel])
        buttons.orientation = .horizontal
        buttons.spacing = 8

        let stack = NSStackView(views: [grid, buttons, scroll])
        stack.orientation = .vertical
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])
    }

    private func credentials() -> FTPCredentials {
        FTPCredentials(
            host: hostField.stringValue,
            port: Int(portField.stringValue) ?? (sftpButton.state == .on ? 22 : 21),
            username: userField.stringValue,
            password: passField.stringValue,
            useSFTP: sftpButton.state == .on,
            remotePath: pathField.stringValue
        )
    }

    @objc private func sftpToggled() {
        if sftpButton.state == .on, portField.stringValue == "21" {
            portField.stringValue = "22"
        } else if sftpButton.state == .off, portField.stringValue == "22" {
            portField.stringValue = "21"
        }
    }

    @objc private func listRemote() {
        statusLabel.stringValue = "Listing…"
        let creds = credentials()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let listing = try RemoteTransfer.list(credentials: creds)
                DispatchQueue.main.async {
                    self?.listingView.string = listing
                    self?.statusLabel.stringValue = "OK"
                }
            } catch {
                DispatchQueue.main.async {
                    self?.statusLabel.stringValue = error.localizedDescription
                }
            }
        }
    }

    @objc private func downloadRemote() {
        statusLabel.stringValue = "Downloading…"
        let creds = credentials()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let data = try RemoteTransfer.download(credentials: creds)
                let text = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .isoLatin1)
                    ?? ""
                DispatchQueue.main.async {
                    self?.onDownloaded?(text, (creds.remotePath as NSString).lastPathComponent, creds)
                    self?.statusLabel.stringValue = "Downloaded"
                    self?.window?.close()
                }
            } catch {
                DispatchQueue.main.async {
                    self?.statusLabel.stringValue = error.localizedDescription
                }
            }
        }
    }

    @objc private func uploadRemote() {
        guard let request = onUploadRequest?() else {
            statusLabel.stringValue = "No active document"
            return
        }
        statusLabel.stringValue = "Uploading…"
        var creds = request.credentials
        // Prefer form credentials for destination
        creds = credentials()
        let data = request.text.data(using: .utf8) ?? Data()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try RemoteTransfer.upload(credentials: creds, data: data)
                DispatchQueue.main.async {
                    self?.statusLabel.stringValue = "Uploaded"
                }
            } catch {
                DispatchQueue.main.async {
                    self?.statusLabel.stringValue = error.localizedDescription
                }
            }
        }
    }
}
