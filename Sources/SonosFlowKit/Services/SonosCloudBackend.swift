import Foundation

/// Cloud-mediated Sonos backend communicating with the official Sonos 27mcp server at mcp.ws.sonos.com.
public final class SonosCloudBackend: SonosBackend, @unchecked Sendable {
    public let engine: ControlEngine = .cloud
    public let client: CloudMCPClient
    public private(set) var capabilities: ServerCapabilities = .cloudDefault

    /// Cached playback states by groupId discovered during topology query
    private var cachedPlaybackStates: [String: String] = [:]

    public init(client: CloudMCPClient = CloudMCPClient()) {
        self.client = client
    }

    public func connect() async throws -> (serverInfo: MCPServerInfo, tools: [MCPTool]) {
        let (info, tools) = try await client.initialize()
        self.capabilities = ServerCapabilities(engine: .cloud, tools: tools)
        return (info, tools)
    }

    public func disconnect() async {
        // Cloud backend does not maintain persistent sockets when idle
    }

    public func isConnected() async -> Bool {
        return await client.hasValidToken()
    }

    // MARK: - Discovery & Topology

    public func getTopology(target: SonosTarget?) async throws -> TopologyResult {
        let raw = try await client.callTool(name: "get_households_and_groups_and_players", arguments: [:])
        let parsed = try parseTopologyResponse(raw)
        return parsed
    }

    // MARK: - Playback & Transport

    public func getNowPlaying(target: SonosTarget) async throws -> NowPlayingResult {
        guard let gid = target.groupId, !gid.isEmpty else {
            throw NSError(domain: "SonosCloudBackend", code: 400, userInfo: [NSLocalizedDescriptionKey: "Missing group ID for cloud now playing query."])
        }

        // 1. Query what's playing
        let raw = try await client.callTool(name: "get_now_playing", arguments: ["group_id": gid])

        // 2. Query real group volume & mute state
        var volume = 20
        var isMuted = false
        if let rawVol = try? await client.callTool(name: "get_group_volume", arguments: ["group_id": gid]),
           let volDict = try? unwrapMCPJSON(rawVol) as? [String: Any] {
            if let v = volDict["volume"] as? Int {
                volume = v
            }
            if let m = volDict["muted"] as? Bool {
                isMuted = m
            }
        }

        return try parseNowPlayingResponse(raw, groupId: gid, volume: volume, isMuted: isMuted)
    }

    public func play(target: SonosTarget) async throws {
        guard let gid = target.groupId else { return }
        _ = try await client.callTool(name: "resume", arguments: ["group_id": gid])
        cachedPlaybackStates[gid] = "PLAYING"
    }

    public func pause(target: SonosTarget) async throws {
        guard let gid = target.groupId else { return }
        _ = try await client.callTool(name: "pause", arguments: ["group_id": gid])
        cachedPlaybackStates[gid] = "PAUSED_PLAYBACK"
    }

    public func next(target: SonosTarget) async throws {
        guard let gid = target.groupId else { return }
        _ = try await client.callTool(name: "skip_to_next_track", arguments: ["group_id": gid])
    }

    public func previous(target: SonosTarget) async throws {
        guard let gid = target.groupId else { return }
        _ = try await client.callTool(name: "skip_to_previous_track", arguments: ["group_id": gid])
    }

    public func seekTrack(target: SonosTarget, track: Int) async throws {
        // Zero queue tools in official Sonos 27mcp
    }

    public func seekTime(target: SonosTarget, seconds: Int) async throws {
        guard let gid = target.groupId else { return }
        let millis = max(0, seconds * 1000)
        _ = try await client.callTool(name: "seek", arguments: [
            "group_id": gid,
            "position_millis": millis
        ])
    }

    // MARK: - Volume & Mute

    public func setVolume(target: SonosTarget, volume: Int) async throws {
        guard let gid = target.groupId else { return }
        _ = try await client.callTool(name: "set_group_volume", arguments: [
            "group_id": gid,
            "volume": max(0, min(100, volume))
        ])
    }

    public func adjustVolume(target: SonosTarget, delta: Int) async throws {
        guard let gid = target.groupId else { return }
        if capabilities.rawToolNames.contains("adjust_group_volume") {
            _ = try await client.callTool(name: "adjust_group_volume", arguments: [
                "group_id": gid,
                "volume_delta": delta
            ])
        }
    }

    public func setMute(target: SonosTarget, muted: Bool) async throws {
        guard let gid = target.groupId else { return }
        _ = try await client.callTool(name: "set_group_mute", arguments: [
            "group_id": gid,
            "muted": muted
        ])
    }

    // MARK: - Favorites

    public func listFavorites(target: SonosTarget?) async throws -> [SonosFavorite] {
        guard let hid = target?.householdId, !hid.isEmpty else {
            return []
        }
        let raw = try await client.callTool(name: "get_sonos_favorites", arguments: ["household_id": hid])
        return parseFavoritesResponse(raw)
    }

    public func playFavorite(target: SonosTarget, favoriteId: String) async throws {
        guard let gid = target.groupId else { return }
        _ = try await client.callTool(name: "play_sonos_favorite", arguments: [
            "group_id": gid,
            "favorite_id": favoriteId,
            "shuffle": false
        ])
    }

    // MARK: - Audio Streams (Unsupported by Sonos 27mcp)

    public func playStream(target: SonosTarget, url: String, title: String?) async throws {
        throw NSError(domain: "SonosCloudBackend", code: 405, userInfo: [NSLocalizedDescriptionKey: "Arbitrary audio stream URLs are not supported by the official Sonos 27mcp server."])
    }

    // MARK: - Queue Management (Unsupported by Sonos 27mcp)

    public func getQueue(target: SonosTarget, start: Int, count: Int) async throws -> QueueResult {
        return QueueResult(items: [], returned: 0, totalMatches: 0, startIndex: start)
    }

    public func removeTrackFromQueue(target: SonosTarget, track: Int, count: Int) async throws {}
    public func reorderQueue(target: SonosTarget, startingIndex: Int, numberOfTracks: Int, insertBefore: Int) async throws {}
    public func reorderToPlayNext(target: SonosTarget, track: Int, count: Int) async throws {}
    public func clearQueue(target: SonosTarget) async throws {}

    // MARK: - Universal MCP Payload Unwrapping

    public static func unwrapMCPJSON(_ raw: Any) throws -> Any {
        if let dict = raw as? [String: Any] {
            if let content = dict["content"] as? [[String: Any]],
               let firstText = content.first?["text"] as? String {
                if let data = firstText.data(using: .utf8),
                   let parsed = try? JSONSerialization.jsonObject(with: data) {
                    return parsed
                }
                return firstText
            }
            return dict
        } else if let arr = raw as? [[String: Any]] {
            if let firstText = arr.first?["text"] as? String,
               let data = firstText.data(using: .utf8),
               let parsed = try? JSONSerialization.jsonObject(with: data) {
                return parsed
            }
            return arr
        }
        return raw
    }

    private func unwrapMCPJSON(_ raw: Any) throws -> Any {
        try Self.unwrapMCPJSON(raw)
    }

    // MARK: - Parsing Helpers

    public func parseTopologyResponse(_ raw: Any) throws -> TopologyResult {
        let unwrapped = try unwrapMCPJSON(raw)

        // The Sonos 27mcp server returns an array of households: [ { "householdId": "...", "name": "...", "groups": [ ... ] } ]
        var householdsList: [[String: Any]] = []
        if let list = unwrapped as? [[String: Any]] {
            householdsList = list
        } else if let dict = unwrapped as? [String: Any] {
            if let list = dict["households"] as? [[String: Any]] {
                householdsList = list
            } else {
                householdsList = [dict]
            }
        }

        var parsedGroups: [TopologyGroup] = []

        for household in householdsList {
            let householdId = household["householdId"] as? String ?? household["id"] as? String ?? ""

            // Groups inside household
            guard let groups = household["groups"] as? [[String: Any]] else { continue }

            for g in groups {
                guard let gid = g["groupId"] as? String ?? g["id"] as? String else { continue }

                // Cache state
                if let pState = g["playbackState"] as? String {
                    cachedPlaybackStates[gid] = normalizePlaybackState(pState)
                }

                // Players in group
                let rawPlayers = g["players"] as? [[String: Any]] ?? []
                var members: [TopologyMember] = []

                for (idx, p) in rawPlayers.enumerated() {
                    let pid = p["playerId"] as? String ?? p["id"] as? String ?? UUID().uuidString
                    let name = p["name"] as? String ?? "Sonos Speaker"
                    let isCoordinator = (idx == 0) // First player acts as coordinator
                    members.append(TopologyMember(
                        uuid: pid,
                        roomName: name,
                        ip: nil,
                        isCoordinator: isCoordinator,
                        invisible: false
                    ))
                }

                let isPair = (members.count == 2)
                let coordinatorUUID = members.first?.uuid ?? ""

                let grp = TopologyGroup(
                    id: gid,
                    coordinatorUUID: coordinatorUUID,
                    isPair: isPair,
                    members: members,
                    householdId: householdId
                )
                parsedGroups.append(grp)
            }
        }

        return TopologyResult(count: parsedGroups.count, groups: parsedGroups)
    }

    public func parseNowPlayingResponse(
        _ raw: Any,
        groupId: String,
        volume: Int = 20,
        isMuted: Bool = false
    ) throws -> NowPlayingResult {
        let unwrapped = try unwrapMCPJSON(raw)
        let payload = unwrapped as? [String: Any] ?? [:]

        // Playback state: from payload or cached from topology
        let rawState = payload["playbackState"] as? String
        let state = normalizePlaybackState(rawState ?? cachedPlaybackStates[groupId] ?? "STOPPED")

        // Track data (Sonos 27mcp uses "currentTrack", with "track" as fallback)
        let track = payload["currentTrack"] as? [String: Any] ?? payload["track"] as? [String: Any]
        let title = track?["name"] as? String ?? track?["title"] as? String
        let artist = track?["artist"] as? String
        let album = track?["album"] as? String
        let artURI = track?["imageUrl"] as? String ?? track?["albumArtURI"] as? String
        let service = track?["service"] as? String

        var durationStr: String? = nil
        if let durMillis = track?["durationMillis"] as? Int {
            let secs = durMillis / 1000
            durationStr = String(format: "%d:%02d", secs / 60, secs % 60)
        }

        var progressStr: String? = nil
        if let posMillis = payload["positionMillis"] as? Int {
            let secs = posMillis / 1000
            progressStr = String(format: "%d:%02d", secs / 60, secs % 60)
        }

        // Next track preview if available
        var upNext: UpNextTrack? = nil
        if let next = payload["nextTrack"] as? [String: Any],
           let nextTitle = next["name"] as? String ?? next["title"] as? String {
            upNext = UpNextTrack(
                title: nextTitle,
                artist: next["artist"] as? String,
                album: next["album"] as? String,
                albumArtURI: next["imageUrl"] as? String ?? next["albumArtURI"] as? String
            )
        }

        let effectiveVol = isMuted ? 0 : volume

        return NowPlayingResult(
            ip: groupId,
            state: state,
            volume: effectiveVol,
            title: title,
            artist: artist,
            album: album,
            duration: durationStr,
            progress: progressStr,
            streamContent: payload["streamInfo"] as? String ?? service,
            trackURI: artURI,
            queueLength: nil,
            mediaURI: artURI,
            isFollower: false,
            coordinatorIP: nil,
            upNext: upNext
        )
    }

    public func parseFavoritesResponse(_ raw: Any) -> [SonosFavorite] {
        guard let unwrapped = try? unwrapMCPJSON(raw) else { return [] }

        var items: [[String: Any]] = []
        if let arr = unwrapped as? [[String: Any]] {
            items = arr
        } else if let dict = unwrapped as? [String: Any], let favs = dict["favorites"] as? [[String: Any]] {
            items = favs
        }

        return items.compactMap { f in
            guard let fid = f["id"] as? String, let title = f["name"] as? String else { return nil }
            return SonosFavorite(
                id: fid,
                title: title,
                type: f["type"] as? String ?? "favorite",
                albumArtURI: f["imageUrl"] as? String,
                description: f["description"] as? String
            )
        }
    }

    private func normalizePlaybackState(_ raw: String) -> String {
        let upper = raw.uppercased()
        if upper.contains("PLAYING") {
            return "PLAYING"
        } else if upper.contains("PAUSE") {
            return "PAUSED_PLAYBACK"
        } else if upper.contains("BUFFER") {
            return "PLAYING"
        }
        return "STOPPED"
    }
}
