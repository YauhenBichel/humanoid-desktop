import Foundation

/// The part of TOML that settings and teammate files use: `[table]` headers, `key = value` with basic
/// strings ("..."), multi-line strings ("""..."""), literal strings ('...'), booleans, integers and
/// floats, and `#` comments. Anything else is an error that names the line, so a typo is never ignored.
public enum Toml {
    public typealias Table = [String: Value]

    public enum Value: Equatable {
        case string(String)
        case bool(Bool)
        case number(Double)
        case table(Table)

        public var string: String? { if case .string(let value) = self { return value } else { return nil } }
        public var bool: Bool? { if case .bool(let value) = self { return value } else { return nil } }
        public var table: Table? { if case .table(let value) = self { return value } else { return nil } }
    }

    public struct ParseError: Error, CustomStringConvertible, Equatable {
        public let line: Int
        public let message: String
        public var description: String { "line \(line): \(message)" }
    }

    public static func parse(_ text: String) throws -> Table {
        var root: Table = [:]
        var section: String?
        let lines = text.components(separatedBy: "\n")
        var index = 0
        while index < lines.count {
            let lineNumber = index + 1
            let line = stripComment(lines[index]).trimmingCharacters(in: .whitespaces)
            index += 1
            if line.isEmpty { continue }
            if line.hasPrefix("[") {
                guard line.hasSuffix("]"), !line.hasPrefix("[["), line.count > 2 else {
                    throw ParseError(line: lineNumber, message: "a table header looks like [name]")
                }
                let name = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                guard isBareKey(name) else { throw ParseError(line: lineNumber, message: "unsupported table name \(name)") }
                if root[name] == nil { root[name] = .table([:]) }
                section = name
                continue
            }
            guard let equals = line.firstIndex(of: "=") else {
                throw ParseError(line: lineNumber, message: "expected key = value")
            }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces)
            guard isBareKey(key) else { throw ParseError(line: lineNumber, message: "unsupported key \(key)") }
            var raw = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            if raw.hasPrefix("\"\"\"") {
                // A multi-line string runs until the closing """, possibly on a later line.
                var body = String(raw.dropFirst(3))
                if body.hasPrefix("\n") { body.removeFirst() }
                while !body.contains("\"\"\"") {
                    guard index < lines.count else {
                        throw ParseError(line: lineNumber, message: "a \"\"\" string is not closed")
                    }
                    body += (body.isEmpty ? "" : "\n") + lines[index]
                    index += 1
                }
                let end = body.range(of: "\"\"\"")!
                guard stripComment(String(body[end.upperBound...])).trimmingCharacters(in: .whitespaces).isEmpty else {
                    throw ParseError(line: lineNumber, message: "text after a closing \"\"\"")
                }
                raw = ""
                try set(key, .string(unescape(String(body[..<end.lowerBound]))), in: &root, section: section, line: lineNumber)
                continue
            }
            try set(key, try scalar(raw, line: lineNumber), in: &root, section: section, line: lineNumber)
        }
        return root
    }

    private static func set(_ key: String, _ value: Value, in root: inout Table, section: String?, line: Int) throws {
        if let section {
            var table = root[section]?.table ?? [:]
            guard table[key] == nil else { throw ParseError(line: line, message: "\(key) is set twice") }
            table[key] = value
            root[section] = .table(table)
        } else {
            guard root[key] == nil else { throw ParseError(line: line, message: "\(key) is set twice") }
            root[key] = value
        }
    }

    private static func scalar(_ raw: String, line: Int) throws -> Value {
        if raw.hasPrefix("\"") {
            guard raw.count >= 2, raw.hasSuffix("\""), !raw.dropFirst().dropLast().hasSuffix("\\") || raw.hasSuffix("\\\\\"") else {
                throw ParseError(line: line, message: "a string is not closed")
            }
            return .string(unescape(String(raw.dropFirst().dropLast())))
        }
        if raw.hasPrefix("'") {
            guard raw.count >= 2, raw.hasSuffix("'") else { throw ParseError(line: line, message: "a string is not closed") }
            return .string(String(raw.dropFirst().dropLast()))
        }
        if raw == "true" { return .bool(true) }
        if raw == "false" { return .bool(false) }
        if let number = Double(raw.replacingOccurrences(of: "_", with: "")) { return .number(number) }
        throw ParseError(line: line, message: "unsupported value \(raw)")
    }

    private static func isBareKey(_ key: String) -> Bool {
        !key.isEmpty && key.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
    }

    /// The line without a trailing `# comment`; a # inside a string is kept.
    private static func stripComment(_ line: String) -> String {
        var inBasic = false, inLiteral = false, escaped = false
        for (offset, character) in line.enumerated() {
            if escaped { escaped = false; continue }
            switch character {
            case "\\" where inBasic: escaped = true
            case "\"" where !inLiteral: inBasic.toggle()
            case "'" where !inBasic: inLiteral.toggle()
            case "#" where !inBasic && !inLiteral: return String(line.prefix(offset))
            default: break
            }
        }
        return line
    }

    private static func unescape(_ text: String) -> String {
        var result = "", escaped = false
        for character in text {
            if escaped {
                switch character {
                case "n": result.append("\n")
                case "t": result.append("\t")
                case "\"": result.append("\"")
                case "\\": result.append("\\")
                default: result.append("\\"); result.append(character)
                }
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else {
                result.append(character)
            }
        }
        return result
    }
}
