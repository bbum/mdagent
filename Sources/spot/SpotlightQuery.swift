import Foundation
import CoreServices

/// Result from a Spotlight query
struct SpotlightResult: Codable, Sendable {
    let path: String
    let name: String
    let kind: String?
    let size: Int64?
    let modified: Date?
    let created: Date?
    let contentType: String?

    /// Compact representation for AI - minimal tokens
    var compact: String {
        var parts = [path]
        if let size = size {
            parts.append("\(formatSize(size))")
        }
        if let modified = modified {
            parts.append(ISO8601DateFormatter().string(from: modified))
        }
        return parts.joined(separator: "|")
    }

    private func formatSize(_ bytes: Int64) -> String {
        if bytes < 1024 { return "\(bytes)B" }
        if bytes < 1024 * 1024 { return "\(bytes / 1024)K" }
        if bytes < 1024 * 1024 * 1024 { return "\(bytes / (1024 * 1024))M" }
        return "\(bytes / (1024 * 1024 * 1024))G"
    }
}

/// Spotlight query execution - not an actor to avoid CoreFoundation threading issues
final class SpotlightQueryExecutor: @unchecked Sendable {
    private let queue = DispatchQueue(label: "spot.spotlight", qos: .userInitiated)

    enum QueryError: Error, LocalizedError {
        case queryCreationFailed
        case executionFailed
        case invalidScope(String)

        var errorDescription: String? {
            switch self {
            case .queryCreationFailed: return "Failed to create MDQuery"
            case .executionFailed: return "Query execution failed"
            case .invalidScope(let path): return "Invalid scope path: \(path)"
            }
        }
    }

    /// Execute a Spotlight query synchronously
    /// - Parameters:
    ///   - queryString: MDQuery string (e.g., "kMDItemFSName == '*.swift'")
    ///   - scopes: Optional array of directory paths to search within
    ///   - limit: Maximum results to return (0 = unlimited)
    ///   - sortBy: Attribute to sort by (e.g., kMDItemFSName, kMDItemContentModificationDate)
    ///   - descending: Sort order
    /// - Returns: Array of SpotlightResult
    func execute(
        query queryString: String,
        scopes: [String]? = nil,
        limit: Int = 0,
        sortBy: String? = nil,
        descending: Bool = true
    ) throws -> [SpotlightResult] {
        // Create the query
        guard let query = MDQueryCreate(kCFAllocatorDefault, queryString as CFString, nil, nil) else {
            throw QueryError.queryCreationFailed
        }

        // Set search scopes if provided
        if let scopes = scopes, !scopes.isEmpty {
            let scopeURLs = scopes.map { URL(fileURLWithPath: $0) as CFURL }
            MDQuerySetSearchScope(query, scopeURLs as CFArray, 0)
        }

        // Set sort order if provided
        if let sortBy = sortBy {
            MDQuerySetSortOrder(query, [sortBy as CFString] as CFArray)
            if descending {
                // kMDQueryReverseSortOrderFlag = 1
                MDQuerySetSortOptionFlagsForAttribute(query, sortBy as CFString, 1)
            }
        }

        // Set max results
        if limit > 0 {
            MDQuerySetMaxCount(query, limit)
        }

        // Execute synchronously
        guard MDQueryExecute(query, CFOptionFlags(kMDQuerySynchronous.rawValue)) else {
            throw QueryError.executionFailed
        }

        // Collect results
        let count = MDQueryGetResultCount(query)
        var results: [SpotlightResult] = []
        results.reserveCapacity(count)

        for i in 0..<count {
            guard let item = MDQueryGetResultAtIndex(query, i) else { continue }
            let mdItem = unsafeBitCast(item, to: MDItem.self)

            if let result = extractResult(from: mdItem) {
                results.append(result)
            }
        }

        return results
    }

    /// Extract result data from an MDItem
    private func extractResult(from item: MDItem) -> SpotlightResult? {
        guard let path = MDItemCopyAttribute(item, kMDItemPath) as? String else {
            return nil
        }

        let name = MDItemCopyAttribute(item, kMDItemFSName) as? String ?? URL(fileURLWithPath: path).lastPathComponent
        let kind = MDItemCopyAttribute(item, kMDItemKind) as? String
        let size = MDItemCopyAttribute(item, kMDItemFSSize) as? Int64
        let modified = MDItemCopyAttribute(item, kMDItemContentModificationDate) as? Date
        let created = MDItemCopyAttribute(item, kMDItemFSCreationDate) as? Date
        let contentType = MDItemCopyAttribute(item, kMDItemContentType) as? String

        return SpotlightResult(
            path: path,
            name: name,
            kind: kind,
            size: size,
            modified: modified,
            created: created,
            contentType: contentType
        )
    }

    /// Count results for a query without fetching full data
    func count(query queryString: String, scopes: [String]? = nil) throws -> Int {
        guard let query = MDQueryCreate(kCFAllocatorDefault, queryString as CFString, nil, nil) else {
            throw QueryError.queryCreationFailed
        }

        if let scopes = scopes, !scopes.isEmpty {
            let scopeURLs = scopes.map { URL(fileURLWithPath: $0) as CFURL }
            MDQuerySetSearchScope(query, scopeURLs as CFArray, 0)
        }

        guard MDQueryExecute(query, CFOptionFlags(kMDQuerySynchronous.rawValue)) else {
            throw QueryError.executionFailed
        }

        return MDQueryGetResultCount(query)
    }

    /// Get metadata for a specific file
    func metadata(path: String) throws -> String {
        guard let mdItem = MDItemCreate(kCFAllocatorDefault, path as CFString) else {
            throw QueryError.invalidScope(path)
        }

        guard let attrNames = MDItemCopyAttributeNames(mdItem) as? [String] else {
            return "No metadata available"
        }

        var lines: [String] = []

        for attr in attrNames.sorted() {
            if let value = MDItemCopyAttribute(mdItem, attr as CFString) {
                let shortKey = attr.replacingOccurrences(of: "kMDItem", with: "")
                    .replacingOccurrences(of: "_kMDItem", with: "_")
                lines.append("\(shortKey): \(formatValue(value))")
            }
        }

        return lines.joined(separator: "\n")
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

/// Query builder for common patterns
struct QueryBuilder {

    /// Build query for filename pattern (glob-style)
    static func filename(_ pattern: String) -> String {
        // Convert glob to MDQuery: *.swift -> kMDItemFSName == "*.swift"wc
        "kMDItemFSName == \"\(pattern)\"wc"
    }

    /// Build query for exact filename match (case-insensitive)
    static func exactFilename(_ name: String) -> String {
        // Exact match with case+diacritic insensitivity: Back -> kMDItemFSName == "Back"cd
        "kMDItemFSName == \"\(escapeQuery(name))\"cd"
    }

    /// Build query for content search
    static func content(_ text: String) -> String {
        "kMDItemTextContent == \"*\(escapeQuery(text))*\"cd"
    }

    /// Build query for file kind
    static func kind(_ kind: String) -> String {
        "kMDItemKind == \"\(escapeQuery(kind))\"cd"
    }

    /// Build query for content type (UTI)
    static func contentType(_ uti: String) -> String {
        "kMDItemContentType == \"\(escapeQuery(uti))\""
    }

    /// Build query for content type tree (includes subtypes)
    static func contentTypeTree(_ uti: String) -> String {
        "kMDItemContentTypeTree == \"\(escapeQuery(uti))\""
    }

    /// Build query for files modified within days
    static func modifiedWithinDays(_ days: Int) -> String {
        "kMDItemContentModificationDate > $time.today(-\(days))"
    }

    /// Build query for files created within days
    static func createdWithinDays(_ days: Int) -> String {
        "kMDItemFSCreationDate > $time.today(-\(days))"
    }

    /// Build query for files larger than size (bytes)
    static func largerThan(_ bytes: Int64) -> String {
        "kMDItemFSSize > \(bytes)"
    }

    /// Build query for files smaller than size (bytes)
    static func smallerThan(_ bytes: Int64) -> String {
        "kMDItemFSSize < \(bytes)"
    }

    /// Combine queries with AND
    static func and(_ queries: String...) -> String {
        "(" + queries.joined(separator: " && ") + ")"
    }

    /// Combine queries with OR
    static func or(_ queries: String...) -> String {
        "(" + queries.joined(separator: " || ") + ")"
    }

    /// Negate a query
    static func not(_ query: String) -> String {
        "!(\(query))"
    }

    /// Escape special characters in query values
    private static func escapeQuery(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

/// Common content type constants
enum ContentTypes {
    static let sourceCode = "public.source-code"
    static let swift = "public.swift-source"
    static let objectiveC = "public.objective-c-source"
    static let python = "public.python-script"
    static let javascript = "com.netscape.javascript-source"
    static let json = "public.json"
    static let xml = "public.xml"
    static let html = "public.html"
    static let markdown = "net.daringfireball.markdown"
    static let plainText = "public.plain-text"
    static let pdf = "com.adobe.pdf"
    static let image = "public.image"
    static let audio = "public.audio"
    static let video = "public.movie"
    static let folder = "public.folder"
    static let application = "com.apple.application-bundle"
}
