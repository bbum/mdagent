import ArgumentParser
import Foundation

@main
struct MDAgent: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mdagent",
        abstract: "Spotlight search for AI - CLI and MCP server",
        discussion: """
            Wraps macOS Spotlight (MDQuery) for efficient file discovery.
            Run as MCP server: mdagent mcp
            Direct query: mdagent search "*.swift"
            """,
        version: "1.0.0",
        subcommands: [Search.self, Count.self, Meta.self, MCP.self, Schema.self],
        defaultSubcommand: Search.self
    )
}

// MARK: - Search Command

struct Search: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Search files via Spotlight"
    )

    @Argument(help: "Query: glob pattern, @name:*.swift, @content:TODO, @kind:folder, @type:UTI, @mod:7 (days), @size:>1M")
    var query: String

    @Option(name: .shortAndLong, help: "Search scope path(s), comma-separated")
    var scope: String?

    @Option(name: .shortAndLong, help: "Max results")
    var limit: Int = 100

    @Option(name: .long, help: "Sort: name|date|size|created (prefix - for desc)")
    var sort: String?

    @Option(name: .shortAndLong, help: "Output format: compact|full|paths|json")
    var format: String = "compact"

    mutating func run() async throws {
        let executor = SpotlightQueryExecutor()
        let parsedQuery = parseQueryShorthand(query)
        let scopes = scope?.split(separator: ",").map(String.init)

        var sortBy: String? = nil
        var descending = true

        if let s = sort {
            let clean: String
            if s.hasPrefix("-") {
                descending = true
                clean = String(s.dropFirst())
            } else {
                descending = false
                clean = s
            }

            switch clean {
            case "name": sortBy = kMDItemFSName as String
            case "date": sortBy = kMDItemContentModificationDate as String
            case "size": sortBy = kMDItemFSSize as String
            case "created": sortBy = kMDItemFSCreationDate as String
            default: sortBy = clean
            }
        }

        let results = try await executor.execute(
            query: parsedQuery,
            scopes: scopes,
            limit: limit,
            sortBy: sortBy,
            descending: descending
        )

        switch format {
        case "paths":
            for r in results { print(r.path) }
        case "full":
            for r in results {
                var parts = [r.path]
                if let kind = r.kind { parts.append("kind:\(kind)") }
                if let size = r.size { parts.append("size:\(size)") }
                if let mod = r.modified {
                    parts.append("mod:\(ISO8601DateFormatter().string(from: mod))")
                }
                print(parts.joined(separator: " | "))
            }
        case "json":
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(results)
            print(String(data: data, encoding: .utf8)!)
        default: // compact
            for r in results { print(r.compact) }
        }
    }
}

// MARK: - Count Command

struct Count: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Count matching files"
    )

    @Argument(help: "Query (same format as search)")
    var query: String

    @Option(name: .shortAndLong, help: "Search scope path(s)")
    var scope: String?

    mutating func run() async throws {
        let executor = SpotlightQueryExecutor()
        let parsedQuery = parseQueryShorthand(query)
        let scopes = scope?.split(separator: ",").map(String.init)

        let count = try await executor.count(query: parsedQuery, scopes: scopes)
        print(count)
    }
}

// MARK: - Meta Command

struct Meta: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Get file metadata"
    )

    @Argument(help: "File path")
    var path: String

    @Flag(name: .shortAndLong, help: "Show all attributes")
    var all: Bool = false

    mutating func run() async throws {
        let expandedPath = (path as NSString).expandingTildeInPath
        guard let mdItem = MDItemCreate(kCFAllocatorDefault, expandedPath as CFString) else {
            throw ValidationError("Could not access file: \(path)")
        }

        if all {
            guard let attrs = MDItemCopyAttributeNames(mdItem) as? [String] else {
                throw ValidationError("Could not read attribute names")
            }
            for attr in attrs.sorted() {
                if let value = MDItemCopyAttribute(mdItem, attr as CFString) {
                    print("\(attr): \(formatValue(value))")
                }
            }
        } else {
            let keyAttrs = [
                kMDItemDisplayName,
                kMDItemKind,
                kMDItemContentType,
                kMDItemFSSize,
                kMDItemContentModificationDate,
                kMDItemFSCreationDate,
                kMDItemLastUsedDate,
                kMDItemWhereFroms,
                kMDItemFinderComment
            ] as [CFString]

            for attr in keyAttrs {
                if let value = MDItemCopyAttribute(mdItem, attr) {
                    let shortKey = (attr as String).replacingOccurrences(of: "kMDItem", with: "")
                    print("\(shortKey): \(formatValue(value))")
                }
            }
        }
    }

    private func formatValue(_ value: Any) -> String {
        switch value {
        case let date as Date:
            return ISO8601DateFormatter().string(from: date)
        case let array as [Any]:
            return array.map { "\($0)" }.joined(separator: ", ")
        case let num as NSNumber:
            return num.stringValue
        default:
            return "\(value)"
        }
    }
}

// MARK: - MCP Command

struct MCP: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mcp",
        abstract: "MCP server mode",
        subcommands: [Run.self, Help.self],
        defaultSubcommand: Run.self
    )

    struct Run: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Run as MCP server (JSON-RPC over stdio)"
        )

        mutating func run() async throws {
            let server = await MCPServer()
            await server.run()
        }
    }

    struct Help: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Show MCP configuration instructions"
        )

        func run() throws {
            let execPath = CommandLine.arguments[0]
            let resolvedPath: String

            if execPath.hasPrefix("/") {
                resolvedPath = execPath
            } else if execPath.contains("/") {
                let cwd = FileManager.default.currentDirectoryPath
                resolvedPath = (cwd as NSString).appendingPathComponent(execPath)
            } else {
                // Search PATH
                if let path = ProcessInfo.processInfo.environment["PATH"] {
                    let dirs = path.split(separator: ":").map(String.init)
                    resolvedPath = dirs.compactMap { dir -> String? in
                        let full = (dir as NSString).appendingPathComponent(execPath)
                        return FileManager.default.isExecutableFile(atPath: full) ? full : nil
                    }.first ?? execPath
                } else {
                    resolvedPath = execPath
                }
            }

            print("""
            mdagent - Spotlight Search for AI

            Provides Spotlight search capabilities via CLI or MCP server.

            Tools provided:
              • search - Search files via Spotlight queries
              • count  - Count matching files
              • meta   - Get file metadata

            === Claude Code Configuration ===

            Add to Claude Code with:

              claude mcp add mdagent -- \(resolvedPath) mcp

            === Claude Desktop Configuration ===

            Add to ~/Library/Application Support/Claude/claude_desktop_config.json:

            {
              "mcpServers": {
                "mdagent": {
                  "command": "\(resolvedPath)",
                  "args": ["mcp"]
                }
              }
            }

            === Query Syntax ===

            Queries support shorthand notation:
              @name:*.swift     - Filename glob pattern
              @content:TODO     - File content search
              @kind:folder      - File kind
              @type:UTI         - Content type (e.g., public.swift-source)
              @tree:UTI         - Content type tree (includes subtypes)
              @mod:N            - Modified within N days
              @created:N        - Created within N days
              @size:>1M         - Size filter (K/M/G units, </> operators)

            Plain text is treated as a filename glob pattern.
            """)
        }
    }
}

// MARK: - Schema Command

struct Schema: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Output tool schema for AI consumption"
    )

    @Flag(name: .long, help: "Pretty-print JSON")
    var pretty: Bool = false

    @Flag(name: .long, help: "Output MCP tools/list format")
    var mcp: Bool = false

    func run() throws {
        let schema = buildSchema()

        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]

        if mcp {
            let mcpSchema = buildMCPSchema()
            let data = try encoder.encode(mcpSchema)
            print(String(data: data, encoding: .utf8)!)
        } else {
            let data = try encoder.encode(schema)
            print(String(data: data, encoding: .utf8)!)
        }
    }

    private func buildSchema() -> MDAgentSchema {
        MDAgentSchema(
            version: "1.0.0",
            description: "Spotlight search for AI",
            tools: [
                "search": ToolSchema(
                    description: "Search files via Spotlight",
                    params: [
                        "q": ParamSchema(type: "string", description: "Query: glob or @name:*.ext @content:text @kind:folder @type:UTI @mod:days @size:>1M", required: true),
                        "in": ParamSchema(type: "string", description: "Scope path(s), comma-sep", required: false),
                        "n": ParamSchema(type: "int", description: "Max results (100)", required: false),
                        "sort": ParamSchema(type: "string", description: "name|date|size|created (-prefix=desc)", required: false),
                        "fmt": ParamSchema(type: "string", description: "compact|full|paths", required: false)
                    ],
                    returns: "Lines: path[|size|date]"
                ),
                "count": ToolSchema(
                    description: "Count matching files",
                    params: [
                        "q": ParamSchema(type: "string", description: "Query", required: true),
                        "in": ParamSchema(type: "string", description: "Scope", required: false)
                    ],
                    returns: "Integer count"
                ),
                "meta": ToolSchema(
                    description: "File metadata",
                    params: [
                        "path": ParamSchema(type: "string", description: "File path", required: true)
                    ],
                    returns: "Key: value lines"
                )
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

    private func buildMCPSchema() -> MCPToolsSchema {
        MCPToolsSchema(tools: [
            MCPTool(
                name: "search",
                description: "Spotlight search. Returns paths matching query.",
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
            MCPTool(
                name: "count",
                description: "Count matching files without returning paths.",
                inputSchema: MCPInputSchema(
                    type: "object",
                    properties: [
                        "q": MCPProperty(type: "string", description: "Query"),
                        "in": MCPProperty(type: "string", description: "Scope path(s)")
                    ],
                    required: ["q"]
                )
            ),
            MCPTool(
                name: "meta",
                description: "Get file metadata via Spotlight.",
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

// MARK: - Schema Types

struct MDAgentSchema: Codable {
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
    let tools: [MCPTool]
}

struct MCPTool: Codable {
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

// MARK: - Query Parser

func parseQueryShorthand(_ input: String) -> String {
    // If it starts with kMD, assume raw query
    if input.hasPrefix("kMD") {
        return input
    }

    var components: [String] = []
    var remaining = input

    let patterns: [(String, (String) -> String)] = [
        ("@name:", { QueryBuilder.filename($0) }),
        ("@content:", { QueryBuilder.content($0) }),
        ("@kind:", { QueryBuilder.kind($0) }),
        ("@type:", { QueryBuilder.contentType($0) }),
        ("@tree:", { QueryBuilder.contentTypeTree($0) }),
        ("@mod:", { parseDateQuery($0, isModified: true) }),
        ("@created:", { parseDateQuery($0, isModified: false) }),
        ("@size:", { parseSizeQuery($0) })
    ]

    for (prefix, builder) in patterns {
        while let range = remaining.range(of: prefix) {
            let afterPrefix = remaining[range.upperBound...]
            let endIndex = afterPrefix.firstIndex(where: { $0 == " " }) ?? afterPrefix.endIndex
            let value = String(afterPrefix[..<endIndex])

            if !value.isEmpty {
                components.append(builder(value))
            }

            let fullRange = range.lowerBound..<(endIndex == afterPrefix.endIndex ? remaining.endIndex : remaining.index(after: endIndex))
            remaining.removeSubrange(fullRange)
        }
    }

    remaining = remaining.trimmingCharacters(in: .whitespaces)
    if !remaining.isEmpty && components.isEmpty {
        components.append(QueryBuilder.filename(remaining))
    } else if !remaining.isEmpty {
        components.append(QueryBuilder.filename(remaining))
    }

    if components.isEmpty {
        return "kMDItemFSName == \"*\""
    }

    return components.count == 1 ? components[0] : "(" + components.joined(separator: " && ") + ")"
}

func parseDateQuery(_ value: String, isModified: Bool) -> String {
    if let days = Int(value) {
        return isModified ? QueryBuilder.modifiedWithinDays(days) : QueryBuilder.createdWithinDays(days)
    }
    return "kMDItemFSName == \"*\""
}

func parseSizeQuery(_ value: String) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespaces)
    var op = ">"
    var sizeStr = trimmed

    if trimmed.hasPrefix(">") {
        op = ">"
        sizeStr = String(trimmed.dropFirst())
    } else if trimmed.hasPrefix("<") {
        op = "<"
        sizeStr = String(trimmed.dropFirst())
    }

    let bytes = parseSizeString(sizeStr)
    return "kMDItemFSSize \(op) \(bytes)"
}

func parseSizeString(_ str: String) -> Int64 {
    let trimmed = str.trimmingCharacters(in: .whitespaces).uppercased()
    var multiplier: Int64 = 1
    var numStr = trimmed

    if trimmed.hasSuffix("K") || trimmed.hasSuffix("KB") {
        multiplier = 1024
        numStr = trimmed.replacingOccurrences(of: "KB", with: "").replacingOccurrences(of: "K", with: "")
    } else if trimmed.hasSuffix("M") || trimmed.hasSuffix("MB") {
        multiplier = 1024 * 1024
        numStr = trimmed.replacingOccurrences(of: "MB", with: "").replacingOccurrences(of: "M", with: "")
    } else if trimmed.hasSuffix("G") || trimmed.hasSuffix("GB") {
        multiplier = 1024 * 1024 * 1024
        numStr = trimmed.replacingOccurrences(of: "GB", with: "").replacingOccurrences(of: "G", with: "")
    } else if trimmed.hasSuffix("B") {
        numStr = String(trimmed.dropLast())
    }

    return (Int64(numStr) ?? 0) * multiplier
}
