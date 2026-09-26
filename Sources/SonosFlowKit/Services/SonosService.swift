import Foundation

public class SonosService: @unchecked Sendable {
    public let client: MCPClient

    public init(client: MCPClient = MCPClient()) {
        self.client = client
    }

    public func listSpeakers(refresh: Bool = false) async throws -> [SonosDevice] {
        let args: [String: Any] = ["refresh": refresh]
        let raw = try await client.callTool(name: "sonos_list_speakers", arguments: args)
        let res = try MCPClient.decodeResult(raw, as: ListSpeakersResult.self)
        return res.speakers
    }

    public func getTopology(ip: String) async throws -> TopologyResult {
        let args: [String: Any] = ["ip": ip]
        let raw = try await client.callTool(name: "sonos_get_topology", arguments: args)
        return try MCPClient.decodeResult(raw, as: TopologyResult.self)
    }

    public func getNowPlaying(ip: String) async throws -> NowPlayingResult {
        let args: [String: Any] = ["ip": ip]
        let raw = try await client.callTool(name: "sonos_get_now_playing", arguments: args)
        return try MCPClient.decodeResult(raw, as: NowPlayingResult.self)
    }

    public func getQueue(ip: String, start: Int = 0, count: Int = 100) async throws -> QueueResult {
        let args: [String: Any] = [
            "ip": ip,
            "start": start,
            "count": count
        ]
        let raw = try await client.callTool(name: "sonos_get_queue", arguments: args)
        return try MCPClient.decodeResult(raw, as: QueueResult.self)
    }

    public func control(ip: String, action: String, track: Int? = nil, target: String? = nil) async throws {
        var args: [String: Any] = [
            "ip": ip,
            "action": action
        ]
        if let track = track {
            args["track"] = track
        }
        if let target = target {
            args["target"] = target
        }
        _ = try await client.callTool(name: "sonos_control", arguments: args)
    }

    public func seekTrack(ip: String, track: Int) async throws {
        try await control(ip: ip, action: "seek_track", track: track)
    }

    public func play(ip: String) async throws {
        try await control(ip: ip, action: "play")
    }

    public func pause(ip: String) async throws {
        try await control(ip: ip, action: "pause")
    }

    public func next(ip: String) async throws {
        try await control(ip: ip, action: "next")
    }

    public func previous(ip: String) async throws {
        try await control(ip: ip, action: "previous")
    }

    public func setVolume(ip: String, volume: Int) async throws {
        let args: [String: Any] = [
            "ip": ip,
            "volume": max(0, min(100, volume))
        ]
        _ = try await client.callTool(name: "sonos_set_volume", arguments: args)
    }

    public func adjustVolume(ip: String, delta: Int) async throws {
        let args: [String: Any] = [
            "ip": ip,
            "delta": delta
        ]
        _ = try await client.callTool(name: "sonos_set_volume", arguments: args)
    }

    public func listFavorites(ip: String) async throws -> [SonosFavorite] {
        let args: [String: Any] = ["ip": ip]
        let raw = try await client.callTool(name: "sonos_list_favorites", arguments: args)
        let res = try MCPClient.decodeResult(raw, as: ListFavoritesResult.self)
        return res.favorites
    }

    public func playFavorite(ip: String, favoriteId: String) async throws {
        let args: [String: Any] = [
            "ip": ip,
            "favorite_id": favoriteId
        ]
        _ = try await client.callTool(name: "sonos_play_favorite", arguments: args)
    }

    public func playStream(ip: String, url: String, title: String? = nil) async throws {
        var args: [String: Any] = [
            "ip": ip,
            "url": url
        ]
        if let t = title, !t.isEmpty {
            args["title"] = t
        }
        _ = try await client.callTool(name: "sonos_play_stream", arguments: args)
    }

    // MARK: - Queue Mutations (Pure MCP: sonos_queue_edit)
    // Invokes the official `sonos_queue_edit` tool on the homectl MCP server
    // (implemented in homectl via beads issues control-znc, control-s5y, and control-6ht).

    public func removeTrackFromQueue(ip: String, track: Int, count: Int = 1) async throws {
        let args: [String: Any] = [
            "ip": ip,
            "action": "remove",
            "track": track,
            "count": count
        ]
        _ = try await client.callTool(name: "sonos_queue_edit", arguments: args)
    }

    public func reorderQueue(
        ip: String,
        startingIndex: Int,
        numberOfTracks: Int = 1,
        insertBefore: Int
    ) async throws {
        let args: [String: Any] = [
            "ip": ip,
            "action": "reorder",
            "track": startingIndex,
            "count": numberOfTracks,
            "insert_before": insertBefore
        ]
        _ = try await client.callTool(name: "sonos_queue_edit", arguments: args)
    }

    public func reorderToPlayNext(
        ip: String,
        track: Int,
        count: Int = 1
    ) async throws {
        let args: [String: Any] = [
            "ip": ip,
            "action": "reorder",
            "track": track,
            "count": count,
            "as_next": true
        ]
        _ = try await client.callTool(name: "sonos_queue_edit", arguments: args)
    }

    public func clearQueue(ip: String) async throws {
        let args: [String: Any] = [
            "ip": ip,
            "action": "clear"
        ]
        _ = try await client.callTool(name: "sonos_queue_edit", arguments: args)
    }
}
