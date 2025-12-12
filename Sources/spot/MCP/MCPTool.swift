import Foundation

/// Protocol for MCP tools that can generate their own schema
protocol MCPTool {
    /// Tool name as exposed via MCP
    static var name: String { get }

    /// Tool description for AI consumption
    static var description: String { get }

    /// Input schema as JSONValue for MCP tools/list
    static var inputSchema: JSONValue { get }

    /// Required initializer
    init()

    /// Execute the tool with given arguments
    func execute(args: [String: JSONValue]) async throws -> String
}

extension MCPTool {
    /// Generate MCP tool definition for tools/list
    static var mcpToolDefinition: JSONValue {
        .object([
            "name": .string(name),
            "description": .string(description),
            "inputSchema": inputSchema
        ])
    }
}

/// Schema types for CLI schema command output
struct SpotSchema: Codable {
    let version: String
    let description: String
    let tools: [String: ToolSchema]
    let queryShorthand: [String: String]
    let commonTypes: [String: String]
}

struct ToolSchema: Codable {
    let description: String
    let params: [String: ParamSchema]
    let returns: String
}

struct ParamSchema: Codable {
    let type: String
    let description: String
    let required: Bool
}

struct MCPToolsSchema: Codable {
    let tools: [MCPToolEntry]
}

struct MCPToolEntry: Codable {
    let name: String
    let description: String
    let inputSchema: MCPInputSchema
}

struct MCPInputSchema: Codable {
    let type: String
    let properties: [String: MCPProperty]
    let required: [String]
}

struct MCPProperty: Codable {
    let type: String
    let description: String
}
