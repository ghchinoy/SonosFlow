import Foundation
import SwiftUI
import Combine

@MainActor
public final class SonosCoordinator: ObservableObject {
    @Published public var serverStatus: MCPServerStatus = .disconnected
    @Published public var groups: [TopologyGroup] = []
    @Published public var selectedGroup: TopologyGroup? = nil
    @Published public var nowPlaying: NowPlayingResult? = nil
    @Published public var queueItems: [QueueItem] = []
    @Published public var queueTotalMatches: Int = 0
    @Published public var favorites: [SonosFavorite] = []
    @Published public var volume: Double = 0.0
    @Published public var isMuted: Bool = false
    @Published public var groupPlaybackStates: [String: String] = [:]
    @Published public var isLoadingQueue: Bool = false
    @Published public var isRefreshing: Bool = false
    @Published public var isMiniPlayerMode: Bool = false
    @Published public var errorMessage: String? = nil

    public func toggleMiniPlayerMode() {
        isMiniPlayerMode.toggle()
    }

    public let sonosService: SonosService
    public let settings: AppSettings

    /// Resolves the album art URL for the currently playing track/stream
    public var currentArtworkURL: URL? {
        guard let coordIP = selectedGroup?.coordinatorIP else { return nil }
        if let np = nowPlaying, let title = np.title, !title.isEmpty {
            if let matched = queueItems.first(where: { $0.title == title }) {
                return matched.resolvedAlbumArtURL(coordinatorIP: coordIP)
            }
        }
        if let np = nowPlaying {
            let query = np.title ?? np.streamContent ?? ""
            if !query.isEmpty {
                if let fav = favorites.first(where: { $0.title.localizedCaseInsensitiveContains(query) || query.localizedCaseInsensitiveContains($0.title) }) {
                    return fav.resolvedAlbumArtURL(coordinatorIP: coordIP)
                }
            }
        }
        return nil
    }

    private var pollTask: Task<Void, Never>?
    private var volumeDebounceTask: Task<Void, Never>?
    private var previousVolume: Double = 20.0

    public init(
        sonosService: SonosService = SonosService(),
        settings: AppSettings = .shared
    ) {
        self.sonosService = sonosService
        self.settings = settings
    }

    deinit {
        pollTask?.cancel()
        volumeDebounceTask?.cancel()
    }

    // MARK: - Server Lifecycle

    public func connectAndInitialize() async {
        serverStatus = .connecting
        errorMessage = nil
        let binaryPath = settings.effectiveMcpBinaryPath

        do {
            let (serverInfo, tools) = try await sonosService.client.initializeAndVerify(binaryPath: binaryPath)
            serverStatus = .connected(serverInfo: serverInfo, tools: tools)
            AppLogger.shared.log("Connected to \(serverInfo.name) with \(tools.count) tools", category: "COORDINATOR")
            await refreshAll()
            startPolling()
        } catch {
            serverStatus = .error(error.localizedDescription)
            errorMessage = "Sonos MCP Server error: \(error.localizedDescription)"
            AppLogger.shared.error("Connection failed: \(error)", category: "COORDINATOR")
        }
    }

    public func disconnect() async {
        pollTask?.cancel()
        pollTask = nil
        await sonosService.client.stop()
        serverStatus = .disconnected
    }

    /// Stops the existing MCP server process, spawns the binary anew, and refreshes all groups and playback state.
    public func reloadServer() async {
        isRefreshing = true
        serverStatus = .connecting
        AppLogger.shared.log("Reloading Sonos MCP Server...", category: "COORDINATOR")

        await sonosService.client.stop()
        try? await Task.sleep(nanoseconds: 150_000_000)

        let binaryPath = settings.effectiveMcpBinaryPath
        do {
            let (serverInfo, tools) = try await sonosService.client.initializeAndVerify(binaryPath: binaryPath)
            serverStatus = .connected(serverInfo: serverInfo, tools: tools)
            AppLogger.shared.log("Reloaded \(serverInfo.name) with \(tools.count) tools", category: "COORDINATOR")
            await refreshAll(forceNetworkScan: false)
            errorMessage = nil
        } catch {
            serverStatus = .error(error.localizedDescription)
            errorMessage = "Failed to reload MCP Server: \(error.localizedDescription)"
            AppLogger.shared.error("reloadServer failed: \(error)", category: "COORDINATOR")
        }
        isRefreshing = false
    }

    // MARK: - Discovery & Refresh

    /// Orders discovered speakers prioritizing active coordinator first, stationary/mains speakers next, and battery portables (Move, Roam) last.
    public nonisolated static func prioritizeSeedSpeakers(speakers: [SonosDevice], activeCoordinatorIP: String?) -> [String] {
        var orderedIPs: [String] = []

        // 1. If we have an active coordinator IP, try it first
        if let active = activeCoordinatorIP, !active.isEmpty {
            orderedIPs.append(active)
        }

        // 2. Stationary speakers (Arc, Play:1, Play:3, Port, Beam, One, Five, etc.)
        let stationary = speakers.filter { spk in
            let model = (spk.modelName ?? "").lowercased()
            let isPortable = model.contains("move") || model.contains("roam")
            return !isPortable && !orderedIPs.contains(spk.ip)
        }
        for spk in stationary {
            orderedIPs.append(spk.ip)
        }

        // 3. Portable/battery speakers (Move, Roam) as last-resort fallback
        let portables = speakers.filter { spk in
            let model = (spk.modelName ?? "").lowercased()
            let isPortable = model.contains("move") || model.contains("roam")
            return isPortable && !orderedIPs.contains(spk.ip)
        }
        for spk in portables {
            orderedIPs.append(spk.ip)
        }

        return orderedIPs.filter { !$0.isEmpty }
    }

    public func refreshAll(forceNetworkScan: Bool = false) async {
        guard serverStatus.isConnected else { return }

        // Check if the binary on disk was updated/recompiled since the process started
        if await sonosService.client.isBinaryNewerOnDisk() {
            AppLogger.shared.log("Detected updated mcp-sonos binary on disk. Hot-reloading server...", category: "COORDINATOR")
            await reloadServer()
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        do {
            // 1. Discover speakers or check cached speakers
            let speakers = try await sonosService.listSpeakers(refresh: forceNetworkScan)
            guard !speakers.isEmpty else {
                if groups.isEmpty {
                    errorMessage = "No Sonos speakers discovered on the local network."
                }
                return
            }

            // 2. Prioritize candidate seed IPs: active coordinator -> stationary -> portable
            let candidateIPs = Self.prioritizeSeedSpeakers(
                speakers: speakers,
                activeCoordinatorIP: selectedGroup?.coordinatorIP
            )

            // 3. Fetch topology with automatic failover across candidates
            var topology: TopologyResult? = nil
            var lastError: Error? = nil

            for ip in candidateIPs {
                do {
                    topology = try await sonosService.getTopology(ip: ip)
                    break // Succeeded!
                } catch {
                    lastError = error
                    AppLogger.shared.warning("Topology query failed on \(ip), failing over to next speaker: \(error)", category: "COORDINATOR")
                }
            }

            guard let topology = topology else {
                if let err = lastError {
                    if groups.isEmpty {
                        errorMessage = "Failed to connect to Sonos speakers: \(err.localizedDescription)"
                    }
                    AppLogger.shared.error("All \(candidateIPs.count) candidate speakers failed for topology: \(err)", category: "COORDINATOR")
                }
                return
            }

            self.groups = topology.groups
            AppLogger.shared.log("Discovered \(topology.groups.count) Sonos groups", category: "COORDINATOR")

            // 4. Inspect playback state for each group coordinator
            for group in topology.groups {
                if let coordIP = group.coordinatorIP {
                    if let np = try? await sonosService.getNowPlaying(ip: coordIP) {
                        self.groupPlaybackStates[group.id] = np.state
                    }
                }
            }

            // 5. Select group (persisted selection -> first playing group -> first group)
            if let savedId = settings.selectedGroupId, let matched = topology.groups.first(where: { $0.id == savedId }) {
                self.selectedGroup = matched
            } else if selectedGroup == nil || !topology.groups.contains(where: { $0.id == selectedGroup?.id }) {
                if let playingGroup = topology.groups.first(where: { groupPlaybackStates[$0.id]?.uppercased() == "PLAYING" }) {
                    self.selectedGroup = playingGroup
                } else {
                    self.selectedGroup = topology.groups.first
                }
                if let sel = self.selectedGroup {
                    settings.selectedGroupId = sel.id
                }
            }

            // 6. Refresh active group data
            if let active = self.selectedGroup {
                await refreshActiveGroupData(group: active)
            }
            errorMessage = nil
        } catch {
            if groups.isEmpty {
                errorMessage = "Failed to refresh Sonos topology: \(error.localizedDescription)"
            }
            AppLogger.shared.error("refreshAll failed: \(error)", category: "COORDINATOR")
        }
    }

    public func selectGroup(_ group: TopologyGroup) async {
        self.selectedGroup = group
        self.settings.selectedGroupId = group.id
        await refreshActiveGroupData(group: group)
    }

    public func refreshActiveGroupData(group: TopologyGroup) async {
        guard let ip = group.coordinatorIP else { return }
        await refreshNowPlaying(ip: ip)
        await refreshQueue(ip: ip)
        await refreshFavorites(ip: ip)
    }

    // MARK: - Now Playing

    public func refreshNowPlaying(ip: String? = nil) async {
        guard let targetIP = ip ?? selectedGroup?.coordinatorIP else { return }
        do {
            let np = try await sonosService.getNowPlaying(ip: targetIP)
            self.nowPlaying = np
            self.volume = Double(np.volume)
            self.isMuted = (np.volume == 0)
            if let sel = selectedGroup {
                self.groupPlaybackStates[sel.id] = np.state
            }

            // Self-healing queue recovery:
            // If speaker reports tracks in the queue, but our local queueItems list is empty,
            // quietly refresh the queue in background so the UI self-heals.
            if let qLen = np.queueLength, qLen > 0 && queueItems.isEmpty && !isLoadingQueue {
                Task { [weak self] in
                    await self?.refreshQueue(ip: targetIP)
                }
            }
        } catch {
            AppLogger.shared.warning("Failed to refresh now playing for \(targetIP): \(error)", category: "COORDINATOR")
        }
    }

    // MARK: - Queue

    public func refreshQueue(ip: String? = nil) async {
        guard let targetIP = ip ?? selectedGroup?.coordinatorIP else { return }
        isLoadingQueue = true
        defer { isLoadingQueue = false }

        do {
            let q = try await sonosService.getQueue(ip: targetIP, start: 0, count: 100)
            self.queueItems = q.items
            self.queueTotalMatches = q.totalMatches
        } catch {
            AppLogger.shared.warning("Failed to refresh queue for \(targetIP): \(error)", category: "COORDINATOR")
        }
    }

    public func playQueueItem(_ item: QueueItem) async {
        guard let ip = selectedGroup?.coordinatorIP else { return }
        do {
            AppLogger.shared.log("Seeking track \(item.position) ('\(item.title)') on \(ip)", category: "COORDINATOR")
            try await sonosService.seekTrack(ip: ip, track: item.position)
            // Immediately start playing if paused
            if nowPlaying?.isPlaying != true {
                try? await sonosService.play(ip: ip)
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
            await refreshNowPlaying(ip: ip)
        } catch {
            errorMessage = "Failed to play queue track: \(error.localizedDescription)"
            AppLogger.shared.error("playQueueItem failed: \(error)", category: "COORDINATOR")
        }
    }

    public func removeQueueItem(_ item: QueueItem) async {
        guard let ip = selectedGroup?.coordinatorIP else { return }
        let priorItems = self.queueItems
        let priorTotal = self.queueTotalMatches

        // Optimistic UI removal
        if let idx = self.queueItems.firstIndex(where: { $0.id == item.id }) {
            self.queueItems.remove(at: idx)
            self.queueTotalMatches = max(0, self.queueTotalMatches - 1)
        }

        do {
            AppLogger.shared.log("Removing track \(item.position) ('\(item.title)') from queue on \(ip)", category: "COORDINATOR")
            try await sonosService.removeTrackFromQueue(ip: ip, track: item.position)
            try? await Task.sleep(nanoseconds: 200_000_000)
            await refreshQueue(ip: ip)
            await refreshNowPlaying(ip: ip)
        } catch {
            // Rollback on failure
            self.queueItems = priorItems
            self.queueTotalMatches = priorTotal
            errorMessage = "Failed to remove track: \(error.localizedDescription)"
            AppLogger.shared.error("removeQueueItem failed: \(error)", category: "COORDINATOR")
        }
    }

    public func moveQueueItems(from source: IndexSet, to destination: Int) async {
        guard let ip = selectedGroup?.coordinatorIP, let sourceIdx = source.first else { return }
        let priorItems = self.queueItems

        // Optimistic local reorder
        var updated = queueItems
        updated.move(fromOffsets: source, toOffset: destination)
        self.queueItems = updated

        // Compute 1-based Sonos UPnP indices
        let startingIndex = sourceIdx + 1
        // In UPnP ReorderTracksInQueue: insertBefore is 1-based track number
        let insertBefore = destination + 1

        do {
            AppLogger.shared.log("Reordering queue on \(ip): track \(startingIndex) -> before \(insertBefore)", category: "COORDINATOR")
            try await sonosService.reorderQueue(
                ip: ip,
                startingIndex: startingIndex,
                numberOfTracks: source.count,
                insertBefore: insertBefore
            )
            try? await Task.sleep(nanoseconds: 300_000_000)
            await refreshQueue(ip: ip)
        } catch {
            // Rollback on failure
            self.queueItems = priorItems
            errorMessage = "Failed to reorder queue: \(error.localizedDescription)"
            AppLogger.shared.error("moveQueueItems failed: \(error)", category: "COORDINATOR")
        }
    }

    public func playNextInQueue(_ item: QueueItem) async {
        guard let ip = selectedGroup?.coordinatorIP else { return }
        do {
            AppLogger.shared.log("Moving track \(item.position) ('\(item.title)') to play next on \(ip)", category: "COORDINATOR")
            try await sonosService.reorderToPlayNext(ip: ip, track: item.position)
            try? await Task.sleep(nanoseconds: 300_000_000)
            await refreshQueue(ip: ip)
        } catch {
            errorMessage = "Failed to move track to play next: \(error.localizedDescription)"
            AppLogger.shared.error("playNextInQueue failed: \(error)", category: "COORDINATOR")
        }
    }

    public func clearQueue() async {
        guard let ip = selectedGroup?.coordinatorIP else { return }
        let priorItems = self.queueItems
        let priorTotal = self.queueTotalMatches

        // Optimistic wipe
        self.queueItems = []
        self.queueTotalMatches = 0

        do {
            AppLogger.shared.log("Clearing all tracks from queue on \(ip)", category: "COORDINATOR")
            try await sonosService.clearQueue(ip: ip)
            try? await Task.sleep(nanoseconds: 200_000_000)
            await refreshQueue(ip: ip)
            await refreshNowPlaying(ip: ip)
        } catch {
            // Rollback on failure
            self.queueItems = priorItems
            self.queueTotalMatches = priorTotal
            errorMessage = "Failed to clear queue: \(error.localizedDescription)"
            AppLogger.shared.error("clearQueue failed: \(error)", category: "COORDINATOR")
        }
    }

    // MARK: - Favorites

    public func refreshFavorites(ip: String? = nil) async {
        guard let targetIP = ip ?? selectedGroup?.coordinatorIP else { return }
        do {
            let favs = try await sonosService.listFavorites(ip: targetIP)
            self.favorites = favs
        } catch {
            AppLogger.shared.warning("Failed to list favorites on \(targetIP): \(error)", category: "COORDINATOR")
        }
    }

    public func playFavorite(_ favorite: SonosFavorite) async {
        guard let ip = selectedGroup?.coordinatorIP else { return }
        do {
            AppLogger.shared.log("Playing favorite '\(favorite.title)' (ID: \(favorite.id)) on \(ip)", category: "COORDINATOR")
            try await sonosService.playFavorite(ip: ip, favoriteId: favorite.id)
            try? await Task.sleep(nanoseconds: 500_000_000)
            await refreshNowPlaying(ip: ip)
            await refreshQueue(ip: ip)
        } catch {
            errorMessage = "Failed to play favorite '\(favorite.title)': \(error.localizedDescription)"
            AppLogger.shared.error("playFavorite failed: \(error)", category: "COORDINATOR")
        }
    }

    // MARK: - Volume Controls

    public func setVolume(_ newVolume: Double) {
        let clamped = max(0.0, min(100.0, newVolume))
        self.volume = clamped
        self.isMuted = (clamped == 0)

        guard let ip = selectedGroup?.coordinatorIP else { return }

        volumeDebounceTask?.cancel()
        volumeDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 120_000_000) // 120ms debounce
            guard !Task.isCancelled else { return }
            do {
                try await sonosService.setVolume(ip: ip, volume: Int(clamped))
            } catch {
                AppLogger.shared.warning("Failed to set volume on \(ip): \(error)", category: "COORDINATOR")
            }
        }
    }

    public func stepVolume(delta: Int) {
        let target = volume + Double(delta)
        setVolume(target)
    }

    public func toggleMute() {
        if volume > 0 {
            previousVolume = volume
            setVolume(0)
        } else {
            let restore = previousVolume > 0 ? previousVolume : 20.0
            setVolume(restore)
        }
    }

    // MARK: - Transport Controls

    public func togglePlayPause() async {
        if nowPlaying?.isPlaying == true {
            await pause()
        } else {
            await play()
        }
    }

    public func play() async {
        guard let ip = selectedGroup?.coordinatorIP else { return }
        do {
            try await sonosService.play(ip: ip)
            try? await Task.sleep(nanoseconds: 200_000_000)
            await refreshNowPlaying(ip: ip)
        } catch {
            errorMessage = "Failed to play: \(error.localizedDescription)"
        }
    }

    public func pause() async {
        guard let ip = selectedGroup?.coordinatorIP else { return }
        do {
            try await sonosService.pause(ip: ip)
            try? await Task.sleep(nanoseconds: 200_000_000)
            await refreshNowPlaying(ip: ip)
        } catch {
            errorMessage = "Failed to pause: \(error.localizedDescription)"
        }
    }

    public func next() async {
        guard let ip = selectedGroup?.coordinatorIP else { return }
        do {
            try await sonosService.next(ip: ip)
            try? await Task.sleep(nanoseconds: 300_000_000)
            await refreshNowPlaying(ip: ip)
        } catch {
            errorMessage = "Failed to skip to next track: \(error.localizedDescription)"
        }
    }

    public func previous() async {
        guard let ip = selectedGroup?.coordinatorIP else { return }
        do {
            try await sonosService.previous(ip: ip)
            try? await Task.sleep(nanoseconds: 300_000_000)
            await refreshNowPlaying(ip: ip)
        } catch {
            errorMessage = "Failed to go to previous track: \(error.localizedDescription)"
        }
    }

    // MARK: - Background Polling

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                let interval = self?.settings.pollingInterval ?? 4.0
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard let self = self, !Task.isCancelled else { break }
                if self.serverStatus.isConnected {
                    if let ip = self.selectedGroup?.coordinatorIP {
                        await self.refreshNowPlaying(ip: ip)
                    } else if self.groups.isEmpty {
                        // Auto-recovery: if no groups were established (e.g. boot network hiccup), retry refreshAll
                        await self.refreshAll()
                    }
                }
            }
        }
    }
}
