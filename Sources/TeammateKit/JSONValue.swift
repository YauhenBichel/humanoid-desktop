/// A JSON value, for the parts of a request that are JSON by nature, such as the reply's JSON schema.
/// Everything else in the requests and responses is a typed Codable struct.
public enum JSONValue: Encodable, Equatable, Sendable {
    case string(String)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])

    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .string(let value): try value.encode(to: encoder)
        case .bool(let value): try value.encode(to: encoder)
        case .array(let values): try values.encode(to: encoder)
        case .object(let members): try members.encode(to: encoder)
        }
    }
}

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByBooleanLiteral, ExpressibleByArrayLiteral,
    ExpressibleByDictionaryLiteral
{
    public init(stringLiteral value: String) { self = .string(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }

    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(uniqueKeysWithValues: elements))
    }
}
