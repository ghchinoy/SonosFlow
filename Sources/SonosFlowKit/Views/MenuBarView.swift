import SwiftUI
import AppKit

public struct MenuBarView: View {
    @ObservedObject var coordinator: SonosCoordinator

    public init(coordinator: SonosCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        VStack(spacing: 12) {
            // Room Selection Bar
            HStack {
                Menu {
                    ForEach(coordinator.groups) { group in
                        Button(action: {
                            Task { await coordinator.selectGroup(group) }
                        }) {
                            HStack {
                                Text(group.displayName)
                                if group.id == coordinator.selectedGroup?.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isPlaying ? "speaker.wave.3.fill" : "hifispeaker")
                            .font(.system(size: 11))
                            .foregroundColor(isPlaying ? .green : .secondary)
                        Text(coordinator.selectedGroup?.displayName ?? "Select Room")
                            .font(.subheadline.weight(.semibold))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                    }
                }
                .menuStyle(.borderlessButton)

                Spacer()

                // Refresh Button
                Button(action: {
                    Task { await coordinator.refreshAll() }
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            Divider()

            // Now Playing Card
            HStack(spacing: 12) {
                ArtworkImageView(
                    url: coordinator.currentArtworkURL,
                    size: 54,
                    cornerRadius: 6
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(coordinator.nowPlaying?.displayTitle ?? "No Track Loaded")
                        .font(.body.weight(.bold))
                        .lineLimit(1)

                    Text(coordinator.nowPlaying?.displaySubtitle ?? "Idle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)

                    if let np = coordinator.nowPlaying, np.durationSeconds > 0 {
                        Text("\(np.progress ?? "0:00") / \(np.duration ?? "0:00")")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }

            // Transport Controls
            HStack(spacing: 16) {
                Button(action: { Task { await coordinator.previous() } }) {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)

                Button(action: { Task { await coordinator.togglePlayPause() } }) {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 26))
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)

                Button(action: { Task { await coordinator.next() } }) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)

                Spacer()

                // Volume slider
                Slider(
                    value: Binding(
                        get: { coordinator.volume },
                        set: { coordinator.setVolume($0) }
                    ),
                    in: 0...100,
                    step: 1
                )
                .controlSize(.small)
                .frame(width: 90)

                Text("\(Int(coordinator.volume))%")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 28, alignment: .trailing)
            }

            // Quick Pinned Favorites
            if coordinator.capabilities.supportsFavorites && !coordinator.favorites.isEmpty {
                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Text("FAVORITES")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)

                    ForEach(coordinator.favorites.prefix(3)) { fav in
                        Button(action: {
                            Task { await coordinator.playFavorite(fav) }
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 9))
                                    .foregroundColor(.yellow)
                                Text(fav.title)
                                    .font(.caption)
                                    .lineLimit(1)
                                Spacer()
                                Image(systemName: "play.fill")
                                    .font(.system(size: 8))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Divider()

            // Footer Actions
            HStack {
                Button("Open SonosFlow") {
                    NSApp.activate(ignoringOtherApps: true)
                    for window in NSApp.windows where !window.className.contains("NSStatusBarWindow") {
                        window.makeKeyAndOrderFront(nil)
                    }
                }
                .font(.caption)
                .buttonStyle(.plain)

                Spacer()

                Button("Miniplayer") {
                    coordinator.isMiniPlayerMode = true
                    NSApp.activate(ignoringOtherApps: true)
                }
                .font(.caption)
                .buttonStyle(.plain)

                Text("•")
                    .foregroundColor(.secondary.opacity(0.4))
                    .font(.caption2)

                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundColor(.red.opacity(0.8))
            }
        }
        .padding(14)
        .frame(width: 300)
    }

    private var isPlaying: Bool {
        coordinator.nowPlaying?.isPlaying ?? false
    }
}
