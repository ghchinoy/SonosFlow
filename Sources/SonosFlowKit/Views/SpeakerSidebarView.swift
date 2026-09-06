import SwiftUI

public struct SpeakerSidebarView: View {
    @ObservedObject var coordinator: SonosCoordinator
    @Binding var showingFavorites: Bool
    @Binding var showingSettings: Bool

    public init(
        coordinator: SonosCoordinator,
        showingFavorites: Binding<Bool>,
        showingSettings: Binding<Bool>
    ) {
        self.coordinator = coordinator
        self._showingFavorites = showingFavorites
        self._showingSettings = showingSettings
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Server Connection Status Header
            serverStatusHeader
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

            Divider()

            // Zone Groups List
            List(selection: Binding(
                get: { coordinator.selectedGroup?.id },
                set: { newId in
                    if let newId = newId, let group = coordinator.groups.first(where: { $0.id == newId }) {
                        Task { await coordinator.selectGroup(group) }
                    }
                }
            )) {
                Section {
                    if coordinator.groups.isEmpty {
                        VStack(spacing: 8) {
                            Text(coordinator.isRefreshing ? "Scanning network..." : "No groups found")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            if !coordinator.isRefreshing {
                                Button("Rescan Network") {
                                    Task { await coordinator.refreshAll(forceNetworkScan: true) }
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    } else {
                        ForEach(coordinator.groups) { group in
                            GroupRowView(
                                group: group,
                                isSelected: coordinator.selectedGroup?.id == group.id,
                                playbackState: coordinator.groupPlaybackStates[group.id]
                            )
                            .tag(group.id)
                        }
                    }
                } header: {
                    Text("SPEAKER GROUPS")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(.secondary)
                }
            }
            .listStyle(.sidebar)

            Divider()

            // Bottom Toolbar
            bottomToolbar
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
        }
        .frame(minWidth: 230)
    }

    private var serverStatusHeader: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 9, height: 9)

            VStack(alignment: .leading, spacing: 1) {
                Text(statusTitle)
                    .font(.caption.weight(.semibold))
                Text(statusSubtitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if coordinator.isRefreshing {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button(action: {
                    Task { await coordinator.reloadServer() }
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("Reload MCP Server & Re-sync (⌘⇧R)")
                .accessibilityLabel("Reload MCP Server and refresh speakers")
            }
        }
    }

    private var statusColor: Color {
        switch coordinator.serverStatus {
        case .connected: return .green
        case .connecting: return .orange
        case .disconnected: return .secondary
        case .error: return .red
        }
    }

    private var statusTitle: String {
        switch coordinator.serverStatus {
        case .connected(let info, _): return info.name
        case .connecting: return "Connecting to MCP..."
        case .disconnected: return "Sonos MCP Offline"
        case .error: return "Connection Error"
        }
    }

    private var statusSubtitle: String {
        switch coordinator.serverStatus {
        case .connected(_, let tools): return "\(tools.count) tools active"
        case .connecting: return "Starting mcp-sonos..."
        case .disconnected: return "Click to reconnect"
        case .error(let msg): return msg
        }
    }

    private var bottomToolbar: some View {
        HStack(spacing: 12) {
            Button(action: { showingFavorites = true }) {
                Label("Favorites", systemImage: "star.fill")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.plain)
            .help("Browse Sonos Favorites (⌘F)")

            Spacer()

            Button(action: { showingSettings = true }) {
                Image(systemName: "gearshape")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Sonos MCP Settings (⌘,)")
        }
    }
}

public struct GroupRowView: View {
    public let group: TopologyGroup
    public let isSelected: Bool
    public let playbackState: String?

    public var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1))
                    .frame(width: 32, height: 32)

                if isPlaying {
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.green)
                } else if isPaused {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                } else {
                    Image(systemName: group.isPair ? "hifispeaker.2" : "hifispeaker")
                        .font(.system(size: 14))
                        .foregroundColor(isSelected ? .accentColor : .secondary)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(group.displayName)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .foregroundColor(isSelected ? .primary : .primary.opacity(0.9))

                Text(group.subtitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if isPlaying {
                Text("PLAYING")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.green)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.12))
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }

    private var isPlaying: Bool {
        playbackState?.uppercased() == "PLAYING"
    }

    private var isPaused: Bool {
        playbackState?.uppercased() == "PAUSED_PLAYBACK" || playbackState?.uppercased() == "PAUSED"
    }
}
