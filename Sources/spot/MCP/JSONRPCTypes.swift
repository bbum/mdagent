import Foundation

// MARK: - JSON-RPC Types

struct JSONRPCRequest: Codable {
    let jsonrpc: String
    let id: RequestID?
    let method: String
    let params: JSONValue?

    enum RequestID: Codable, Sendable {
        case string(String)
        case int(Int)

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let intVal = try? container.decode(Int.self) {
                self = .int(intVal)
            } else if let strVal = try? container.decode(String.self) {
                self = .string(strVal)
            } else {
                throw DecodingError.typeMismatch(RequestID.self, .init(codingPath: decoder.codingPath, debugDescription: "Expected string or int"))
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .string(let s): try container.encode(s)
            case .int(let i): try container.encode(i)
            }
        }
    }
}

struct JSONRPCResponse: Codable {
    let jsonrpc: String
    let id: JSONRPCRequest.RequestID?
    let result: JSONValue?
    let error: JSONRPCError?

    init(id: JSONRPCRequest.RequestID?, result: JSONValue) {
        self.jsonrpc = "2.0"
        self.id = id
        self.result = result
        self.error = nil
    }

    init(id: JSONRPCRequest.RequestID?, error: JSONRPCError) {
        self.jsonrpc = "2.0"
        self.id = id
        self.result = nil
        self.error = error
    }
}

struct JSONRPCError: Codable {
    let code: Int
    let message: String
    let data: JSONValue?

    static func parseError(_ msg: String) -> JSONRPCError {
        JSONRPCError(code: -32700, message: msg, data: nil)
    }

    static func invalidRequest(_ msg: String) -> JSONRPCError {
        JSONRPCError(code: -32600, message: msg, data: nil)
    }

    static func methodNotFound(_ method: String) -> JSONRPCError {
        JSONRPCError(code: -32601, message: "Method not found: \(method)", data: nil)
    }

    static func invalidParams(_ msg: String) -> JSONRPCError {
        JSONRPCError(code: -32602, message: msg, data: nil)
    }

    static func internalError(_ msg: String) -> JSONRPCError {
        JSONRPCError(code: -32603, message: msg, data: nil)
    }
}

// MARK: - JSON Value (dynamic)

enum JSONValue: Codable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let i = try? container.decode(Int.self) {
            self = .int(i)
        } else if let d = try? container.decode(Double.self) {
            self = .double(d)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let arr = try? container.decode([JSONValue].self) {
            self = .array(arr)
        } else if let obj = try? container.decode([String: JSONValue].self) {
            self = .object(obj)
        } else {
            throw DecodingError.typeMismatch(JSONValue.self, .init(codingPath: decoder.codingPath, debugDescription: "Unknown JSON type"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let b): try container.encode(b)
        case .int(let i): try container.encode(i)
        case .double(let d): try container.encode(d)
        case .string(let s): try container.encode(s)
        case .array(let arr): try container.encode(arr)
        case .object(let obj): try container.encode(obj)
        }
    }

    var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    var intValue: Int? {
        if case .int(let i) = self { return i }
        return nil
    }

    var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }

    var arrayValue: [JSONValue]? {
        if case .array(let a) = self { return a }
        return nil
    }

    var objectValue: [String: JSONValue]? {
        if case .object(let o) = self { return o }
        return nil
    }

    subscript(key: String) -> JSONValue? {
        if case .object(let obj) = self {
            return obj[key]
        }
        return nil
    }
}
