import Foundation

/// Local edge-first Sonos backend communicating with homectl mcp-sonos via stdio pipe JSON-RPC 2.0.
public final class LocalHomectlBackend: SonosBackend, @unchecked Sendable {
    public let engine: ControlEngine = .local
    public let service: SonosService
    public let settings: AppSettings
    public private(set) var capabilities: ServerCapabilities = .localDefault

    public init(
        service: SonosService = SonosService(),
        settings: AppSettings = .shared
    ) {
        self.service = service
        self.settings = settings
    }

    public func connect() async throws -> (serverInfo: MCPServerInfo, tools: [MCPTool]) {
        let path = settings.effectiveMcpBinaryPath
        let (info, tools) = try await service.client.initializeAndVerify(binaryPath: path)
        let toolNames = Set(tools.map(\.name))
        self.capabilities = ServerCapabilities(engine: .local, rawToolNames: toolNames)
        return (info, tools)
    }

    public func disconnect() async {
        await service.client.stop()
    }

    public func isConnected() async -> Bool {
        await service.client.isConnected()
    }

    // MARK: - Discovery & Topology

    public func getTopology(target: SonosTarget?) async throws -> TopologyResult {
        if let ip = target?.localIP, !ip.isEmpty {
            return try await service.getTopology(ip: ip)
        }

        let speakers = try await service.listSpeakers(refresh: false)
        guard let first = speakers.first else {
            throw NSError(domain: "LocalHomectlBackend", code: 404, userInfo: [NSLocalizedDescriptionKey: "No Sonos speakers discovered on local network."])
        }
        return try await service.getTopology(ip: first.ip)
    }

    // MARK: - Playback & Transport

    public func getNowPlaying(target: SonosTarget) async throws -> NowPlayingResult {
        guard let ip = target.localIP else {
            throw NSError(domain: "LocalHomectlBackend", code: 400, userInfo: [NSLocalizedDescriptionKey: "Missing local IP for now playing."])
        }
        return try await service.getNowPlaying(ip: ip)
    }

    public func play(target: SonosTarget) async throws {
        guard let ip = target.localIP else { return }
        try await service.play(ip: ip)
    }

    public func pause(target: SonosTarget) async throws {
        guard let ip = target.localIP else { return }
        try await service.pause(ip: ip)
    }

    public func next(target: SonosTarget) async throws {
        guard let ip = target.localIP else { return }
        try await service.next(ip: ip)
    }

    public func previous(target: SonosTarget) async throws {
        guard let ip = target.localIP else { return }
        try await service.previous(ip: ip)
    }

    public func seekTrack(target: SonosTarget, track: Int) async throws {
        guard let ip = target.localIP else { return }
        try await service.seekTrack(ip: ip, track: track)
    }

    public func seekTime(target: SonosTarget, seconds: Int) async throws {
        guard let ip = target.localIP else { return }
        let totalSecs = max(0, seconds)
        let hours = totalSecs / 3600
        let minutes = (totalSecs % 3600) / 60
        let secs = totalSecs % 60
        let timeTarget = String(format: "%02d:%02d:%02d", hours, minutes, secs)
        try await service.control(ip: ip, action: "seek_time", target: timeTarget)
    }

    // MARK: - Volume & Mute

    public func setVolume(target: SonosTarget, volume: Int) async throws {
        guard let ip = target.localIP else { return }
        try await service.setVolume(ip: ip, volume: volume)
    }

    public func adjustVolume(target: SonosTarget, delta: Int) async throws {
        guard let ip = target.localIP else { return }
        try await service.adjustVolume(ip: ip, delta: delta)
    }

    public func setMute(target: SonosTarget, muted: Bool) async throws {
        guard let ip = target.localIP else { return }
        if muted {
            try await service.setVolume(ip: ip, volume: 0)
        }
    }

    // MARK: - Favorites

    public func listFavorites(target: SonosTarget?) async throws -> [SonosFavorite] {
        guard let ip = target?.localIP else { return [] }
        return try await service.listFavorites(ip: ip)
    }

    public func playFavorite(target: SonosTarget, favoriteId: String) async throws {
        guard let ip = target.localIP else { return }
        try await service.playFavorite(ip: ip, favoriteId: favoriteId)
    }

    // MARK: - Audio Streams

    public func playStream(target: SonosTarget, url: String, title: String?) async throws {
        guard let ip = target.localIP else { return }
        try await service.playStream(ip: ip, url: url, title: title)
    }

    // MARK: - Queue Management

    public func getQueue(target: SonosTarget, start: Int, count: Int) async throws -> QueueResult {
        guard let ip = target.localIP else {
            return QueueResult(items: [], returned: 0, totalMatches: 0, startIndex: start)
        }
        return try await service.getQueue(ip: ip, start: start, count: count)
    }

    public func removeTrackFromQueue(target: SonosTarget, track: Int, count: Int) async throws {
        guard let ip = target.localIP else { return }
        try await service.removeTrackFromQueue(ip: ip, track: track, count: count)
    }

    public func reorderQueue(target: SonosTarget, startingIndex: Int, numberOfTracks: Int, insertBefore: Int) async throws {
        guard let ip = target.localIP else { return }
        try await service.reorderQueue(ip: ip, startingIndex: startingIndex, numberOfTracks: numberOfTracks, insertBefore: insertBefore)
    }

    public func reorderToPlayNext(target: SonosTarget, track: Int, count: Int) async throws {
        guard let ip = target.localIP else { return }
        try await service.reorderToPlayNext(ip: ip, track: track, count: count)
    }

    public func clearQueue(target: SonosTarget) async throws {
        guard let ip = target.localIP else { return }
        try await service.clearQueue(ip: ip)
    }
}
