import ArgumentParser
import Foundation

struct SchemaCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "schema",
        abstract: "Output tool schema for AI consumption"
    )

    @Flag(name: .long, help: "Pretty-print JSON")
    var pretty: Bool = false

    @Flag(name: .long, help: "Output MCP tools/list format")
    var mcp: Bool = false

    func run() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]

        if mcp {
            let mcpSchema = Self.buildMCPSchema()
            let data = try encoder.encode(mcpSchema)
            print(String(data: data, encoding: .utf8)!)
        } else {
            let schema = Self.buildSchema()
            let data = try encoder.encode(schema)
            print(String(data: data, encoding: .utf8)!)
        }
    }

    /// Build CLI schema from tool definitions
    static func buildSchema() -> SpotSchema {
        SpotSchema(
            version: "1.0.0",
            description: "Spotlight search for AI",
            tools: [
                SearchTool.name: SearchTool.cliSchema,
                MetaTool.name: MetaTool.cliSchema
            ],
            queryShorthand: [
                "@name:*.ext": "Filename glob",
                "@content:text": "Content search",
                "@kind:folder": "File kind",
                "@type:UTI": "Content type (public.swift-source)",
                "@tree:UTI": "Content type tree (includes subtypes)",
                "@mod:N": "Modified within N days",
                "@created:N": "Created within N days",
                "@size:>1M": "Size filter (K/M/G, </> prefix)"
            ],
            commonTypes: [
                "public.source-code": "Any source code",
                "public.swift-source": "Swift",
                "public.python-script": "Python",
                "public.json": "JSON",
                "net.daringfireball.markdown": "Markdown",
                "public.folder": "Directories"
            ]
        )
    }

    /// Build MCP schema from tool definitions
    static func buildMCPSchema() -> MCPToolsSchema {
        MCPToolsSchema(tools: [
            MCPToolEntry(
                name: SearchTool.name,
                description: SearchTool.description,
                inputSchema: MCPInputSchema(
                    type: "object",
                    properties: [
                        "q": MCPProperty(type: "string", description: "Query: glob or @name:*.ext @content:text @kind:folder @type:UTI @mod:days @size:>1M"),
                        "in": MCPProperty(type: "string", description: "Scope path(s), comma-sep"),
                        "n": MCPProperty(type: "integer", description: "Max results (100)"),
                        "sort": MCPProperty(type: "string", description: "name|date|size|created (-prefix=desc)"),
                        "fmt": MCPProperty(type: "string", description: "compact|full|paths")
                    ],
                    required: ["q"]
                )
            ),
            MCPToolEntry(
                name: MetaTool.name,
                description: MetaTool.description,
                inputSchema: MCPInputSchema(
                    type: "object",
                    properties: [
                        "path": MCPProperty(type: "string", description: "File path")
                    ],
                    required: ["path"]
                )
            )
        ])
    }
}
