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
    @Published public var memberVolumes: [String: Double] = [:]
    @Published public var groupPlaybackStates: [String: String] = [:]
    @Published public var isLoadingQueue: Bool = false
    @Published public var isRefreshing: Bool = false
    @Published public var isMiniPlayerMode: Bool = false
    @Published public var showingStreamPlayer: Bool = false
    @Published public var showingClearQueueConfirmation: Bool = false
    @Published public var errorMessage: String? = nil

    public func toggleMiniPlayerMode() {
        isMiniPlayerMode.toggle()
    }

    public let sonosService: SonosService
    public let settings: AppSettings

    var pollTask: Task<Void, Never>?
    var volumeDebounceTask: Task<Void, Never>?
    var memberVolumeDebounceTasks: [String: Task<Void, Never>] = [:]
    var lastUserVolumeChangeTime: Date = .distantPast
    var previousVolume: Double = 20.0

    public init(
        sonosService: SonosService = SonosService(),
        settings: AppSettings = .shared
    ) {
        self.sonosService = sonosService
        self.settings = settings
        setupMediaManager()
    }

    deinit {
        pollTask?.cancel()
        volumeDebounceTask?.cancel()
    }

    private func setupMediaManager() {
        let manager = NowPlayingMediaManager.shared
        manager.onPlay = { [weak self] in await self?.play() }
        manager.onPause = { [weak self] in await self?.pause() }
        manager.onTogglePlayPause = { [weak self] in await self?.togglePlayPause() }
        manager.onNext = { [weak self] in await self?.next() }
        manager.onPrevious = { [weak self] in await self?.previous() }
        manager.onSeekTime = { [weak self] seconds in await self?.seekTime(seconds: seconds) }
        manager.configureRemoteCommands()
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

    // MARK: - Background Polling

    func startPolling() {
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
