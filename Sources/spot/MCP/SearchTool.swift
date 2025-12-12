import Foundation

/// MCP tool for Spotlight search
struct SearchTool: MCPTool {
    static let name = "search"

    static let description = "Spotlight search. Query: @name:*.swift @content:TODO @kind:folder @type:public.swift-source @mod:7 @size:>1M (or raw MDQuery). fmt: compact|full|paths|count."

    static let inputSchema: JSONValue = .object([
        "type": .string("object"),
        "properties": .object([
            "q": .object([
                "type": .string("string"),
                "description": .string("Query: glob or @name:*.ext @content:text @kind:folder @type:UTI @mod:days @size:>1M")
            ]),
            "in": .object([
                "type": .string("string"),
                "description": .string("Scope path(s), comma-separated")
            ]),
            "n": .object([
                "type": .string("integer"),
                "description": .string("Max results (default: 100)")
            ]),
            "sort": .object([
                "type": .string("string"),
                "description": .string("Sort: name|date|size|created (-prefix for desc)")
            ]),
            "fmt": .object([
                "type": .string("string"),
                "description": .string("Output format: compact|full|paths|count")
            ])
        ]),
        "required": .array([.string("q")])
    ])

    /// Schema for CLI schema command
    static let cliSchema = ToolSchema(
        description: "Search files via Spotlight",
        params: [
            "q": ParamSchema(type: "string", description: "Query: glob or @name:*.ext @content:text @kind:folder @type:UTI @mod:days @size:>1M", required: true),
            "in": ParamSchema(type: "string", description: "Scope path(s), comma-sep", required: false),
            "n": ParamSchema(type: "int", description: "Max results (100)", required: false),
            "sort": ParamSchema(type: "string", description: "name|date|size|created (-prefix=desc)", required: false),
            "fmt": ParamSchema(type: "string", description: "compact|full|paths", required: false)
        ],
        returns: "Lines: path[|size|date]"
    )

    private let executor = SpotlightQueryExecutor()

    func execute(args: [String: JSONValue]) async throws -> String {
        guard let queryInput = args["q"]?.stringValue else {
            throw NSError(domain: "spot", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing query parameter 'q'"])
        }

        let query = parseQueryShorthand(queryInput)
        let scopes = args["in"]?.stringValue?.split(separator: ",").map(String.init)
        let limit = args["n"]?.intValue ?? 100
        let format = args["fmt"]?.stringValue ?? "compact"
        let (sortBy, descending) = parseSortSpec(args["sort"]?.stringValue)

        // Handle count format separately
        if format == "count" {
            let count = try executor.count(query: query, scopes: scopes)
            return "\(count)"
        }

        let results = try executor.execute(
            query: query,
            scopes: scopes,
            limit: limit,
            sortBy: sortBy,
            descending: descending
        )

        return formatResults(results, format: format)
    }
}
