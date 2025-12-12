# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
swift build              # Debug build
swift build -c release   # Release build
```

## Install

```bash
swift build -c release
cp .build/release/spot ~/.local/bin/
```

## Test MCP Server

```bash
# Test tools/list
echo '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | .build/debug/spot mcp

# Test search tool
echo '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"search","arguments":{"q":"*.swift","n":5}}}' | .build/debug/spot mcp

# Test meta tool
echo '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"meta","arguments":{"path":"/path/to/file"}}}' | .build/debug/spot mcp
```

## Architecture

Three source files in `Sources/spot/`:

- **spot.swift** - CLI entry point using swift-argument-parser. Defines subcommands (`search`, `count`, `meta`, `mcp`, `schema`) and shared helper functions (`parseQueryShorthand`, `parseSortSpec`, `formatResults`).

- **MCPServer.swift** - MCP protocol implementation. JSON-RPC 2.0 over stdio. Handles `initialize`, `tools/list`, `tools/call`. Uses `enabledTools: Set<String>` for tool filtering.

- **SpotlightQuery.swift** - CoreServices/MDQuery wrapper. `SpotlightQueryExecutor` runs Spotlight queries synchronously. `QueryBuilder` provides shorthand-to-MDQuery translation. Key: uses `MDItemCopyAttribute` individually (not `MDItemCopyAttributes` which crashes).

## Query Shorthand

The `parseQueryShorthand()` function converts user-friendly syntax to raw MDQuery:
- `@name:*.swift` → `kMDItemFSName == "*.swift"wc`
- `@content:TODO` → `kMDItemTextContent == "*TODO*"cd`
- `@type:public.swift-source` → `kMDItemContentType == "public.swift-source"`
- `@mod:7` → `kMDItemContentModificationDate > $time.today(-7)`

Plain text defaults to filename glob.

## MCP Tool Filtering

MCP server accepts optional tool names as arguments:
```bash
spot mcp              # All tools (search, meta)
spot mcp search       # Only search
spot mcp meta         # Only meta
```
