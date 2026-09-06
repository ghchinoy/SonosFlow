import Foundation

public struct MCPServerInfo: Codable, Equatable {
    public let name: String
    public let version: String?

    public init(name: String, version: String? = nil) {
        self.name = name
        self.version = version
    }
}

public struct MCPTool: Codable, Identifiable, Equatable {
    public var id: String { name }
    public let name: String
    public let description: String?

    public init(name: String, description: String? = nil) {
        self.name = name
        self.description = description
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
