import SwiftUI

public struct FavoritesPopoverView: View {
    @ObservedObject var coordinator: SonosCoordinator
    @Environment(\.dismiss) private var dismiss

    public init(coordinator: SonosCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                    Text("Sonos Favorites")
                        .font(.headline)
                }

                Spacer()

                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.body)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)

            Divider()

            // List of Favorites
            if coordinator.favorites.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "star.slash")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary.opacity(0.4))
                    Text("No Sonos Favorites Found")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.secondary)
                    Text("Pin playlists or radio stations in your Sonos app to access them quickly here.")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(coordinator.favorites) { fav in
                        FavoriteRowView(
                            favorite: fav,
                            coordinatorIP: coordinator.selectedGroup?.coordinatorIP ?? "",
                            onSelect: {
                                Task {
                                    await coordinator.playFavorite(fav)
                                    dismiss()
                                }
                            }
                        )
                        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(width: 380, height: 420)
    }
}

public struct FavoriteRowView: View {
    public let favorite: SonosFavorite
    public let coordinatorIP: String
    public let onSelect: () -> Void

    @State private var isHovering: Bool = false

    public var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                ArtworkImageView(
                    url: favorite.resolvedAlbumArtURL(coordinatorIP: coordinatorIP),
                    size: 44,
                    cornerRadius: 6
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(favorite.title)
                        .font(.body.weight(.medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    if let desc = favorite.description, !desc.isEmpty {
                        Text(desc)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Image(systemName: "play.fill")
                    .font(.caption)
                    .foregroundColor(isHovering ? .accentColor : .clear)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovering ? Color.secondary.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}
