import SwiftUI

public struct NowPlayingCardView: View {
    @ObservedObject var coordinator: SonosCoordinator

    public init(coordinator: SonosCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        HStack(spacing: 20) {
            // Hero Album Art
            ArtworkImageView(
                url: coordinator.currentArtworkURL,
                size: 130,
                cornerRadius: 10
            )
            .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 4)

            // Metadata & Controls
            VStack(alignment: .leading, spacing: 8) {
                // Status Pill & Room
                HStack(spacing: 8) {
                    statusPill

                    if let group = coordinator.selectedGroup {
                        Text(group.displayName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }

                // Title
                Text(coordinator.nowPlaying?.displayTitle ?? "No Track Loaded")
                    .font(.title2.weight(.bold))
                    .lineLimit(1)
                    .foregroundColor(.primary)

                // Subtitle (Artist • Album)
                Text(coordinator.nowPlaying?.displaySubtitle ?? "Select a group or favorite to begin")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                // Progress Bar
                if let np = coordinator.nowPlaying, np.durationSeconds > 0 {
                    VStack(spacing: 4) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.secondary.opacity(0.2))
                                    .frame(height: 4)

                                Capsule()
                                    .fill(Color.accentColor)
                                    .frame(width: geo.size.width * CGFloat(np.progressFraction), height: 4)
                            }
                        }
                        .frame(height: 4)

                        HStack {
                            Text(np.progress ?? "0:00")
                                .font(.system(size: 10, weight: .regular, design: .monospaced))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(np.duration ?? "0:00")
                                .font(.system(size: 10, weight: .regular, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.top, 2)
                }

                // Transport Controls
                HStack(spacing: 16) {
                    Button(action: {
                        Task { await coordinator.previous() }
                    }) {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 15))
                    }
                    .buttonStyle(.plain)
                    .help("Previous Track (⌘←)")
                    .accessibilityLabel("Previous Track")

                    Button(action: {
                        Task { await coordinator.togglePlayPause() }
                    }) {
                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .help("Play / Pause (Space)")
                    .accessibilityLabel(isPlaying ? "Pause" : "Play")

                    Button(action: {
                        Task { await coordinator.next() }
                    }) {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 15))
                    }
                    .buttonStyle(.plain)
                    .help("Next Track (⌘→)")
                    .accessibilityLabel("Next Track")

                    Spacer()
                }
                .padding(.top, 2)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                )
        )
    }

    private var isPlaying: Bool {
        coordinator.nowPlaying?.isPlaying ?? false
    }

    private var statusPill: some View {
        let state = coordinator.nowPlaying?.state.uppercased() ?? "STOPPED"
        let isPl = state == "PLAYING"
        let isPa = state == "PAUSED_PLAYBACK" || state == "PAUSED"

        return HStack(spacing: 4) {
            Circle()
                .fill(isPl ? Color.green : (isPa ? Color.orange : Color.secondary))
                .frame(width: 6, height: 6)
            Text(isPl ? "PLAYING" : (isPa ? "PAUSED" : state))
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(isPl ? .green : (isPa ? .orange : .secondary))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            isPl ? Color.green.opacity(0.12) :
            (isPa ? Color.orange.opacity(0.12) : Color.secondary.opacity(0.12))
        )
        .clipShape(Capsule())
    }
}
