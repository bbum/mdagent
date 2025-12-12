import ArgumentParser
import Foundation

struct MCPCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mcp",
        abstract: "MCP server mode",
        subcommands: [Run.self, Help.self],
        defaultSubcommand: Run.self
    )

    struct Run: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Run as MCP server (JSON-RPC over stdio)",
            discussion: """
                By default, all tools are enabled: search, meta

                Optionally specify tool names to enable only those tools:
                  spot mcp search        # Only search tool
                  spot mcp meta          # Only meta tool
                  spot mcp search meta   # Both tools (same as default)
                """
        )

        @Argument(help: "Tools to enable (default: all). Valid: search, meta")
        var tools: [String] = []

        mutating func run() async throws {
            let allTools = MCPTools.allNames
            let enabledTools: Set<String>

            if tools.isEmpty {
                enabledTools = allTools
            } else {
                let specified = Set(tools.map { $0.lowercased() })
                let invalid = specified.subtracting(allTools)
                if !invalid.isEmpty {
                    throw ValidationError("Unknown tools: \(invalid.sorted().joined(separator: ", ")). Valid: \(allTools.sorted().joined(separator: ", "))")
                }
                enabledTools = specified
            }

            let server = MCPServer(enabledTools: enabledTools)
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
            spot - Spotlight Search for AI

            Provides Spotlight search capabilities via CLI or MCP server.

            MCP Tools:
              • search - Search files via Spotlight queries
              • meta   - Get file metadata

            === Claude Code Configuration ===

            Add to Claude Code (all tools):

              claude mcp add spot -- \(resolvedPath) mcp

            Add with specific tools only:

              claude mcp add spot -- \(resolvedPath) mcp search
              claude mcp add spot -- \(resolvedPath) mcp meta

            === Claude Desktop Configuration ===

            Add to ~/Library/Application Support/Claude/claude_desktop_config.json:

            {
              "mcpServers": {
                "spot": {
                  "command": "\(resolvedPath)",
                  "args": ["mcp"]
                }
              }
            }

            For specific tools only, add tool names to args:
              "args": ["mcp", "search"]

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
