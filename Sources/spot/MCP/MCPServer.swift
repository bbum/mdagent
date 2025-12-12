import Foundation

/// All available MCP tools - add new tools here
enum MCPTools {
    static let allNames: Set<String> = ["search", "meta"]

    static func createTool(name: String) -> (any MCPTool)? {
        switch name {
        case "search": return SearchTool()
        case "meta": return MetaTool()
        default: return nil
        }
    }

    static func toolType(name: String) -> (any MCPTool.Type)? {
        switch name {
        case "search": return SearchTool.self
        case "meta": return MetaTool.self
        default: return nil
        }
    }
}

// MARK: - MCP Server

final class MCPServer {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let enabledTools: Set<String>
    private var toolInstances: [String: any MCPTool] = [:]

    init(enabledTools: Set<String> = MCPTools.allNames) {
        self.enabledTools = enabledTools
        encoder.outputFormatting = []
        encoder.dateEncodingStrategy = .iso8601

        // Create instances of enabled tools
        for name in enabledTools {
            if let tool = MCPTools.createTool(name: name) {
                toolInstances[name] = tool
            }
        }
    }

    func run() async {
        while let line = readLine() {
            guard !line.isEmpty else { continue }

            do {
                let request = try decoder.decode(JSONRPCRequest.self, from: Data(line.utf8))
                let response = await handleRequest(request)
                sendResponse(response)
            } catch {
                let errorResponse = JSONRPCResponse(id: nil, error: .parseError(error.localizedDescription))
                sendResponse(errorResponse)
            }
        }
    }

    private func sendResponse(_ response: JSONRPCResponse) {
        do {
            let data = try encoder.encode(response)
            if let json = String(data: data, encoding: .utf8) {
                print(json)
                fflush(stdout)
            }
        } catch {
            print("{\"jsonrpc\":\"2.0\",\"id\":null,\"error\":{\"code\":-32603,\"message\":\"Encoding error\"}}")
            fflush(stdout)
        }
    }

    private func handleRequest(_ request: JSONRPCRequest) async -> JSONRPCResponse {
        switch request.method {
        case "initialize":
            return handleInitialize(request)
        case "initialized", "notifications/initialized":
            return JSONRPCResponse(id: request.id, result: .object([:]))
        case "tools/list":
            return handleToolsList(request)
        case "tools/call":
            return await handleToolsCall(request)
        default:
            return JSONRPCResponse(id: request.id, error: .methodNotFound(request.method))
        }
    }

    // MARK: - Initialize

    private func handleInitialize(_ request: JSONRPCRequest) -> JSONRPCResponse {
        let result: JSONValue = .object([
            "protocolVersion": .string("2024-11-05"),
            "serverInfo": .object([
                "name": .string("spot"),
                "version": .string("1.0.0")
            ]),
            "capabilities": .object([
                "tools": .object([:])
            ])
        ])
        return JSONRPCResponse(id: request.id, result: result)
    }

    // MARK: - Tools List

    private func handleToolsList(_ request: JSONRPCRequest) -> JSONRPCResponse {
        var toolsList: [JSONValue] = []

        for name in enabledTools.sorted() {
            if let toolType = MCPTools.toolType(name: name) {
                toolsList.append(toolType.mcpToolDefinition)
            }
        }

        let tools: JSONValue = .object(["tools": .array(toolsList)])
        return JSONRPCResponse(id: request.id, result: tools)
    }

    // MARK: - Tools Call

    private func handleToolsCall(_ request: JSONRPCRequest) async -> JSONRPCResponse {
        guard let params = request.params?.objectValue,
              let name = params["name"]?.stringValue else {
            return JSONRPCResponse(id: request.id, error: .invalidParams("Missing tool name"))
        }

        guard enabledTools.contains(name) else {
            return JSONRPCResponse(id: request.id, error: .methodNotFound("Tool not enabled: \(name)"))
        }

        guard let tool = toolInstances[name] else {
            return JSONRPCResponse(id: request.id, error: .methodNotFound("Unknown tool: \(name)"))
        }

        let args = params["arguments"]?.objectValue ?? [:]

        do {
            let result = try await tool.execute(args: args)

            let response: JSONValue = .object([
                "content": .array([
                    .object([
                        "type": .string("text"),
                        "text": .string(result)
                    ])
                ])
            ])
            return JSONRPCResponse(id: request.id, result: response)
        } catch {
            return JSONRPCResponse(id: request.id, error: .internalError(error.localizedDescription))
        }
    }
}
