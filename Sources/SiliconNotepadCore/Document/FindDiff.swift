import Foundation

public struct FindInFilesHit: Equatable {
    public let fileURL: URL
    public let line: Int
    public let column: Int
    public let preview: String
}

public enum FindInFiles {
    private static let excludedDirectories: Set<String> = [
        "node_modules", ".git", "build", ".venv", "venv", "DerivedData", "dist", "Pods", ".build"
    ]

    public static func search(
        query: String,
        root: URL,
        matchCase: Bool,
        useRegex: Bool,
        fileExtensions: [String],
        maxHits: Int = 500
    ) -> [FindInFilesHit] {
        guard !query.isEmpty else { return [] }
        var hits: [FindInFilesHit] = []
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        let engine = FindMatchEngine(
            find: query,
            matchCase: matchCase,
            wholeWord: false,
            useRegex: useRegex
        )
        let allowed = Set(fileExtensions.map { $0.lowercased() })

        for case let url as URL in enumerator {
            if hits.count >= maxHits { break }
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                if excludedDirectories.contains(url.lastPathComponent) {
                    enumerator.skipDescendants()
                }
                continue
            }
            let ext = url.pathExtension.lowercased()
            if !allowed.isEmpty, !allowed.contains(ext) { continue }
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            guard let data = try? Data(contentsOf: url),
                  !data.contains(0), // skip binary files (NUL bytes)
                  let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
            else { continue }

            let lines = splitLines(text)
            for (idx, line) in lines.enumerated() {
                if hits.count >= maxHits { break }
                if engine.firstMatch(in: line, from: 0, forward: true) != nil {
                    hits.append(FindInFilesHit(
                        fileURL: url,
                        line: idx + 1,
                        column: 1,
                        preview: String(line.prefix(200))
                    ))
                }
            }
        }
        return hits
    }

    /// Splits on \n and strips a trailing \r so CRLF files don't produce phantom empty lines.
    private static func splitLines(_ text: String) -> [String] {
        text.components(separatedBy: "\n").map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
    }
}

public struct DiffHunk: Equatable {
    public enum Kind: Equatable { case same, added, removed }
    public let kind: Kind
    public let text: String
    public let leftLine: Int?
    public let rightLine: Int?
}

public enum DiffEngine {
    /// Myers-lite line LCS diff.
    public static func diff(left: String, right: String) -> [DiffHunk] {
        let a = splitLines(left)
        let b = splitLines(right)
        let n = a.count
        let m = b.count
        var dp = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in 1...max(n, 1) where i <= n {
            for j in 1...max(m, 1) where j <= m {
                if a[i - 1] == b[j - 1] {
                    dp[i][j] = dp[i - 1][j - 1] + 1
                } else {
                    dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
                }
            }
        }
        var hunks: [DiffHunk] = []
        var i = n, j = m
        var stack: [DiffHunk] = []
        while i > 0 || j > 0 {
            if i > 0, j > 0, a[i - 1] == b[j - 1] {
                stack.append(DiffHunk(kind: .same, text: a[i - 1], leftLine: i, rightLine: j))
                i -= 1; j -= 1
            } else if j > 0, (i == 0 || dp[i][j - 1] >= dp[i - 1][j]) {
                stack.append(DiffHunk(kind: .added, text: b[j - 1], leftLine: nil, rightLine: j))
                j -= 1
            } else if i > 0 {
                stack.append(DiffHunk(kind: .removed, text: a[i - 1], leftLine: i, rightLine: nil))
                i -= 1
            }
        }
        hunks = stack.reversed()
        return hunks
    }

    /// Splits on \n and strips a trailing \r so CRLF files don't produce phantom empty lines.
    private static func splitLines(_ text: String) -> [String] {
        text.components(separatedBy: "\n").map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
    }
}
