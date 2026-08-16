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
    /// LCS cell budget: above this, segments fall back to naive alignment so
    /// huge inputs stay fast and bounded instead of allocating an n×m table.
    private static let maxDPCells = 4_000_000

    /// Line diff tuned for real-world sizes: common prefix/suffix are trimmed,
    /// then unique matching lines anchor patience-style recursion; only small
    /// residue segments pay for the O(n·m) LCS table.
    public static func diff(left: String, right: String) -> [DiffHunk] {
        let a = splitLines(left)
        let b = splitLines(right)
        var hunks: [DiffHunk] = []

        // Trim common prefix.
        var start = 0
        while start < a.count, start < b.count, a[start] == b[start] {
            hunks.append(DiffHunk(kind: .same, text: a[start], leftLine: start + 1, rightLine: start + 1))
            start += 1
        }
        // Trim common suffix.
        var endA = a.count, endB = b.count
        var suffix: [DiffHunk] = []
        while endA > start, endB > start, a[endA - 1] == b[endB - 1] {
            suffix.append(DiffHunk(kind: .same, text: a[endA - 1], leftLine: endA, rightLine: endB))
            endA -= 1
            endB -= 1
        }

        let midA = Array(a[start..<endA])
        let midB = Array(b[start..<endB])
        hunks.append(contentsOf: diffSegment(midA, midB, offsetA: start, offsetB: start))
        hunks.append(contentsOf: suffix.reversed())
        return hunks
    }

    private static func diffSegment(_ a: [String], _ b: [String], offsetA: Int, offsetB: Int) -> [DiffHunk] {
        if a.isEmpty {
            return b.enumerated().map { DiffHunk(kind: .added, text: $0.element, leftLine: nil, rightLine: offsetB + $0.offset + 1) }
        }
        if b.isEmpty {
            return a.enumerated().map { DiffHunk(kind: .removed, text: $0.element, leftLine: offsetA + $0.offset + 1, rightLine: nil) }
        }

        // Patience anchors: lines that appear exactly once on each side.
        let anchors = matchingAnchors(a, b)
        if !anchors.isEmpty {
            var hunks: [DiffHunk] = []
            var prevA = 0, prevB = 0
            for (ia, ib) in anchors {
                hunks.append(contentsOf: diffSegment(
                    Array(a[prevA..<ia]), Array(b[prevB..<ib]),
                    offsetA: offsetA + prevA, offsetB: offsetB + prevB
                ))
                hunks.append(DiffHunk(kind: .same, text: a[ia], leftLine: offsetA + ia + 1, rightLine: offsetB + ib + 1))
                prevA = ia + 1
                prevB = ib + 1
            }
            hunks.append(contentsOf: diffSegment(
                Array(a[prevA..<a.count]), Array(b[prevB..<b.count]),
                offsetA: offsetA + prevA, offsetB: offsetB + prevB
            ))
            return hunks
        }

        // No anchors (or degenerate input): LCS for small segments, naive
        // alignment beyond the budget so memory/time stay bounded.
        let cells = (a.count + 1) * (b.count + 1)
        if cells <= maxDPCells {
            return lcs(a, b, offsetA: offsetA, offsetB: offsetB)
        }
        var hunks: [DiffHunk] = []
        let common = min(a.count, b.count)
        for i in 0..<common {
            if a[i] == b[i] {
                hunks.append(DiffHunk(kind: .same, text: a[i], leftLine: offsetA + i + 1, rightLine: offsetB + i + 1))
            } else {
                hunks.append(DiffHunk(kind: .removed, text: a[i], leftLine: offsetA + i + 1, rightLine: nil))
                hunks.append(DiffHunk(kind: .added, text: b[i], leftLine: nil, rightLine: offsetB + i + 1))
            }
        }
        if a.count > common {
            for i in common..<a.count {
                hunks.append(DiffHunk(kind: .removed, text: a[i], leftLine: offsetA + i + 1, rightLine: nil))
            }
        }
        if b.count > common {
            for i in common..<b.count {
                hunks.append(DiffHunk(kind: .added, text: b[i], leftLine: nil, rightLine: offsetB + i + 1))
            }
        }
        return hunks
    }

    /// Longest increasing sequence of line-index pairs where the line text is
    /// unique in both arrays — the classic patience anchor set.
    private static func matchingAnchors(_ a: [String], _ b: [String]) -> [(Int, Int)] {
        var countA: [String: Int] = [:]
        var countB: [String: Int] = [:]
        for line in a { countA[line, default: 0] += 1 }
        for line in b { countB[line, default: 0] += 1 }

        var posInB: [String: Int] = [:]
        for (i, line) in b.enumerated() where countA[line] == 1 && countB[line] == 1 {
            posInB[line] = i
        }
        guard !posInB.isEmpty else { return [] }

        // LIS over the b-indices of unique matched a-lines.
        var pairs: [(Int, Int)] = []
        for (i, line) in a.enumerated() {
            if let j = posInB[line] {
                pairs.append((i, j))
            }
        }
        guard pairs.count > 1 else { return pairs }

        var tails: [Int] = []
        var tailsIndex: [Int] = []
        var prev: [Int] = Array(repeating: -1, count: pairs.count)
        for (k, _) in pairs.enumerated() {
            let value = pairs[k].1
            var lo = 0, hi = tails.count
            while lo < hi {
                let mid = (lo + hi) / 2
                if tails[mid] < value { lo = mid + 1 } else { hi = mid }
            }
            if lo == tails.count {
                tails.append(value)
                tailsIndex.append(k)
            } else {
                tails[lo] = value
                tailsIndex[lo] = k
            }
            prev[k] = lo > 0 ? tailsIndex[lo - 1] : -1
        }
        var k = tailsIndex.last ?? -1
        var chain: [(Int, Int)] = []
        while k >= 0 {
            chain.append(pairs[k])
            k = prev[k]
        }
        return chain.reversed()
    }

    private static func lcs(_ a: [String], _ b: [String], offsetA: Int, offsetB: Int) -> [DiffHunk] {
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
        var stack: [DiffHunk] = []
        var i = n, j = m
        while i > 0 || j > 0 {
            if i > 0, j > 0, a[i - 1] == b[j - 1] {
                stack.append(DiffHunk(kind: .same, text: a[i - 1], leftLine: offsetA + i, rightLine: offsetB + j))
                i -= 1; j -= 1
            } else if j > 0, (i == 0 || dp[i][j - 1] >= dp[i - 1][j]) {
                stack.append(DiffHunk(kind: .added, text: b[j - 1], leftLine: nil, rightLine: offsetB + j))
                j -= 1
            } else if i > 0 {
                stack.append(DiffHunk(kind: .removed, text: a[i - 1], leftLine: offsetA + i, rightLine: nil))
                i -= 1
            }
        }
        return stack.reversed()
    }

    /// Splits on \n and strips a trailing \r so CRLF files don't produce phantom empty lines.
    private static func splitLines(_ text: String) -> [String] {
        text.components(separatedBy: "\n").map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
    }
}
