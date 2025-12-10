# mdagent

Spotlight search MCP server for AI assistants. Wraps macOS MDQuery for fast file discovery.

## Installation

```bash
swift build -c release
cp .build/release/mdagent ~/.local/bin/
```

## MCP Server

Add to Claude Code:
```bash
claude mcp add mdagent -- ~/.local/bin/mdagent mcp
```

Add specific tools only:
```bash
claude mcp add mdagent -- ~/.local/bin/mdagent mcp search
claude mcp add mdagent -- ~/.local/bin/mdagent mcp meta
```

Claude Desktop (`~/Library/Application Support/Claude/claude_desktop_config.json`):
```json
{
  "mcpServers": {
    "mdagent": {
      "command": "/path/to/mdagent",
      "args": ["mcp"]
    }
  }
}
```

## MCP Tools

### search

Search files via Spotlight. Returns paths matching query.

Parameters:
- `q` (required): Query string (see syntax below)
- `in`: Scope path(s), comma-separated
- `n`: Max results (default: 100)
- `sort`: Sort by `name|date|size|created` (prefix `-` for descending)
- `fmt`: Output format `compact|full|paths|count`

### meta

Get all Spotlight metadata for a file (equivalent to `mdls`).

Parameters:
- `path` (required): File path

## Query Syntax

Shorthand notation:
- `@name:*.swift` - Filename glob pattern
- `@content:TODO` - File content search
- `@kind:folder` - File kind
- `@type:public.swift-source` - Content type (UTI)
- `@tree:public.source-code` - Content type tree (includes subtypes)
- `@mod:7` - Modified within N days
- `@created:30` - Created within N days
- `@size:>1M` - Size filter (K/M/G units, `<`/`>` operators)

Plain text is treated as a filename glob. Raw MDQuery syntax also supported.

## CLI Usage

```bash
# Search
mdagent search "*.swift"
mdagent search "@content:TODO @type:public.swift-source" --scope ~/Developer
mdagent search "@mod:7 @size:>100K" --format full --limit 50

# Count
mdagent count "@kind:folder" --scope ~/Documents

# Metadata
mdagent meta ~/path/to/file
```

## License

MIT
