import Foundation

public struct FunctionSymbol: Equatable {
    public let name: String
    public let line: Int
}

public enum FunctionListIndexer {
    private static let patterns: [NSRegularExpression] = {
        let raw = [
            #"^\s*(?:public|private|internal|fileprivate|open|static|class|mutating|override|\s)*func\s+(\w+)"#,
            #"^\s*(?:export\s+)?(?:async\s+)?function\s+(\w+)"#,
            #"^\s*(?:pub\s+)?(?:async\s+)?fn\s+(\w+)"#,
            #"^\s*(?:public|private|protected|static|\s)*\w+[\w\<\>\[\]\s]*\s+(\w+)\s*\([^;]*\)\s*\{?"#,
            #"^\s*def\s+(\w+)\s*\("#,
            #"^\s*(?:export\s+)?(?:const|let|var)\s+(\w+)\s*=\s*(?:async\s*)?\("#
        ]
        return raw.compactMap { try? NSRegularExpression(pattern: $0, options: []) }
    }()

    public static func symbols(in text: String) -> [FunctionSymbol] {
        let lines = text.components(separatedBy: CharacterSet.newlines)
        var result: [FunctionSymbol] = []
        for (idx, line) in lines.enumerated() {
            let lineNumber = idx + 1
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            for regex in patterns {
                if let match = regex.firstMatch(in: line, options: [], range: range),
                   match.numberOfRanges > 1,
                   let nameRange = Range(match.range(at: 1), in: line) {
                    result.append(FunctionSymbol(name: String(line[nameRange]), line: lineNumber))
                    break
                }
            }
        }
        return result
    }
}
