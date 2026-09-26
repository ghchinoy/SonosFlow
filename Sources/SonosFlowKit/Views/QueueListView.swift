import SwiftUI
import AppKit

public struct QueueListView: View {
    @ObservedObject var coordinator: SonosCoordinator
    @Binding var showingFavorites: Bool
    @State private var searchText: String = ""
    @State private var selectedTrackId: String? = nil

    public init(coordinator: SonosCoordinator, showingFavorites: Binding<Bool>) {
        self.coordinator = coordinator
        self._showingFavorites = showingFavorites
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Queue Header Bar
            headerBar
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)

            Divider()

            // Active Filter Banner
            if isFiltering {
                HStack(spacing: 8) {
                    Image(systemName: "line.3.horizontal.decrease.circle.fill")
                        .foregroundColor(.accentColor)
                        .font(.caption)

                    Text("Showing \(filteredItems.count) of \(coordinator.queueItems.count) tracks matching \"\(searchText)\"")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.primary)

                    Spacer()

                    Button(action: { searchText = "" }) {
                        Text("Clear Filter (Esc)")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(.accentColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.06))

                Divider()
            }

            // Main Queue List, Empty Search, or Empty Queue State
            if coordinator.isLoadingQueue && coordinator.queueItems.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    ProgressView()
                    Text("Loading Sonos queue...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if coordinator.queueItems.isEmpty {
                emptyQueueView
            } else if filteredItems.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary.opacity(0.4))
                    Text("No tracks matching \"\(searchText)\"")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Button("Clear Filter") {
                        searchText = ""
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedTrackId) {
                    ForEach(filteredItems) { item in
                        QueueItemRow(
                            item: item,
                            coordinatorIP: coordinator.selectedGroup?.coordinatorIP ?? "",
                            isCurrentTrack: isCurrentlyPlaying(item: item),
                            isSelected: selectedTrackId == item.id,
                            totalTracks: coordinator.queueTotalMatches > 0 ? coordinator.queueTotalMatches : coordinator.queueItems.count,
                            isFiltering: isFiltering,
                            onPlay: {
                                Task { await coordinator.playQueueItem(item) }
                            },
                            onPlayNext: {
                                Task { await coordinator.playNextInQueue(item) }
                            },
                            onRemove: {
                                Task { await coordinator.removeQueueItem(item) }
                            }
                        )
                        .tag(item.id)
                        .listRowInsets(EdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10))
                    }
                    .onMove(perform: isFiltering ? nil : { indices, newOffset in
                        Task {
                            await coordinator.moveQueueItems(from: indices, to: newOffset)
                        }
                    })
                    .onDelete { indexSet in
                        for idx in indexSet {
                            if idx < filteredItems.count {
                                let item = filteredItems[idx]
                                Task { await coordinator.removeQueueItem(item) }
                            }
                        }
                    }
                }
                .listStyle(.inset)
                .onKeyPress(.return) {
                    if let selId = selectedTrackId, let item = coordinator.queueItems.first(where: { $0.id == selId }) {
                        Task { await coordinator.playQueueItem(item) }
                        return .handled
                    }
                    return .ignored
                }
                .onKeyPress(.delete) {
                    if let selId = selectedTrackId, let item = coordinator.queueItems.first(where: { $0.id == selId }) {
                        Task { await coordinator.removeQueueItem(item) }
                        return .handled
                    }
                    return .ignored
                }
            }
        }
        .confirmationDialog(
            "Clear Playback Queue",
            isPresented: $coordinator.showingClearQueueConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear All Tracks", role: .destructive) {
                Task { await coordinator.clearQueue() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to remove all tracks from the queue on \(coordinator.selectedGroup?.displayName ?? "this speaker")?")
        }
    }

    private var headerBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "list.bullet")
                    .foregroundColor(.accentColor)
                    .font(.subheadline.weight(.semibold))

                Text("Queue")
                    .font(.headline)

                if coordinator.queueTotalMatches > 0 {
                    Text("(\(coordinator.queueTotalMatches))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Filter Search Field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.caption)

                TextField("Filter queue...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.caption)
                    .onExitCommand {
                        searchText = ""
                    }

                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .frame(width: 170)

            // Clear Queue Button
            if !coordinator.queueItems.isEmpty {
                Button(action: { coordinator.showingClearQueueConfirmation = true }) {
                    Text("Clear")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear Queue (⌘⌫)")
                .accessibilityLabel("Clear playback queue")
            }

            // Refresh Button
            Button(action: {
                Task { await coordinator.refreshQueue() }
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Refresh Queue (⌘R)")
            .accessibilityLabel("Refresh playback queue")
        }
    }

    private var emptyQueueView: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "music.note.list")
                .font(.system(size: 42))
                .foregroundColor(.secondary.opacity(0.4))

            Text("Playback queue is empty")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("Play a track from your Sonos favorites or send music from your streaming service.")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.8))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)

            Button(action: { showingFavorites = true }) {
                Label("Browse Favorites", systemImage: "star.fill")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .padding(.top, 4)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var isFiltering: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var filteredItems: [QueueItem] {
        let clean = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return coordinator.queueItems }
        return coordinator.queueItems.filter { item in
            item.title.localizedCaseInsensitiveContains(clean) ||
            item.artist.localizedCaseInsensitiveContains(clean) ||
            (item.album?.localizedCaseInsensitiveContains(clean) ?? false)
        }
    }

    private func isCurrentlyPlaying(item: QueueItem) -> Bool {
        guard let np = coordinator.nowPlaying, !np.isStopped else { return false }
        if let npTitle = np.title, !npTitle.isEmpty {
            return item.title == npTitle
        }
        return false
    }
}

public struct QueueItemRow: View {
    public let item: QueueItem
    public let coordinatorIP: String
    public let isCurrentTrack: Bool
    public let isSelected: Bool
    public let totalTracks: Int
    public let isFiltering: Bool
    public let onPlay: () -> Void
    public let onPlayNext: () -> Void
    public let onRemove: () -> Void

    @State private var isHovering: Bool = false

    public var body: some View {
        HStack(spacing: 10) {
            // Reorder Drag Affordance (only visible when not filtering)
            if !isFiltering {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 11))
                    .foregroundColor(isHovering ? .secondary.opacity(0.8) : .clear)
                    .frame(width: 14)
            }

            // Track Number or Play Indicator
            ZStack {
                if isCurrentTrack {
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.green)
                } else if isHovering {
                    Button(action: onPlay) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Play track \(item.title)")
                } else {
                    Text("\(item.position)")
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundColor(.secondary)
                        .help("Queue position #\(item.position) of \(totalTracks)")
                }
            }
            .frame(width: 24, alignment: .center)

            // Artwork Thumbnail
            ArtworkImageView(
                url: item.resolvedAlbumArtURL(coordinatorIP: coordinatorIP),
                size: 44,
                cornerRadius: 6
            )

            // Title & Artist
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.body.weight(isCurrentTrack ? .bold : .medium))
                    .foregroundColor(isCurrentTrack ? .accentColor : .primary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(item.artist)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)

                    if let album = item.album, !album.isEmpty {
                        Text("•")
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.5))
                        Text(album)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            // Hover Delete Button
            if isHovering {
                Button(action: onRemove) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundColor(.red.opacity(0.8))
                }
                .buttonStyle(.plain)
                .help("Remove from Queue")
                .accessibilityLabel("Remove \(item.title) from queue")
            }

            // Duration
            if let dur = item.duration, !dur.isEmpty {
                Text(dur)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isCurrentTrack ? Color.accentColor.opacity(0.08) : (isSelected ? Color.accentColor.opacity(0.12) : (isHovering ? Color.secondary.opacity(0.06) : Color.clear)))
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
        .onTapGesture(count: 2) {
            onPlay()
        }
        .contextMenu {
            Button("Play Track Now") {
                onPlay()
            }
            Button("Play Next") {
                onPlayNext()
            }
            Divider()
            Button(role: .destructive, action: onRemove) {
                Label("Remove from Queue", systemImage: "trash")
            }
            Divider()
            Button("Copy Track Title") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.title, forType: .string)
            }
            if !item.artist.isEmpty {
                Button("Copy Artist") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(item.artist, forType: .string)
                }
            }
        }
    }
}
