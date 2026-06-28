import Foundation

enum JSONValue: Decodable, Sendable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    var stringValue: String? {
        switch self {
        case .string(let value): value
        case .number(let value): value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int64(value)) : String(value)
        case .bool(let value): String(value)
        case .null, .array, .object: nil
        }
    }

    var uint32Value: UInt32 {
        switch self {
        case .number(let value): UInt32(max(0, value))
        case .string(let value): UInt32(value.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        case .bool(let value): value ? 1 : 0
        case .null, .array, .object: 0
        }
    }

    var int64Value: Int64? {
        switch self {
        case .number(let value): Int64(value)
        case .string(let value): Int64(value.trimmingCharacters(in: .whitespacesAndNewlines))
        case .bool, .null, .array, .object: nil
        }
    }

    var boolValue: Bool {
        switch self {
        case .bool(let value):
            return value
        case .number(let value):
            return value != 0
        case .string(let value):
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return ["1", "true", "yes", "y"].contains(normalized)
        case .null, .array, .object:
            return false
        }
    }

    var stringArrayValue: [String] {
        switch self {
        case .array(let values):
            values.compactMap(\.stringValue).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        case .string(let value):
            value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? [] : [value]
        case .number, .bool:
            stringValue.map { [$0] } ?? []
        case .null, .object:
            []
        }
    }

    func value(for key: String) -> JSONValue? {
        guard case .object(let object) = self else { return nil }
        return object[key]
    }

    func decoded<T: Decodable>(_ type: T.Type, decoder: JSONDecoder = JSONDecoder()) throws -> T {
        let object = FoundationObjectBuilder.object(from: self)
        let data = try JSONSerialization.data(withJSONObject: object)
        return try decoder.decode(type, from: data)
    }
}

private enum FoundationObjectBuilder {
    static func object(from value: JSONValue) -> Any {
        switch value {
        case .object(let object): object.mapValues { Self.object(from: $0) }
        case .array(let array): array.map { Self.object(from: $0) }
        case .string(let value): value
        case .number(let value): value
        case .bool(let value): value
        case .null: NSNull()
        }
    }
}
