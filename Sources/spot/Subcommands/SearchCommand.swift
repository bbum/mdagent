import ArgumentParser
import Foundation

struct SearchCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "search",
        abstract: "Search files via Spotlight"
    )

    @Argument(help: "Query: glob pattern, @name:*.swift, @content:TODO, @kind:folder, @type:UTI, @mod:7 (days), @size:>1M")
    var query: String

    @Option(name: [.customShort("i"), .customLong("in"), .long], help: "Search scope path(s), comma-separated")
    var scope: String?

    @Option(name: [.customShort("n"), .long], help: "Max results")
    var limit: Int = 100

    @Option(name: .long, help: "Sort: name|date|size|created (prefix - for desc)")
    var sort: String?

    @Option(name: [.customLong("fmt"), .long], help: "Output format: compact|full|paths|json")
    var format: String = "compact"

    mutating func run() async throws {
        let executor = SpotlightQueryExecutor()
        let parsedQuery = parseQueryShorthand(query)
        let scopes = scope?.split(separator: ",").map(String.init)
        let (sortBy, descending) = parseSortSpec(sort)

        let results = try executor.execute(
            query: parsedQuery,
            scopes: scopes,
            limit: limit,
            sortBy: sortBy,
            descending: descending
        )

        if format == "json" {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(results)
            print(String(data: data, encoding: .utf8)!)
        } else {
            print(formatResults(results, format: format))
        }
    }
}
