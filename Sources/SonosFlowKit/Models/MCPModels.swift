import Foundation

public struct MCPServerInfo: Codable, Equatable {
    public let name: String
    public let version: String?

    public init(name: String, version: String? = nil) {
        self.name = name
        self.version = version
    }
}

public struct MCPTool: Codable, Identifiable, Equatable, Sendable {
    public var id: String { name }
    public let name: String
    public let description: String?
    public let inputSchemaJSON: String?

    public init(name: String, description: String? = nil, inputSchemaJSON: String? = nil) {
        self.name = name
        self.description = description
        self.inputSchemaJSON = inputSchemaJSON
    }

    /// Returns parsed inputSchema dictionary if available
    public var inputSchema: [String: Any]? {
        guard let jsonStr = inputSchemaJSON, let data = jsonStr.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// Extracts string enum choices for a given property in inputSchema
    public func enumValues(forProperty propName: String) -> [String] {
        guard let schema = inputSchema,
              let props = schema["properties"] as? [String: Any],
              let prop = props[propName] as? [String: Any] else {
            return []
        }
        if let enumVals = prop["enum"] as? [String] {
            return enumVals
        }
        return []
    }
}

public enum MCPServerStatus: Equatable {
    case disconnected
    case connecting
    case connected(serverInfo: MCPServerInfo, tools: [MCPTool])
    case error(String)

    public var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    public var statusDescription: String {
        switch self {
        case .disconnected:
            return "Disconnected"
        case .connecting:
            return "Connecting..."
        case .connected(let info, let tools):
            return "Connected (\(info.name) - \(tools.count) tools)"
        case .error(let msg):
            return "Error: \(msg)"
        }
    }
}
