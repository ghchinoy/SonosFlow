import SwiftUI
import AppKit

public struct MiniPlayerView: View {
    @ObservedObject var coordinator: SonosCoordinator

    public init(coordinator: SonosCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        HStack(spacing: 12) {
            // Left: Album Art
            ArtworkImageView(
                url: coordinator.currentArtworkURL,
                size: 84,
                cornerRadius: 8
            )
            .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)

            // Right: Info & Controls
            VStack(alignment: .leading, spacing: 4) {
                // Top Header: Room Selector Menu & Expand Button
                HStack(spacing: 6) {
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
                        HStack(spacing: 4) {
                            Image(systemName: isPlaying ? "speaker.wave.2.fill" : "hifispeaker")
                                .font(.system(size: 9))
                                .foregroundColor(isPlaying ? .green : .secondary)
                            Text(coordinator.selectedGroup?.displayName ?? "Select Room")
                                .font(.system(size: 11, weight: .semibold))
                                .lineLimit(1)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 7))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(Capsule())
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()

                    Spacer()

                    // Expand to Full Window Button
                    Button(action: {
                        coordinator.toggleMiniPlayerMode()
                    }) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Expand to Full Window (⌘M)")
                }

                // Track Title
                Text(coordinator.nowPlaying?.displayTitle ?? "No Track Loaded")
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)
                    .foregroundColor(.primary)

                // Artist • Album
                Text(coordinator.nowPlaying?.displaySubtitle ?? "Idle")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                // Slim Progress Bar
                if let np = coordinator.nowPlaying, np.durationSeconds > 0 {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.secondary.opacity(0.2))
                                .frame(height: 2)

                            Capsule()
                                .fill(Color.accentColor)
                                .frame(width: geo.size.width * CGFloat(np.progressFraction), height: 2)
                        }
                    }
                    .frame(height: 2)
                    .padding(.top, 1)
                }

                // Transport & Volume Bar
                HStack(spacing: 12) {
                    // Prev
                    Button(action: { Task { await coordinator.previous() } }) {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .help("Previous (⌘←)")

                    // Play / Pause
                    Button(action: { Task { await coordinator.togglePlayPause() } }) {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .help("Play / Pause (Space)")

                    // Next
                    Button(action: { Task { await coordinator.next() } }) {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .help("Next (⌘→)")

                    Spacer()

                    // Mute / Vol -
                    Button(action: { coordinator.stepVolume(delta: -coordinator.settings.volumeDelta) }) {
                        Image(systemName: "minus")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)

                    // Volume Text
                    Text("\(Int(coordinator.volume))%")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)

                    // Vol +
                    Button(action: { coordinator.stepVolume(delta: coordinator.settings.volumeDelta) }) {
                        Image(systemName: "plus")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 2)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }

    private var isPlaying: Bool {
        coordinator.nowPlaying?.isPlaying ?? false
    }
}
