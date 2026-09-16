import Foundation

/// The part of TOML that settings and teammate files use: `[table]` headers and `key = value` lines, with
/// basic strings (`"..."`), multi-line strings (`"""..."""`), literal strings (`'...'`), booleans, numbers and
/// `#` comments. Anything else is an error that names its line, so a typo is never silently ignored.
public enum Toml {
    public typealias Table = [String: Value]

    public enum Value: Equatable, Sendable {
        case string(String)
        case bool(Bool)
        case number(Double)
        case table(Table)

        public var string: String? {
            guard case .string(let value) = self else { return nil }
            return value
        }

        public var table: Table? {
            guard case .table(let value) = self else { return nil }
            return value
        }
    }

    public struct ParseError: Error, Equatable, Sendable, CustomStringConvertible {
        public let line: Int
        public let message: String
        public var description: String { "line \(line): \(message)" }
    }

    public static func parse(_ text: String) throws(ParseError) -> Table {
        var parser = Parser(lines: text.components(separatedBy: "\n"))
        return try parser.parse()
    }
}

private struct Parser {
    let lines: [String]
    private var next = 0
    private var root: Toml.Table = [:]
    private var section: String?

    init(lines: [String]) {
        self.lines = lines
    }

    mutating func parse() throws(Toml.ParseError) -> Toml.Table {
        while next < lines.count {
            let lineNumber = next + 1
            let line = lines[next].trimmingCharacters(in: .whitespaces)
            next += 1
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line.hasPrefix("[") {
                try readHeader(line, lineNumber: lineNumber)
            } else {
                try readAssignment(line, lineNumber: lineNumber)
            }
        }
        return root
    }

    private mutating func readHeader(_ line: String, lineNumber: Int) throws(Toml.ParseError) {
        let header =
            line.split(separator: "#", maxSplits: 1).first.map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        let name = header.dropFirst().dropLast().trimmingCharacters(in: .whitespaces)
        guard header.hasSuffix("]"), !header.hasPrefix("[["), Self.isBareKey(name) else {
            throw Toml.ParseError(line: lineNumber, message: "a table header looks like [name]")
        }
        switch root[name] {
        case nil: root[name] = .table([:])
        case .table: break
        default: throw Toml.ParseError(line: lineNumber, message: "\(name) is already a value, not a table")
        }
        section = name
    }

    private mutating func readAssignment(_ line: String, lineNumber: Int) throws(Toml.ParseError) {
        guard let equals = line.firstIndex(of: "=") else {
            throw Toml.ParseError(line: lineNumber, message: "expected key = value")
        }
        let key = line[..<equals].trimmingCharacters(in: .whitespaces)
        guard Self.isBareKey(key) else {
            throw Toml.ParseError(line: lineNumber, message: "unsupported key \(key)")
        }
        let text = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
        let (value, trailing) = try readValue(text, lineNumber: lineNumber)
        guard trailing.isEmpty || trailing.hasPrefix("#") else {
            throw Toml.ParseError(line: lineNumber, message: "unexpected text after the value: \(trailing)")
        }
        try store(value, at: key, lineNumber: lineNumber)
    }

    /// The value at the start of `text`, and what follows it on its last line.
    private mutating func readValue(_ text: String, lineNumber: Int) throws(Toml.ParseError) -> (Toml.Value, String) {
        if text.hasPrefix("\"\"\"") {
            return try readMultilineString(firstLine: String(text.dropFirst(3)), lineNumber: lineNumber)
        }
        if text.hasPrefix("\"") {
            return try Self.readBasicString(text.dropFirst(), lineNumber: lineNumber)
        }
        if text.hasPrefix("'") {
            let body = text.dropFirst()
            guard let end = body.firstIndex(of: "'") else {
                throw Toml.ParseError(line: lineNumber, message: "a string is not closed")
            }
            return (.string(String(body[..<end])), Self.rest(of: body, after: end))
        }
        let token = String(text.prefix { !$0.isWhitespace && $0 != "#" })
        let trailing = text.dropFirst(token.count).trimmingCharacters(in: .whitespaces)
        switch token {
        case "true": return (.bool(true), trailing)
        case "false": return (.bool(false), trailing)
        default:
            guard let number = Double(token.replacingOccurrences(of: "_", with: "")) else {
                throw Toml.ParseError(line: lineNumber, message: "unsupported value \(text)")
            }
            return (.number(number), trailing)
        }
    }

    private static func readBasicString(
        _ body: Substring,
        lineNumber: Int
    ) throws(Toml.ParseError) -> (Toml.Value, String) {
        var result = ""
        var escaped = false
        var position = body.startIndex
        while position < body.endIndex {
            let character = body[position]
            if escaped {
                result += unescape(character)
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "\"" {
                return (.string(result), rest(of: body, after: position))
            } else {
                result.append(character)
            }
            position = body.index(after: position)
        }
        throw Toml.ParseError(line: lineNumber, message: "a string is not closed")
    }

    private mutating func readMultilineString(
        firstLine: String,
        lineNumber: Int
    ) throws(Toml.ParseError) -> (Toml.Value, String) {
        var pieces: [String] = []
        var current = firstLine
        while true {
            if let close = current.range(of: "\"\"\"") {
                pieces.append(String(current[..<close.lowerBound]))
                let trailing = current[close.upperBound...].trimmingCharacters(in: .whitespaces)
                // A line break right after the opening quotes is not part of the string.
                if pieces.count > 1, pieces[0].isEmpty { pieces.removeFirst() }
                return (.string(Self.unescapeAll(pieces.joined(separator: "\n"))), trailing)
            }
            pieces.append(current)
            guard next < lines.count else {
                throw Toml.ParseError(line: lineNumber, message: "a \"\"\" string is not closed")
            }
            current = lines[next]
            next += 1
        }
    }

    private mutating func store(_ value: Toml.Value, at key: String, lineNumber: Int) throws(Toml.ParseError) {
        guard let section else {
            guard root[key] == nil else { throw Toml.ParseError(line: lineNumber, message: "\(key) is set twice") }
            root[key] = value
            return
        }
        var table = root[section]?.table ?? [:]
        guard table[key] == nil else { throw Toml.ParseError(line: lineNumber, message: "\(key) is set twice") }
        table[key] = value
        root[section] = .table(table)
    }

    private static func isBareKey(_ key: String) -> Bool {
        !key.isEmpty && key.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
    }

    private static func rest(of body: Substring, after position: Substring.Index) -> String {
        body[body.index(after: position)...].trimmingCharacters(in: .whitespaces)
    }

    private static func unescape(_ character: Character) -> String {
        switch character {
        case "n": "\n"
        case "t": "\t"
        case "\"": "\""
        case "\\": "\\"
        default: "\\\(character)"
        }
    }

    private static func unescapeAll(_ text: String) -> String {
        var result = ""
        var escaped = false
        for character in text {
            if escaped {
                result += unescape(character)
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
