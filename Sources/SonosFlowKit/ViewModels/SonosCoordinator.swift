import Foundation
import SwiftUI
import Combine

@MainActor
public final class SonosCoordinator: ObservableObject {
    @Published public var serverStatus: MCPServerStatus = .disconnected
    @Published public var groups: [TopologyGroup] = []
    @Published public var selectedGroup: TopologyGroup? = nil
    @Published public var nowPlaying: NowPlayingResult? = nil
    @Published public var upNextTrack: UpNextTrack? = nil
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
    @Published public var capabilities: ServerCapabilities = .localDefault
    @Published public var backend: any SonosBackend

    public func toggleMiniPlayerMode() {
        isMiniPlayerMode.toggle()
    }

    public var sonosService: SonosService {
        if let local = backend as? LocalHomectlBackend {
            return local.service
        }
        return SonosService()
    }

    public let settings: AppSettings

    var pollTask: Task<Void, Never>?
    var volumeDebounceTask: Task<Void, Never>?
    var memberVolumeDebounceTasks: [String: Task<Void, Never>] = [:]
    var lastUserVolumeChangeTime: Date = .distantPast
    var previousVolume: Double = 20.0

    public init(
        backend: any SonosBackend,
        settings: AppSettings = .shared
    ) {
        self.backend = backend
        self.settings = settings
        self.capabilities = backend.capabilities
        setupMediaManager()
    }

    public convenience init(
        sonosService: SonosService = SonosService(),
        settings: AppSettings = .shared
    ) {
        let backend = LocalHomectlBackend(service: sonosService, settings: settings)
        self.init(backend: backend, settings: settings)
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

        // Ensure backend matches user setting
        if settings.controlEngine == .cloud && !(backend is SonosCloudBackend) {
            self.backend = SonosCloudBackend()
        } else if settings.controlEngine == .local && !(backend is LocalHomectlBackend) {
            self.backend = LocalHomectlBackend(service: SonosService(), settings: settings)
        }

        do {
            let (serverInfo, tools) = try await backend.connect()
            self.capabilities = backend.capabilities
            serverStatus = .connected(serverInfo: serverInfo, tools: tools)
            AppLogger.shared.log("Connected to \(serverInfo.name) (\(backend.engine.shortBadge)) with \(tools.count) tools", category: "COORDINATOR")
            await refreshAll()
            startPolling()
        } catch {
            serverStatus = .error(error.localizedDescription)
            errorMessage = "Connection error (\(settings.controlEngine.shortBadge)): \(error.localizedDescription)"
            AppLogger.shared.error("Connection failed: \(error)", category: "COORDINATOR")
        }
    }

    public func disconnect() async {
        pollTask?.cancel()
        pollTask = nil
        await backend.disconnect()
        serverStatus = .disconnected
    }

    /// Switches the active control engine between Local and Cloud without auto-fallback
    public func switchEngine(to newEngine: ControlEngine) async {
        guard newEngine != settings.controlEngine else { return }
        settings.controlEngine = newEngine
        await disconnect()

        if newEngine == .cloud {
            self.backend = SonosCloudBackend()
        } else {
            self.backend = LocalHomectlBackend(service: SonosService(), settings: settings)
        }
        self.capabilities = backend.capabilities

        // Reset system state
        self.groups = []
        self.selectedGroup = nil
        self.nowPlaying = nil
        self.upNextTrack = nil
        self.queueItems = []
        self.queueTotalMatches = 0

        await connectAndInitialize()
    }

    /// Reloads the active backend connection and refreshes state
    public func reloadServer() async {
        isRefreshing = true
        serverStatus = .connecting
        AppLogger.shared.log("Reloading Sonos \(settings.controlEngine.shortBadge) Backend...", category: "COORDINATOR")

        await backend.disconnect()
        try? await Task.sleep(nanoseconds: 150_000_000)

        do {
            let (serverInfo, tools) = try await backend.connect()
            self.capabilities = backend.capabilities
            serverStatus = .connected(serverInfo: serverInfo, tools: tools)
            AppLogger.shared.log("Reloaded \(serverInfo.name) with \(tools.count) tools", category: "COORDINATOR")
            await refreshAll(forceNetworkScan: false)
            errorMessage = nil
        } catch {
            serverStatus = .error(error.localizedDescription)
            errorMessage = "Failed to reload: \(error.localizedDescription)"
            AppLogger.shared.error("reloadServer failed: \(error)", category: "COORDINATOR")
        }
        isRefreshing = false
    }

    // MARK: - Background Polling

    func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                // In cloud mode, default to 6.0s polling to respect cloud rate limits & ~220ms latency
                let defaultInterval = self?.settings.controlEngine == .cloud ? 6.0 : 4.0
                let interval = max(2.0, self?.settings.pollingInterval ?? defaultInterval)
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard let self = self, !Task.isCancelled else { break }

                if self.serverStatus.isConnected {
                    if self.selectedGroup != nil {
                        await self.refreshNowPlaying()
                    } else if self.groups.isEmpty {
                        await self.refreshAll()
                    }
                }
            }
        }
    }
}
