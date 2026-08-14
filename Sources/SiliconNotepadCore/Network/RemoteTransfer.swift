import Foundation

public struct FTPCredentials {
    public var host: String
    public var port: Int
    public var username: String
    public var password: String
    public var useSFTP: Bool
    public var remotePath: String

    public init(
        host: String,
        port: Int = 21,
        username: String,
        password: String,
        useSFTP: Bool = false,
        remotePath: String = "/"
    ) {
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.useSFTP = useSFTP
        self.remotePath = remotePath
    }
}

public enum RemoteTransferError: LocalizedError {
    case curlFailed(String)
    case emptyResponse

    public var errorDescription: String? {
        switch self {
        case .curlFailed(let msg): return msg
        case .emptyResponse: return "Empty response from server."
        }
    }
}

/// Uses system `curl` for FTP/SFTP so we stay dependency-light on macOS.
public enum RemoteTransfer {
    public static func download(credentials: FTPCredentials) throws -> Data {
        let url = remoteURL(credentials)
        let args = baseArgs(credentials) + ["-sS", url]
        let (status, stdout, stderr) = runCurl(args)
        guard status == 0 else {
            throw RemoteTransferError.curlFailed(stderr.isEmpty ? "Download failed (\(status))" : stderr)
        }
        // A legitimately empty file produces empty stdout — only fail on a non-zero exit status.
        return stdout
    }

    public static func upload(credentials: FTPCredentials, data: Data) throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try data.write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let url = remoteURL(credentials)
        let args = baseArgs(credentials) + ["-sS", "-T", tmp.path, url]
        let (status, _, stderr) = runCurl(args)
        guard status == 0 else {
            throw RemoteTransferError.curlFailed(stderr.isEmpty ? "Upload failed (\(status))" : stderr)
        }
    }

    public static func list(credentials: FTPCredentials) throws -> String {
        var listCreds = credentials
        if !listCreds.remotePath.hasSuffix("/") {
            listCreds.remotePath += "/"
        }
        let url = remoteURL(listCreds)
        let args = baseArgs(listCreds) + ["-sS", "-l", url]
        let (status, stdout, stderr) = runCurl(args)
        guard status == 0 else {
            throw RemoteTransferError.curlFailed(stderr.isEmpty ? "List failed (\(status))" : stderr)
        }
        return String(data: stdout, encoding: .utf8) ?? ""
    }

    private static func remoteURL(_ c: FTPCredentials) -> String {
        let scheme = c.useSFTP ? "sftp" : "ftp"
        let path = c.remotePath.hasPrefix("/") ? c.remotePath : "/" + c.remotePath
        let user = percentEncode(c.username)
        let pass = percentEncode(c.password)
        return "\(scheme)://\(user):\(pass)@\(c.host):\(c.port)\(path)"
    }

    private static func baseArgs(_ c: FTPCredentials) -> [String] {
        var args = ["--connect-timeout", "15", "--max-time", "120"]
        if c.useSFTP {
            args += ["-k"] // allow unknown host keys for simplicity
        }
        return args
    }

    private static func percentEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func runCurl(_ args: [String]) -> (Int32, Data, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        process.arguments = args
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return (1, Data(), error.localizedDescription)
        }
        let stdout = out.fileHandleForReading.readDataToEndOfFile()
        let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (process.terminationStatus, stdout, stderr)
    }
}
