import ArgumentParser
import Foundation

struct MetaCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "meta",
        abstract: "Get file metadata"
    )

    @Argument(help: "File path")
    var path: String

    mutating func run() async throws {
        let expandedPath = (path as NSString).expandingTildeInPath
        let executor = SpotlightQueryExecutor()
        let result = try executor.metadata(path: expandedPath)
        print(result)
    }
}
