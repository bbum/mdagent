# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
swift build              # Debug build
swift build -c release   # Release build
```

## Install

Always use the Makefile (removes old binary first to avoid code signing issues):
```bash
make install
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

`Sources/spot/`:

- **spot.swift** - CLI entry point, shared helpers (`parseQueryShorthand`, `parseSortSpec`, `formatResults`)
- **SpotlightQuery.swift** - CoreServices/MDQuery wrapper. Uses `MDItemCopyAttribute` individually (not `MDItemCopyAttributes` which crashes)
- **Subcommands/** - CLI subcommands (SearchCommand, CountCommand, MetaCommand, MCPCommand, SchemaCommand)
- **MCP/** - MCP server (MCPServer, MCPTool protocol, SearchTool, MetaTool)

## Query Shorthand

The `parseQueryShorthand()` function converts user-friendly syntax to raw MDQuery:

| Shorthand | MDQuery | Notes |
|-----------|---------|-------|
| `@name:*.swift` | `kMDItemFSName == "*.swift"wc` | Glob match (partial) |
| `@name=Back` | `kMDItemFSName == "Back"cd` | **Exact match** (case-insensitive) |
| `@content:TODO` | `kMDItemTextContent == "*TODO*"cd` | Content search |
| `@type:public.swift-source` | `kMDItemContentType == "..."` | UTI type |
| `@mod:7` | `kMDItemContentModificationDate > $time.today(-7)` | Modified within days |
| `@size:>1M` | `kMDItemFSSize > 1048576` | Size filter |

Plain text defaults to filename glob.

### Raw MDQuery

For advanced queries, use raw MDQuery syntax directly:
```
kMDItemFSName == "back"cd && kMDItemContentType == "public.folder"
```

Modifiers: `c`=case-insensitive, `d`=diacritic-insensitive, `w`=wildcard

## MCP Tool Filtering

MCP server accepts optional tool names as arguments:
```bash
spot mcp              # All tools (search, meta)
spot mcp search       # Only search
spot mcp meta         # Only meta
```
