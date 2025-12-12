import Foundation

/// MCP tool for file metadata retrieval
struct MetaTool: MCPTool {
    static let name = "meta"

    static let description = "Get file metadata via Spotlight."

    static let inputSchema: JSONValue = .object([
        "type": .string("object"),
        "properties": .object([
            "path": .object([
                "type": .string("string"),
                "description": .string("File path")
            ])
        ]),
        "required": .array([.string("path")])
    ])

    /// Schema for CLI schema command
    static let cliSchema = ToolSchema(
        description: "File metadata",
        params: [
            "path": ParamSchema(type: "string", description: "File path", required: true)
        ],
        returns: "Key: value lines"
    )

    private let executor = SpotlightQueryExecutor()

    func execute(args: [String: JSONValue]) async throws -> String {
        guard let path = args["path"]?.stringValue else {
            throw NSError(domain: "spot", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing path parameter"])
        }

        return try executor.metadata(path: path)
    }
}
