import SwiftUI
import AppKit

public struct MainSplitView: View {
    @ObservedObject public var coordinator: SonosCoordinator
    @State private var showingFavorites: Bool = false
    @State private var showingSettings: Bool = false
    @State private var eventMonitor: Any? = nil
    @State private var currentWindow: NSWindow? = nil
    @State private var savedWindowFrame: NSRect = .zero

    public init(coordinator: SonosCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        Group {
            if coordinator.isMiniPlayerMode {
                MiniPlayerView(coordinator: coordinator)
                    .frame(minWidth: 320, maxWidth: .infinity, minHeight: 110, maxHeight: 110)
            } else {
                fullSplitView
                    .frame(minWidth: 860, minHeight: 620)
            }
        }
        .background(
            WindowAccessor { win in
                if currentWindow == nil {
                    currentWindow = win
                    updateProxyIcon()
                }
            }
        )
        .onChange(of: coordinator.isMiniPlayerMode) { _, isMini in
            handleMiniPlayerModeChange(isMini)
        }
        .onChange(of: coordinator.currentArtworkURL) { _, _ in
            updateProxyIcon()
        }
        .onChange(of: coordinator.nowPlaying) { _, _ in
            updateProxyIcon()
        }
        .sheet(isPresented: $showingFavorites) {
            FavoritesPopoverView(coordinator: coordinator)
        }
        .sheet(isPresented: $coordinator.showingStreamPlayer) {
            StreamPlayerSheetView(coordinator: coordinator)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(settings: coordinator.settings, coordinator: coordinator)
        }
        .onAppear {
            setupKeyboardMonitor()
        }
        .onDisappear {
            if let monitor = eventMonitor {
                NSEvent.removeMonitor(monitor)
                eventMonitor = nil
            }
        }
        .task {
            await coordinator.connectAndInitialize()
        }
    }

    private var fullSplitView: some View {
        NavigationSplitView {
            SpeakerSidebarView(
                coordinator: coordinator,
                showingFavorites: $showingFavorites,
                showingStreamPlayer: $coordinator.showingStreamPlayer,
                showingSettings: $showingSettings
            )
        } detail: {
            VStack(spacing: 0) {
                // Header Bar with Group Info and Volume Control
                topHeaderBar
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial)

                Divider()

                // Error Banner if any
                if let error = coordinator.errorMessage {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.subheadline)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.primary)
                            .lineLimit(2)
                        Spacer()
                        Button(action: { coordinator.errorMessage = nil }) {
                            Image(systemName: "xmark")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.orange.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                }

                // Center Stage Canvas
                VStack(spacing: 16) {
                    // Now Playing Hero Card
                    NowPlayingCardView(coordinator: coordinator)

                    // Playback Queue Section
                    QueueListView(
                        coordinator: coordinator,
                        showingFavorites: $showingFavorites
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                    )
                }
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var topHeaderBar: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(coordinator.selectedGroup?.displayName ?? "Select a Speaker")
                        .font(.title3.weight(.bold))

                    if let group = coordinator.selectedGroup, group.isPair {
                        Text("PAIR")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15))
                            .foregroundColor(.accentColor)
                            .clipShape(Capsule())
                    }
                }

                if let group = coordinator.selectedGroup {
                    Text("Coordinator: \(group.coordinatorIP ?? "Unknown IP") • \(group.members.count) speaker\(group.members.count == 1 ? "" : "s")")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // MiniPlayer Button
            Button(action: { coordinator.toggleMiniPlayerMode() }) {
                Image(systemName: "pip.enter")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Miniplayer Mode (⌘M)")

            // Master Volume Control Bar
            TransportBarView(coordinator: coordinator)
        }
    }

    private func updateProxyIcon() {
        guard let window = currentWindow else { return }
        Task {
            if let artURL = coordinator.currentArtworkURL,
               let fileURL = await ArtworkCache.shared.cachedFileURL(for: artURL) {
                window.representedURL = fileURL
                if let track = coordinator.nowPlaying, let title = track.title, !title.isEmpty {
                    window.title = "\(title) — \(track.artist ?? "")"
                }
            } else {
                window.representedURL = nil
                window.title = "SonosFlow"
            }
        }
    }

    private func handleMiniPlayerModeChange(_ isMini: Bool) {
        guard let window = currentWindow else { return }
        if isMini {
            if savedWindowFrame == .zero {
                savedWindowFrame = window.frame
            }
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.minSize = NSSize(width: 320, height: 110)
            window.maxSize = NSSize(width: 480, height: 110)
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true

            let miniWidth: CGFloat = 340
            let miniHeight: CGFloat = 110
            let newX = savedWindowFrame.minX
            let newY = savedWindowFrame.maxY - miniHeight
            let newFrame = NSRect(x: newX, y: newY, width: miniWidth, height: miniHeight)
            window.setFrame(newFrame, display: true, animate: true)
        } else {
            window.level = .normal
            window.collectionBehavior = []
            window.minSize = NSSize(width: 860, height: 620)
            window.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            window.titleVisibility = .visible
            window.titlebarAppearsTransparent = false
            window.isMovableByWindowBackground = false

            if savedWindowFrame != .zero {
                window.setFrame(savedWindowFrame, display: true, animate: true)
                savedWindowFrame = .zero
            }
        }
    }

    private func setupKeyboardMonitor() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = event.modifierFlags.intersection([.command, .control, .option])

            // If a text editing view has focus, let it handle typing
            let targetWindow = event.window ?? NSApp.keyWindow
            if let firstResponder = targetWindow?.firstResponder {
                if firstResponder is NSTextView || firstResponder is NSTextField || firstResponder is NSTextInputClient {
                    return event
                }
            }

            // Esc (key code 53) -> exit miniplayer mode if active
            if event.keyCode == 53 && coordinator.isMiniPlayerMode {
                coordinator.toggleMiniPlayerMode()
                return nil
            }

            // Spacebar (key code 49) -> Play/Pause
            if event.keyCode == 49 && modifiers.isEmpty {
                Task { @MainActor in
                    await coordinator.togglePlayPause()
                }
                return nil
            }

            // Command + Shift Shortcuts
            if modifiers == [.command, .shift] {
                if event.keyCode == 15 { // 'R' -> Reload Server
                    Task { @MainActor in await coordinator.reloadServer() }
                    return nil
                }
            }

            // Command Shortcuts
            if modifiers == .command {
                switch event.keyCode {
                case 46: // 'M' -> Toggle MiniPlayer
                    coordinator.toggleMiniPlayerMode()
                    return nil
                case 124: // Right Arrow -> Next Track
                    Task { @MainActor in await coordinator.next() }
                    return nil
                case 123: // Left Arrow -> Prev Track
                    Task { @MainActor in await coordinator.previous() }
                    return nil
                case 126: // Up Arrow -> Volume +5%
                    coordinator.stepVolume(delta: coordinator.settings.volumeDelta)
                    return nil
                case 125: // Down Arrow -> Volume -5%
                    coordinator.stepVolume(delta: -coordinator.settings.volumeDelta)
                    return nil
                case 15: // 'R' -> Refresh
                    Task { @MainActor in await coordinator.refreshAll() }
                    return nil
                case 3: // 'F' -> Favorites
                    showingFavorites = true
                    return nil
                case 32: // 'U' -> Audio Stream
                    coordinator.showingStreamPlayer = true
                    return nil
                case 43: // ',' -> Settings
                    showingSettings = true
                    return nil
                default:
                    break
                }
            }

            return event
        }
    }
}
