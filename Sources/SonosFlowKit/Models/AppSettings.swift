import Foundation
import Combine

public final class AppSettings: ObservableObject {
    public static let shared = AppSettings()

    private enum Keys {
        static let mcpBinaryPath = "sonosflow_mcp_binary_path"
        static let selectedGroupId = "sonosflow_selected_group_id"
        static let pollingInterval = "sonosflow_polling_interval"
        static let volumeDelta = "sonosflow_volume_delta"
        static let recentStreams = "sonosflow_recent_streams"
        static let customPresets = "sonosflow_custom_presets"
    }

    private let defaults: UserDefaults

    @Published public var mcpBinaryPath: String {
        didSet { defaults.set(mcpBinaryPath, forKey: Keys.mcpBinaryPath) }
    }

    @Published public var selectedGroupId: String? {
        didSet { defaults.set(selectedGroupId, forKey: Keys.selectedGroupId) }
    }

    @Published public var pollingInterval: Double {
        didSet { defaults.set(pollingInterval, forKey: Keys.pollingInterval) }
    }

    @Published public var volumeDelta: Int {
        didSet { defaults.set(volumeDelta, forKey: Keys.volumeDelta) }
    }

    @Published public var recentStreams: [SavedStream] {
        didSet {
            if let data = try? JSONEncoder().encode(recentStreams) {
                defaults.set(data, forKey: Keys.recentStreams)
            }
        }
    }

    @Published public var customPresets: [SavedStream] {
        didSet {
            if let data = try? JSONEncoder().encode(customPresets) {
                defaults.set(data, forKey: Keys.customPresets)
            }
        }
    }

    public var allPresets: [SavedStream] {
        return SavedStream.curatedPresets + customPresets
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.mcpBinaryPath = defaults.string(forKey: Keys.mcpBinaryPath) ?? ""
        self.selectedGroupId = defaults.string(forKey: Keys.selectedGroupId)
        let interval = defaults.double(forKey: Keys.pollingInterval)
        self.pollingInterval = interval > 0 ? interval : 4.0
        let delta = defaults.integer(forKey: Keys.volumeDelta)
        self.volumeDelta = delta > 0 ? delta : 5

        if let data = defaults.data(forKey: Keys.recentStreams),
           let streams = try? JSONDecoder().decode([SavedStream].self, from: data) {
            self.recentStreams = streams
        } else {
            self.recentStreams = []
        }

        if let data = defaults.data(forKey: Keys.customPresets),
           let presets = try? JSONDecoder().decode([SavedStream].self, from: data) {
            self.customPresets = presets
        } else {
            self.customPresets = []
        }
    }

    public func addRecentStream(_ stream: SavedStream) {
        var updated = recentStreams.filter { $0.url != stream.url }
        updated.insert(stream, at: 0)
        self.recentStreams = Array(updated.prefix(8))
    }

    public func addCustomPreset(_ stream: SavedStream) {
        var updated = customPresets.filter { $0.url != stream.url }
        updated.append(stream)
        self.customPresets = updated
    }

    public func removeCustomPreset(id: String) {
        self.customPresets.removeAll(where: { $0.id == id })
    }

    /// Resolves the executable path to mcp-sonos binary with fallback discovery
    public var effectiveMcpBinaryPath: String {
        let trimmed = mcpBinaryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && FileManager.default.isExecutableFile(atPath: trimmed) {
            return trimmed
        }

        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(homeDir)/projects/homectl/bin/mcp-sonos",
            "\(homeDir)/go/bin/mcp-sonos",
            "/usr/local/bin/mcp-sonos",
            "/opt/homebrew/bin/mcp-sonos"
        ]

        for candidate in candidates {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        return "\(homeDir)/projects/homectl/bin/mcp-sonos"
    }
}
