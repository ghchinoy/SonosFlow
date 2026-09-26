import Foundation

// MARK: - Discovery & Speakers

public struct SonosDevice: Codable, Identifiable, Hashable {
    public var id: String { rinconID.isEmpty ? ip : rinconID }
    public let name: String
    public let ip: String
    public let rinconID: String
    public let modelName: String?
    public let modelNumber: String?

    public init(
        name: String,
        ip: String,
        rinconID: String,
        modelName: String? = nil,
        modelNumber: String? = nil
    ) {
        self.name = name
        self.ip = ip
        self.rinconID = rinconID
        self.modelName = modelName
        self.modelNumber = modelNumber
    }

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case ip = "IP"
        case rinconID = "RinconID"
        case modelName = "ModelName"
        case modelNumber = "ModelNumber"
    }
}

public struct ListSpeakersResult: Codable {
    public let count: Int
    public let speakers: [SonosDevice]
}

// MARK: - Topology

public struct TopologyMember: Codable, Identifiable, Hashable {
    public var id: String { uuid }
    public let uuid: String
    public let roomName: String
    public let ip: String?
    public let isCoordinator: Bool
    public let invisible: Bool?

    public init(
        uuid: String,
        roomName: String,
        ip: String? = nil,
        isCoordinator: Bool = false,
        invisible: Bool? = nil
    ) {
        self.uuid = uuid
        self.roomName = roomName
        self.ip = ip
        self.isCoordinator = isCoordinator
        self.invisible = invisible
    }

    enum CodingKeys: String, CodingKey {
        case uuid
        case roomName = "room_name"
        case ip
        case isCoordinator = "is_coordinator"
        case invisible
    }
}

public struct TopologyGroup: Codable, Identifiable, Hashable {
    public let id: String
    public let coordinatorUUID: String
    public let isPair: Bool
    public let members: [TopologyMember]
    public let householdId: String?

    public init(
        id: String,
        coordinatorUUID: String,
        isPair: Bool,
        members: [TopologyMember],
        householdId: String? = nil
    ) {
        self.id = id
        self.coordinatorUUID = coordinatorUUID
        self.isPair = isPair
        self.members = members
        self.householdId = householdId
    }

    enum CodingKeys: String, CodingKey {
        case id
        case coordinatorUUID = "coordinator_uuid"
        case isPair = "is_pair"
        case members
        case householdId = "household_id"
    }

    /// Neutral target representation for backend dispatch
    public var target: SonosTarget {
        if let ip = coordinatorIP, !ip.isEmpty {
            return .local(ip)
        }
        return .cloud(householdId: householdId ?? "", groupId: id)
    }

    /// Best human-readable name for the group (e.g. "Office", "Living Room + Kitchen")
    public var displayName: String {
        let visibleRooms = members
            .filter { !($0.invisible ?? false) }
            .map(\.roomName)
            .reduce(into: [String]()) { acc, name in
                if !acc.contains(name) { acc.append(name) }
            }
        if visibleRooms.isEmpty {
            return members.first?.roomName ?? "Sonos Group"
        }
        return visibleRooms.joined(separator: " + ")
    }

    /// Subtitle description (e.g. "Stereo Pair • 2 speakers" or "Single Speaker")
    public var subtitle: String {
        if isPair {
            return "Stereo Pair (\(members.count) speakers)"
        } else if members.count > 1 {
            return "Group (\(members.count) rooms)"
        }
        return "Standalone"
    }

    /// Authoritative IP address of the group coordinator
    public var coordinatorIP: String? {
        if let coord = members.first(where: { $0.uuid == coordinatorUUID }), let ip = coord.ip, !ip.isEmpty {
            return ip
        }
        if let coord = members.first(where: { $0.isCoordinator }), let ip = coord.ip, !ip.isEmpty {
            return ip
        }
        return members.first?.ip
    }
}

public struct TopologyResult: Codable {
    public let count: Int
    public let groups: [TopologyGroup]

    public init(count: Int, groups: [TopologyGroup]) {
        self.count = count
        self.groups = groups
    }
}

// MARK: - Now Playing

public struct UpNextTrack: Codable, Equatable, Hashable, Sendable {
    public let title: String
    public let artist: String?
    public let album: String?
    public let albumArtURI: String?
    public let duration: String?

    public init(
        title: String,
        artist: String? = nil,
        album: String? = nil,
        albumArtURI: String? = nil,
        duration: String? = nil
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.albumArtURI = albumArtURI
        self.duration = duration
    }

    enum CodingKeys: String, CodingKey {
        case title
        case artist
        case album
        case albumArtURI = "album_art_uri"
        case duration
    }
}

public struct NowPlayingResult: Codable, Equatable {
    public let ip: String
    public let state: String
    public let volume: Int
    public let title: String?
    public let artist: String?
    public let album: String?
    public let duration: String?
    public let progress: String?
    public let streamContent: String?
    public let trackURI: String?
    public let queueLength: Int?
    public let mediaURI: String?
    public let isFollower: Bool?
    public let coordinatorIP: String?
    public let upNext: UpNextTrack?

    public init(
        ip: String,
        state: String,
        volume: Int,
        title: String? = nil,
        artist: String? = nil,
        album: String? = nil,
        duration: String? = nil,
        progress: String? = nil,
        streamContent: String? = nil,
        trackURI: String? = nil,
        queueLength: Int? = nil,
        mediaURI: String? = nil,
        isFollower: Bool? = nil,
        coordinatorIP: String? = nil,
        upNext: UpNextTrack? = nil
    ) {
        self.ip = ip
        self.state = state
        self.volume = volume
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.progress = progress
        self.streamContent = streamContent
        self.trackURI = trackURI
        self.queueLength = queueLength
        self.mediaURI = mediaURI
        self.isFollower = isFollower
        self.coordinatorIP = coordinatorIP
        self.upNext = upNext
    }

    enum CodingKeys: String, CodingKey {
        case ip
        case state
        case volume
        case title
        case artist
        case album
        case duration
        case progress
        case streamContent = "stream_content"
        case trackURI = "track_uri"
        case queueLength = "queue_length"
        case mediaURI = "media_uri"
        case isFollower = "is_follower"
        case coordinatorIP = "coordinator_ip"
        case upNext = "up_next"
    }

    public var isPlaying: Bool {
        state.uppercased() == "PLAYING"
    }

    public var isPaused: Bool {
        state.uppercased() == "PAUSED_PLAYBACK" || state.uppercased() == "PAUSED"
    }

    public var isStopped: Bool {
        state.uppercased() == "STOPPED"
    }

    public var displayTitle: String {
        if let t = title, !t.trimmingCharacters(in: .whitespaces).isEmpty {
            return t
        }
        if let s = streamContent, !s.trimmingCharacters(in: .whitespaces).isEmpty {
            return s
        }
        return "No Track Playing"
    }

    public var displaySubtitle: String {
        var parts: [String] = []
        if let a = artist, !a.trimmingCharacters(in: .whitespaces).isEmpty {
            parts.append(a)
        }
        if let al = album, !al.trimmingCharacters(in: .whitespaces).isEmpty {
            parts.append(al)
        }
        if parts.isEmpty {
            return state.capitalized
        }
        return parts.joined(separator: " — ")
    }

    public var progressSeconds: Double {
        parseDurationSeconds(progress)
    }

    public var durationSeconds: Double {
        parseDurationSeconds(duration)
    }

    public var progressFraction: Double {
        let dur = durationSeconds
        guard dur > 0 else { return 0.0 }
        let prog = progressSeconds
        return min(max(prog / dur, 0.0), 1.0)
    }
}

// MARK: - Queue

public struct QueueItem: Codable, Identifiable, Hashable {
    public var id: String { "\(position)_\(trackID)" }
    public let position: Int
    public let trackID: String
    public let title: String
    public let artist: String
    public let album: String?
    public let uri: String?
    public let albumArtURI: String?
    public let duration: String?

    public init(
        position: Int,
        trackID: String,
        title: String,
        artist: String,
        album: String? = nil,
        uri: String? = nil,
        albumArtURI: String? = nil,
        duration: String? = nil
    ) {
        self.position = position
        self.trackID = trackID
        self.title = title
        self.artist = artist
        self.album = album
        self.uri = uri
        self.albumArtURI = albumArtURI
        self.duration = duration
    }

    enum CodingKeys: String, CodingKey {
        case position
        case trackID = "track_id"
        case title
        case artist
        case album
        case uri
        case albumArtURI = "album_art_uri"
        case duration
    }

    /// Resolves the album art URL using either cloud HTTPS or local Sonos UPnP port 1400
    public func resolvedAlbumArtURL(coordinatorIP: String) -> URL? {
        guard let art = albumArtURI, !art.isEmpty else { return nil }
        if art.hasPrefix("http://") || art.hasPrefix("https://") {
            return URL(string: art)
        }
        let cleanIP = coordinatorIP.trimmingCharacters(in: .whitespaces)
        guard !cleanIP.isEmpty else { return nil }
        if art.hasPrefix("/") {
            return URL(string: "http://\(cleanIP):1400\(art)")
        }
        return URL(string: "http://\(cleanIP):1400/\(art)")
    }
}

public struct QueueResult: Codable {
    public let items: [QueueItem]
    public let returned: Int
    public let totalMatches: Int
    public let startIndex: Int

    public init(
        items: [QueueItem],
        returned: Int,
        totalMatches: Int,
        startIndex: Int
    ) {
        self.items = items
        self.returned = returned
        self.totalMatches = totalMatches
        self.startIndex = startIndex
    }

    enum CodingKeys: String, CodingKey {
        case items
        case returned
        case totalMatches = "total_matches"
        case startIndex = "start_index"
    }
}

// MARK: - Favorites

public struct SonosFavorite: Codable, Identifiable, Hashable {
    public let id: String
    public let title: String
    public let type: String?
    public let resourceURI: String?
    public let metadata: String?
    public let albumArtURI: String?
    public let description: String?

    public init(
        id: String,
        title: String,
        type: String? = nil,
        resourceURI: String? = nil,
        metadata: String? = nil,
        albumArtURI: String? = nil,
        description: String? = nil
    ) {
        self.id = id
        self.title = title
        self.type = type
        self.resourceURI = resourceURI
        self.metadata = metadata
        self.albumArtURI = albumArtURI
        self.description = description
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case type
        case resourceURI = "resource_uri"
        case metadata
        case albumArtURI = "album_art_uri"
        case description
    }

    public func resolvedAlbumArtURL(coordinatorIP: String) -> URL? {
        guard let art = albumArtURI, !art.isEmpty else { return nil }
        if art.hasPrefix("http://") || art.hasPrefix("https://") {
            return URL(string: art)
        }
        let cleanIP = coordinatorIP.trimmingCharacters(in: .whitespaces)
        guard !cleanIP.isEmpty else { return nil }
        if art.hasPrefix("/") {
            return URL(string: "http://\(cleanIP):1400\(art)")
        }
        return URL(string: "http://\(cleanIP):1400/\(art)")
    }
}

public struct ListFavoritesResult: Codable {
    public let count: Int
    public let favorites: [SonosFavorite]

    public init(count: Int, favorites: [SonosFavorite]) {
        self.count = count
        self.favorites = favorites
    }
}

// MARK: - Audio Streams & Presets

public struct SavedStream: Codable, Identifiable, Hashable {
    public var id: String { url }
    public let title: String
    public let url: String
    public let genre: String?

    public init(title: String, url: String, genre: String? = nil) {
        self.title = title
        self.url = url
        self.genre = genre
    }

    public static let curatedPresets: [SavedStream] = [
        SavedStream(title: "SomaFM: Groove Salad", url: "https://ice1.somafm.com/groovesalad-128-mp3", genre: "Downtempo Ambient"),
        SavedStream(title: "KEXP 90.3 FM Seattle", url: "https://kexp.streamguys1.com/kexp128.mp3", genre: "Indie / Alternative"),
        SavedStream(title: "BBC Radio 6 Music", url: "http://stream.live.vc.bbcmedia.co.uk/bbc_6music", genre: "Alternative / Eclectic"),
        SavedStream(title: "SomaFM: Drone Zone", url: "https://ice1.somafm.com/dronezone-128-mp3", genre: "Atmospheric Ambient"),
        SavedStream(title: "WNYC 93.9 FM New York", url: "https://fm939.wnyc.org/wnycfm-web", genre: "Public Radio / News"),
        SavedStream(title: "SomaFM: DEF CON Radio", url: "https://ice1.somafm.com/defcon-128-mp3", genre: "Electronic / Hacker")
    ]
}

// MARK: - Time Parsing Helpers

public func parseDurationSeconds(_ str: String?) -> Double {
    guard let s = str?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else {
        return 0.0
    }
    let parts = s.components(separatedBy: ":")
    guard !parts.isEmpty else { return 0.0 }

    if parts.count == 3 {
        let hours = Double(parts[0]) ?? 0
        let minutes = Double(parts[1]) ?? 0
        let seconds = Double(parts[2]) ?? 0
        return hours * 3600 + minutes * 60 + seconds
    } else if parts.count == 2 {
        let minutes = Double(parts[0]) ?? 0
        let seconds = Double(parts[1]) ?? 0
        return minutes * 60 + seconds
    } else if parts.count == 1 {
        return Double(parts[0]) ?? 0
    }
    return 0.0
}
