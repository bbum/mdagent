import ArgumentParser
import Foundation
import CoreServices

@main
struct Spot: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "spot",
        abstract: "Spotlight search for AI - CLI and MCP server",
        discussion: """
            Wraps macOS Spotlight (MDQuery) for efficient file discovery.
            Run as MCP server: spot mcp
            Direct query: spot search "*.swift"
            """,
        version: "1.0.0",
        subcommands: [SearchCommand.self, CountCommand.self, MetaCommand.self, MCPCommand.self, SchemaCommand.self],
        defaultSubcommand: SearchCommand.self
    )
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
        ("@name=", { QueryBuilder.exactFilename($0) }),  // Exact match (must come before @name:)
        ("@name:", { QueryBuilder.filename($0) }),       // Glob match
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

/// Parse sort specification string into (attribute, descending) tuple
func parseSortSpec(_ sort: String?) -> (sortBy: String?, descending: Bool) {
    guard let sort = sort else { return (nil, true) }

    let descending: Bool
    let clean: String
    if sort.hasPrefix("-") {
        descending = true
        clean = String(sort.dropFirst())
    } else {
        descending = false
        clean = sort
    }

    let sortBy: String
    switch clean {
    case "name": sortBy = kMDItemFSName as String
    case "date": sortBy = kMDItemContentModificationDate as String
    case "size": sortBy = kMDItemFSSize as String
    case "created": sortBy = kMDItemFSCreationDate as String
    default: sortBy = clean
    }

    return (sortBy, descending)
}

/// Format search results according to format string
func formatResults(_ results: [SpotlightResult], format: String) -> String {
    switch format {
    case "paths":
        return results.map(\.path).joined(separator: "\n")
    case "full":
        return results.map { r in
            var parts = [r.path]
            if let kind = r.kind { parts.append("kind:\(kind)") }
            if let size = r.size { parts.append("size:\(size)") }
            if let mod = r.modified {
                parts.append("mod:\(ISO8601DateFormatter().string(from: mod))")
            }
            if let ct = r.contentType { parts.append("type:\(ct)") }
            return parts.joined(separator: " | ")
        }.joined(separator: "\n")
    default: // compact
        return results.map(\.compact).joined(separator: "\n")
    }
}
