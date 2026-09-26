import Foundation

/// Unified backend interface abstracting local UPnP (via homectl stdio) and cloud hosted (via Sonos 27mcp).
public protocol SonosBackend: AnyObject, Sendable {
    var engine: ControlEngine { get }
    var capabilities: ServerCapabilities { get }

    func connect() async throws -> (serverInfo: MCPServerInfo, tools: [MCPTool])
    func disconnect() async
    func isConnected() async -> Bool

    // MARK: - Discovery & Topology
    func getTopology(target: SonosTarget?) async throws -> TopologyResult

    // MARK: - Playback & Transport
    func getNowPlaying(target: SonosTarget) async throws -> NowPlayingResult
    func play(target: SonosTarget) async throws
    func pause(target: SonosTarget) async throws
    func next(target: SonosTarget) async throws
    func previous(target: SonosTarget) async throws
    func seekTrack(target: SonosTarget, track: Int) async throws
    func seekTime(target: SonosTarget, seconds: Int) async throws

    // MARK: - Volume & Mute
    func setVolume(target: SonosTarget, volume: Int) async throws
    func adjustVolume(target: SonosTarget, delta: Int) async throws
    func setMute(target: SonosTarget, muted: Bool) async throws

    // MARK: - Favorites
    func listFavorites(target: SonosTarget?) async throws -> [SonosFavorite]
    func playFavorite(target: SonosTarget, favoriteId: String) async throws

    // MARK: - Audio Streams
    func playStream(target: SonosTarget, url: String, title: String?) async throws

    // MARK: - Queue Management
    func getQueue(target: SonosTarget, start: Int, count: Int) async throws -> QueueResult
    func removeTrackFromQueue(target: SonosTarget, track: Int, count: Int) async throws
    func reorderQueue(target: SonosTarget, startingIndex: Int, numberOfTracks: Int, insertBefore: Int) async throws
    func reorderToPlayNext(target: SonosTarget, track: Int, count: Int) async throws
    func clearQueue(target: SonosTarget) async throws
}
