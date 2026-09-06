import Foundation
import MediaPlayer
import AppKit

/// Bridges SonosFlow playback state to macOS Control Center and hardware media keys (F7, F8, F9).
@MainActor
public final class NowPlayingMediaManager {
    public static let shared = NowPlayingMediaManager()

    public var onPlay: (() async -> Void)?
    public var onPause: (() async -> Void)?
    public var onTogglePlayPause: (() async -> Void)?
    public var onNext: (() async -> Void)?
    public var onPrevious: (() async -> Void)?
    public var onSeekTime: ((Double) async -> Void)?

    private var isConfigured = false

    private init() {}

    /// Registers remote commands for macOS Control Center and keyboard media keys.
    public func configureRemoteCommands() {
        guard !isConfigured else { return }
        isConfigured = true

        let center = MPRemoteCommandCenter.shared()

        // 1. Play
        center.playCommand.isEnabled = true
        center.playCommand.addTarget { [weak self] _ in
            guard let self = self, let handler = self.onPlay else { return .commandFailed }
            Task { @MainActor in await handler() }
            return .success
        }

        // 2. Pause
        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget { [weak self] _ in
            guard let self = self, let handler = self.onPause else { return .commandFailed }
            Task { @MainActor in await handler() }
            return .success
        }

        // 3. Toggle Play/Pause (F8 key, headphone buttons)
        center.togglePlayPauseCommand.isEnabled = true
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self = self, let handler = self.onTogglePlayPause else { return .commandFailed }
            Task { @MainActor in await handler() }
            return .success
        }

        // 4. Next Track (F9 key)
        center.nextTrackCommand.isEnabled = true
        center.nextTrackCommand.addTarget { [weak self] _ in
            guard let self = self, let handler = self.onNext else { return .commandFailed }
            Task { @MainActor in await handler() }
            return .success
        }

        // 5. Previous Track (F7 key)
        center.previousTrackCommand.isEnabled = true
        center.previousTrackCommand.addTarget { [weak self] _ in
            guard let self = self, let handler = self.onPrevious else { return .commandFailed }
            Task { @MainActor in await handler() }
            return .success
        }

        // 6. Scrubbing / Position Change
        center.changePlaybackPositionCommand.isEnabled = true
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self = self,
                  let posEvent = event as? MPChangePlaybackPositionCommandEvent,
                  let handler = self.onSeekTime else {
                return .commandFailed
            }
            Task { @MainActor in await handler(posEvent.positionTime) }
            return .success
        }

        AppLogger.shared.log("MPRemoteCommandCenter hardware media keys configured", category: "MEDIA")
    }

    /// Updates macOS Control Center Now Playing widget and lock screen information.
    public func updateNowPlaying(
        title: String,
        artist: String?,
        album: String?,
        duration: Double,
        elapsed: Double,
        isPlaying: Bool,
        artwork: NSImage? = nil
    ) {
        var info: [String: Any] = [:]

        info[MPMediaItemPropertyTitle] = title
        if let artist = artist, !artist.isEmpty {
            info[MPMediaItemPropertyArtist] = artist
        }
        if let album = album, !album.isEmpty {
            info[MPMediaItemPropertyAlbumTitle] = album
        }

        if duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
        }

        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0

        if let img = artwork {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: img.size) { _ in img }
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : (duration > 0 ? .paused : .stopped)
    }

    /// Clears the Control Center Now Playing widget.
    public func clearNowPlaying() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
    }
}
