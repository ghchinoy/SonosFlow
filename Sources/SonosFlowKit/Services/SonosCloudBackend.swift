import Foundation

/// Cloud-mediated Sonos backend communicating with Sonos's official hosted 27mcp server.
public final class SonosCloudBackend: SonosBackend, @unchecked Sendable {
    public let engine: ControlEngine = .cloud
    public let client: CloudMCPClient
    public private(set) var capabilities: ServerCapabilities = .cloudDefault

    public init(client: CloudMCPClient = CloudMCPClient()) {
        self.client = client
    }

    public func connect() async throws -> (serverInfo: MCPServerInfo, tools: [MCPTool]) {
        let (info, tools) = try await client.initialize()
        let toolNames = Set(tools.map(\.name))
        self.capabilities = ServerCapabilities(engine: .cloud, rawToolNames: toolNames)
        return (info, tools)
    }

    public func disconnect() async {
        // Cloud backend does not hold an open socket pipe when idle
    }

    public func isConnected() async -> Bool {
        return await client.hasValidToken()
    }

    // MARK: - Discovery & Topology

    public func getTopology(target: SonosTarget?) async throws -> TopologyResult {
        let raw = try await client.callTool(name: "get_households_and_groups_and_players", arguments: [:])
        return try parseTopologyResponse(raw)
    }

    // MARK: - Playback & Transport

    public func getNowPlaying(target: SonosTarget) async throws -> NowPlayingResult {
        guard let gid = target.groupId, !gid.isEmpty else {
            throw NSError(domain: "SonosCloudBackend", code: 400, userInfo: [NSLocalizedDescriptionKey: "Missing group ID for cloud now playing query."])
        }

        let raw = try await client.callTool(name: "get_now_playing", arguments: ["group_id": gid])
        return try parseNowPlayingResponse(raw, groupId: gid)
    }

    public func play(target: SonosTarget) async throws {
        guard let gid = target.groupId else { return }
        _ = try await client.callTool(name: "resume", arguments: ["group_id": gid])
    }

    public func pause(target: SonosTarget) async throws {
        guard let gid = target.groupId else { return }
        _ = try await client.callTool(name: "pause", arguments: ["group_id": gid])
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
        // Not supported on cloud API; no-op
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
                "delta": delta
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
            "favorite_id": favoriteId
        ])
    }

    // MARK: - Audio Streams (Cloud does not support arbitrary URL streaming)

    public func playStream(target: SonosTarget, url: String, title: String?) async throws {
        throw NSError(domain: "SonosCloudBackend", code: 405, userInfo: [NSLocalizedDescriptionKey: "Audio stream URLs are not supported by the official Sonos cloud API."])
    }

    // MARK: - Queue Management (Cloud API has zero queue tools)

    public func getQueue(target: SonosTarget, start: Int, count: Int) async throws -> QueueResult {
        return QueueResult(items: [], returned: 0, totalMatches: 0, startIndex: start)
    }

    public func removeTrackFromQueue(target: SonosTarget, track: Int, count: Int) async throws {}
    public func reorderQueue(target: SonosTarget, startingIndex: Int, numberOfTracks: Int, insertBefore: Int) async throws {}
    public func reorderToPlayNext(target: SonosTarget, track: Int, count: Int) async throws {}
    public func clearQueue(target: SonosTarget) async throws {}

    // MARK: - Parsing Helpers

    private func parseTopologyResponse(_ raw: Any) throws -> TopologyResult {
        // Result may be wrapped in MCP text content: [{"type": "text", "text": "..."}]
        var dict: [String: Any]? = nil
        if let d = raw as? [String: Any] {
            dict = d
        } else if let arr = raw as? [[String: Any]], let firstText = arr.first?["text"] as? String {
            if let data = firstText.data(using: .utf8),
               let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                dict = parsed
            }
        }

        guard let payload = dict else {
            return TopologyResult(count: 0, groups: [])
        }

        var parsedGroups: [TopologyGroup] = []
        var householdId = ""

        if let households = payload["households"] as? [[String: Any]], let firstH = households.first {
            householdId = firstH["id"] as? String ?? ""

            // Players mapping
            var playersById: [String: [String: Any]] = [:]
            if let players = firstH["players"] as? [[String: Any]] {
                for p in players {
                    if let pid = p["id"] as? String {
                        playersById[pid] = p
                    }
                }
            }

            // Groups
            if let groups = firstH["groups"] as? [[String: Any]] {
                for g in groups {
                    guard let gid = g["id"] as? String else { continue }
                    let playerIds = g["playerIds"] as? [String] ?? []
                    let coordinatorId = g["coordinatorId"] as? String ?? playerIds.first ?? ""

                    var members: [TopologyMember] = []
                    for pid in playerIds {
                        let pData = playersById[pid]
                        let name = pData?["name"] as? String ?? (g["name"] as? String ?? "Sonos Player")
                        let isCoord = (pid == coordinatorId)
                        members.append(TopologyMember(
                            uuid: pid,
                            roomName: name,
                            ip: nil,
                            isCoordinator: isCoord,
                            invisible: false
                        ))
                    }

                    let isPair = (playerIds.count == 2)
                    let grp = TopologyGroup(
                        id: gid,
                        coordinatorUUID: coordinatorId,
                        isPair: isPair,
                        members: members,
                        householdId: householdId
                    )
                    parsedGroups.append(grp)
                }
            }
        }

        return TopologyResult(count: parsedGroups.count, groups: parsedGroups)
    }

    private func parseNowPlayingResponse(_ raw: Any, groupId: String) throws -> NowPlayingResult {
        var dict: [String: Any]? = nil
        if let d = raw as? [String: Any] {
            dict = d
        } else if let arr = raw as? [[String: Any]], let firstText = arr.first?["text"] as? String {
            if let data = firstText.data(using: .utf8),
               let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                dict = parsed
            }
        }

        let payload = dict ?? [:]
        let state = payload["playbackState"] as? String ?? "STOPPED"
        let track = payload["track"] as? [String: Any]
        let title = track?["name"] as? String
        let artist = track?["artist"] as? String
        let album = track?["album"] as? String
        let artURI = track?["imageUrl"] as? String

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

        var upNext: UpNextTrack? = nil
        if let next = payload["nextTrack"] as? [String: Any], let nextTitle = next["name"] as? String {
            upNext = UpNextTrack(
                title: nextTitle,
                artist: next["artist"] as? String,
                album: next["album"] as? String,
                albumArtURI: next["imageUrl"] as? String
            )
        }

        return NowPlayingResult(
            ip: groupId,
            state: state,
            volume: 20, // Group volume is refreshed separately
            title: title,
            artist: artist,
            album: album,
            duration: durationStr,
            progress: progressStr,
            streamContent: payload["streamInfo"] as? String,
            trackURI: artURI,
            queueLength: nil,
            mediaURI: artURI,
            isFollower: false,
            coordinatorIP: nil,
            upNext: upNext
        )
    }

    private func parseFavoritesResponse(_ raw: Any) -> [SonosFavorite] {
        var items: [[String: Any]] = []
        if let arr = raw as? [[String: Any]] {
            if let firstText = arr.first?["text"] as? String,
               let data = firstText.data(using: .utf8),
               let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let favs = parsed["favorites"] as? [[String: Any]] {
                items = favs
            } else {
                items = arr
            }
        } else if let dict = raw as? [String: Any], let favs = dict["favorites"] as? [[String: Any]] {
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
}
