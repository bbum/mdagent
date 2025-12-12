import ArgumentParser
import Foundation

struct CountCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "count",
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

        let count = try executor.count(query: parsedQuery, scopes: scopes)
        print(count)
    }
}
