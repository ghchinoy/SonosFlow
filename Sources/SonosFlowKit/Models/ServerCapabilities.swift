import Foundation

/// Defines which control engine SonosFlow is configured to use.
public enum ControlEngine: String, CaseIterable, Identifiable, Codable, Sendable {
    case local = "local"
    case cloud = "cloud"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .local:
            return "Local Engine (homectl-sonos)"
        case .cloud:
            return "Sonos Cloud (Official 27mcp)"
        }
    }

    public var subtitle: String {
        switch self {
        case .local:
            return "Zero-login, <10ms local UPnP via stdio pipe. Supports full queue editing and local radio streams."
        case .cloud:
            return "Official hosted cloud endpoint via OAuth 2.1 PKCE. Requires active internet connection."
        }
    }

    public var shortBadge: String {
        switch self {
        case .local:
            return "LOCAL"
        case .cloud:
            return "CLOUD"
        }
    }
}

/// Neutral target identifier specifying how to route commands to a speaker or group.
public struct SonosTarget: Hashable, Sendable {
    public let localIP: String?
    public let householdId: String?
    public let groupId: String?
    public let playerId: String?

    public init(
        localIP: String? = nil,
        householdId: String? = nil,
        groupId: String? = nil,
        playerId: String? = nil
    ) {
        self.localIP = localIP
        self.householdId = householdId
        self.groupId = groupId
        self.playerId = playerId
    }

    public static func local(_ ip: String) -> SonosTarget {
        SonosTarget(localIP: ip)
    }

    public static func cloud(householdId: String, groupId: String, playerId: String? = nil) -> SonosTarget {
        SonosTarget(householdId: householdId, groupId: groupId, playerId: playerId)
    }
}

/// Dynamically inspected capabilities discovered from the active server's `tools/list`.
/// Controls in the UI are gated against these booleans rather than hardcoding engine checks.
public struct ServerCapabilities: Equatable, Sendable {
    public let engine: ControlEngine
    public let supportsQueue: Bool
    public let supportsQueueEdit: Bool
    public let supportsAudioStreams: Bool
    public let supportsFavorites: Bool
    public let supportsVolumeControl: Bool
    public let supportsDynamicGrouping: Bool
    public let supportsHomeTheaterEQ: Bool
    public let supportsShuffleRepeat: Bool
    public let supportsCrossfade: Bool
    public let supportsMusicSearch: Bool
    public let rawToolNames: Set<String>

    public init(
        engine: ControlEngine,
        tools: [MCPTool]
    ) {
        self.engine = engine
        let toolNames = Set(tools.map(\.name))
        self.rawToolNames = toolNames
        let toolsByName = Dictionary(uniqueKeysWithValues: tools.map { ($0.name, $0) })

        switch engine {
        case .local:
            self.supportsQueue = toolNames.contains("sonos_get_queue")
            self.supportsQueueEdit = toolNames.contains("sonos_queue_edit")
            self.supportsAudioStreams = toolNames.contains("sonos_play_stream")
            self.supportsFavorites = toolNames.contains("sonos_list_favorites") && toolNames.contains("sonos_play_favorite")
            self.supportsVolumeControl = toolNames.contains("sonos_set_volume")
            self.supportsDynamicGrouping = toolNames.contains("sonos_group")
            self.supportsHomeTheaterEQ = toolNames.contains("sonos_set_eq")

            // Introspect sonos_queue_edit schema for control-bjv (property presence or action description/enum)
            let queueEditTool = toolsByName["sonos_queue_edit"]
            let hasRepeatMode = queueEditTool?.hasProperty("repeat_mode") == true
            let actionMentionsShuffle = queueEditTool?.propertyMentions("action", keyword: "shuffle") == true
            let actionMentionsCrossfade = queueEditTool?.propertyMentions("action", keyword: "crossfade") == true
            let hasEnabled = queueEditTool?.hasProperty("enabled") == true

            self.supportsShuffleRepeat = hasRepeatMode || actionMentionsShuffle || toolNames.contains("sonos_set_playmode")
            self.supportsCrossfade = actionMentionsCrossfade || (hasEnabled && hasRepeatMode)
            self.supportsMusicSearch = false

        case .cloud:
            // Official Sonos 27mcp cloud capabilities
            self.supportsQueue = false
            self.supportsQueueEdit = false
            self.supportsAudioStreams = false
            self.supportsFavorites = toolNames.contains("get_sonos_favorites") && toolNames.contains("play_sonos_favorite")
            self.supportsVolumeControl = toolNames.contains("set_group_volume") || toolNames.contains("set_player_volume")
            self.supportsDynamicGrouping = toolNames.contains("add_players_to_group") && toolNames.contains("remove_players_from_group")
            self.supportsHomeTheaterEQ = toolNames.contains("get_night_sound_and_speech_enhancement") && toolNames.contains("set_night_sound_and_speech_enhancement")
            self.supportsShuffleRepeat = toolNames.contains("get_shuffle_repeat_crossfade") && toolNames.contains("set_shuffle_repeat_crossfade")
            self.supportsCrossfade = toolNames.contains("get_shuffle_repeat_crossfade") && toolNames.contains("set_shuffle_repeat_crossfade")
            self.supportsMusicSearch = toolNames.contains("play_track") || toolNames.contains("play_album") || toolNames.contains("play_artist")
        }
    }

    public init(
        engine: ControlEngine,
        rawToolNames: Set<String>
    ) {
        let dummyTools = rawToolNames.map { MCPTool(name: $0) }
        self.init(engine: engine, tools: dummyTools)
    }

    public static let localDefault = ServerCapabilities(
        engine: .local,
        rawToolNames: [
            "sonos_list_speakers",
            "sonos_get_topology",
            "sonos_get_now_playing",
            "sonos_get_queue",
            "sonos_control",
            "sonos_set_volume",
            "sonos_list_favorites",
            "sonos_play_favorite",
            "sonos_play_stream",
            "sonos_queue_edit"
        ]
    )

    public static let cloudDefault = ServerCapabilities(
        engine: .cloud,
        rawToolNames: [
            "get_households_and_groups_and_players",
            "get_now_playing",
            "resume",
            "pause",
            "skip_to_next_track",
            "skip_to_previous_track",
            "seek",
            "get_group_volume",
            "set_group_volume",
            "set_group_mute",
            "get_sonos_favorites",
            "play_sonos_favorite"
        ]
    )
}
