import Foundation

/// Pretty-printing, minification, validation, and — the important part —
/// structural comparison of JSON documents by value, not by text.
public enum JsonFormatter {
    public static func pretty(_ text: String) throws -> String {
        let value = try parse(text)
        return serialize(value, pretty: true, fallback: text)
    }

    public static func minify(_ text: String) throws -> String {
        let value = try parse(text)
        return serialize(value, pretty: false, fallback: text)
    }

    /// Returns nil when valid, or a human-readable error.
    public static func validate(_ text: String) -> String? {
        do {
            _ = try parse(text)
            return nil
        } catch {
            return (error as NSError).localizedDescription
        }
    }

    public static func parse(_ text: String) throws -> Any {
        guard let data = text.data(using: .utf8) else {
            throw NSError(domain: "JsonFormatter", code: 1, userInfo: [NSLocalizedDescriptionKey: "Text is not valid UTF-8."])
        }
        do {
            return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw error
        }
    }

    private static func serialize(_ value: Any, pretty: Bool, fallback: String) -> String {
        var options: JSONSerialization.WritingOptions = [.fragmentsAllowed, .withoutEscapingSlashes]
        if pretty {
            options.insert(.prettyPrinted)
            options.insert(.sortedKeys)
        }
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: options),
              let out = String(data: data, encoding: .utf8) else {
            return fallback
        }
        return out
    }
}

/// A single structural difference between two JSON documents.
public struct JsonDiffChange: Equatable {
    public enum Kind: String, Equatable {
        case added
        case removed
        case changed
        case typeChanged
    }

    public let path: String
    public let kind: Kind
    /// Compact description of the left-side value (nil for `.added`).
    public let left: String?
    /// Compact description of the right-side value (nil for `.removed`).
    public let right: String?
    /// Value type involved, e.g. "string → number" for type changes.
    public let typeDescription: String
}

public enum JsonDiff {
    /// Structural comparison. Object key order is irrelevant; arrays compare
    /// positionally. Returns changes plus canonical (sorted-key, pretty)
    /// renderings so a side-by-side text view lines up with the change list.
    public static func compare(leftText: String, rightText: String) -> (changes: [JsonDiffChange], leftPretty: String, rightPretty: String) {
        let leftValue = try? JsonFormatter.parse(leftText)
        let rightValue = try? JsonFormatter.parse(rightText)
        let leftPretty = leftValue.map { pretty($0) } ?? leftText
        let rightPretty = rightValue.map { pretty($0) } ?? rightText
        guard let l = leftValue, let r = rightValue else { return ([], leftPretty, rightPretty) }
        return (walk(l, r, path: "$"), leftPretty, rightPretty)
    }

    public static func bothValid(_ left: String, _ right: String) -> Bool {
        JsonFormatter.validate(left) == nil && JsonFormatter.validate(right) == nil
    }

    // MARK: - Walk

    private static func walk(_ left: Any, _ right: Any, path: String) -> [JsonDiffChange] {
        let lt = typeName(left)
        let rt = typeName(right)

        if lt == rt {
            switch (left, right) {
            case let (ld as [String: Any], rd as [String: Any]):
                return diffObjects(ld, rd, path: path)
            case let (ld as [Any], rd as [Any]):
                return diffArrays(ld, rd, path: path)
            default:
                if !scalarEqual(left, right) {
                    return [change(path, .changed, describe(left), describe(right), lt)]
                }
                return []
            }
        }

        // Different type categories entirely (object vs array, string vs
        // number, …). Scalar-vs-scalar mismatches are type changes too.
        return [change(path, .typeChanged, describe(left), describe(right), "\(lt) → \(rt)")]
    }

    private static func diffObjects(_ left: [String: Any], _ right: [String: Any], path: String) -> [JsonDiffChange] {
        var out: [JsonDiffChange] = []
        for key in Array(Set(left.keys).union(right.keys)).sorted() {
            let child = path == "$" ? "$.\(key)" : "\(path).\(key)"
            switch (left[key], right[key]) {
            case let (l?, r?):
                out.append(contentsOf: walk(l, r, path: child))
            case let (l?, nil):
                out.append(change(child, .removed, describe(l), nil, typeName(l)))
            case let (nil, r?):
                out.append(change(child, .added, nil, describe(r), typeName(r)))
            default:
                break
            }
        }
        return out
    }

    private static func diffArrays(_ left: [Any], _ right: [Any], path: String) -> [JsonDiffChange] {
        var out: [DiffRow] = []
        let common = min(left.count, right.count)
        for i in 0..<common {
            let child = "\(path)[\(i)]"
            out.append(contentsOf: walk(left[i], right[i], path: child).map { row($0) })
        }
        if left.count > common {
            for i in common..<left.count {
                out.append(row(change("\(path)[\(i)]", .removed, describe(left[i]), nil, typeName(left[i]))))
            }
        }
        if right.count > common {
            for i in common..<right.count {
                out.append(row(change("\(path)[\(i)]", .added, nil, describe(right[i]), typeName(right[i]))))
            }
        }
        return out.map(\.change)
    }

    private struct DiffRow { let change: JsonDiffChange }
    private static func row(_ c: JsonDiffChange) -> DiffRow { DiffRow(change: c) }

    private static func change(
        _ path: String, _ kind: JsonDiffChange.Kind,
        _ left: String?, _ right: String?, _ type: String
    ) -> JsonDiffChange {
        JsonDiffChange(path: path, kind: kind, left: left, right: right, typeDescription: type)
    }

    // MARK: - Scalars

    private static func scalarEqual(_ a: Any, _ b: Any) -> Bool {
        if let sa = a as? String, let sb = b as? String { return sa == sb }
        if a is NSNull, b is NSNull { return true }
        if let na = a as? NSNumber, let nb = b as? NSNumber {
            // Bool bridges through NSNumber too; compare within kind.
            if (a is Bool) != (b is Bool) { return false }
            return na == nb
        }
        return false
    }

    private static func typeName(_ v: Any) -> String {
        switch v {
        case is Bool: return "bool"
        case is NSNumber: return "number"
        case is String: return "string"
        case is NSNull: return "null"
        case is [String: Any]: return "object"
        case is [Any]: return "array"
        default: return "value"
        }
    }

    /// Compact, truncated description for the change list.
    public static func describe(_ v: Any) -> String {
        let full: String
        switch v {
        case is NSNull: full = "null"
        case let s as String: full = "\"\(s)\""
        default:
            let opts: JSONSerialization.WritingOptions = [.fragmentsAllowed, .withoutEscapingSlashes, .sortedKeys]
            if let data = try? JSONSerialization.data(withJSONObject: v, options: opts),
               let s = String(data: data, encoding: .utf8) {
                full = s.replacingOccurrences(of: "\n", with: " ")
            } else {
                full = String(describing: v)
            }
        }
        guard full.count > 80 else { return full }
        return full.prefix(77) + "…"
    }

    private static func pretty(_ value: Any) -> String {
        let opts: JSONSerialization.WritingOptions = [.fragmentsAllowed, .withoutEscapingSlashes, .sortedKeys, .prettyPrinted]
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: opts),
              let s = String(data: data, encoding: .utf8) else { return "" }
        return s
    }
}
