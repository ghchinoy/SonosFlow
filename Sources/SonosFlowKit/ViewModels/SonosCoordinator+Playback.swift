import Foundation
import AppKit

extension SonosCoordinator {
    // MARK: - Playback, Transport & Audio Streams

    /// Resolves the album art URL for the currently playing track/stream
    public var currentArtworkURL: URL? {
        let coordIP = selectedGroup?.coordinatorIP ?? ""
        if let np = nowPlaying, let art = np.mediaURI ?? np.trackURI, !art.isEmpty {
            if art.hasPrefix("http://") || art.hasPrefix("https://") {
                return URL(string: art)
            }
        }
        if let np = nowPlaying, let title = np.title, !title.isEmpty {
            if let matched = queueItems.first(where: { $0.title == title }) {
                return matched.resolvedAlbumArtURL(coordinatorIP: coordIP)
            }
        }
        if let np = nowPlaying {
            let query = np.title ?? np.streamContent ?? ""
            if !query.isEmpty {
                if let fav = favorites.first(where: { $0.title.localizedCaseInsensitiveContains(query) || query.localizedCaseInsensitiveContains($0.title) }) {
                    return fav.resolvedAlbumArtURL(coordinatorIP: coordIP)
                }
            }
        }
        return nil
    }

    public func refreshNowPlaying(ip: String? = nil) async {
        let target: SonosTarget
        if let ip = ip, !ip.isEmpty {
            target = .local(ip)
        } else if let group = selectedGroup {
            target = group.target
        } else {
            return
        }

        do {
            let np = try await backend.getNowPlaying(target: target)
            self.nowPlaying = np
            self.upNextTrack = np.upNext

            // Only update master volume from speaker if user is not actively adjusting the slider
            if Date().timeIntervalSince(lastUserVolumeChangeTime) > 1.2 {
                self.volume = Double(np.volume)
                self.isMuted = (np.volume == 0)
            }
            if let sel = selectedGroup {
                self.groupPlaybackStates[sel.id] = np.state
            }

            // Sync with macOS Control Center & hardware media keys
            let artURL = self.currentArtworkURL
            Task {
                var img: NSImage? = nil
                if let url = artURL {
                    img = await ArtworkCache.shared.image(for: url)
                }
                NowPlayingMediaManager.shared.updateNowPlaying(
                    title: np.displayTitle,
                    artist: np.artist,
                    album: np.album,
                    duration: np.durationSeconds,
                    elapsed: np.progressSeconds,
                    isPlaying: np.isPlaying,
                    artwork: img
                )
            }

            // Self-healing queue recovery (when queue is supported)
            if capabilities.supportsQueue, let qLen = np.queueLength, qLen > 0 && queueItems.isEmpty && !isLoadingQueue {
                Task { [weak self] in
                    await self?.refreshQueue(ip: ip)
                }
            }
        } catch {
            let desc = target.localIP ?? target.groupId ?? "active target"
            AppLogger.shared.warning("Failed to refresh now playing for \(desc): \(error)", category: "COORDINATOR")
        }
    }

    public func seekTime(seconds: Double) async {
        guard let target = selectedGroup?.target else { return }
        do {
            try await backend.seekTime(target: target, seconds: Int(seconds))
            await refreshNowPlaying()
        } catch {
            AppLogger.shared.warning("Failed to seek to \(seconds)s: \(error)", category: "COORDINATOR")
        }
    }

    public func togglePlayPause() async {
        if nowPlaying?.isPlaying == true {
            await pause()
        } else {
            await play()
        }
    }

    public func play() async {
        guard let target = selectedGroup?.target else { return }
        do {
            try await backend.play(target: target)
            try? await Task.sleep(nanoseconds: 200_000_000)
            await refreshNowPlaying()
        } catch {
            errorMessage = "Failed to play: \(error.localizedDescription)"
        }
    }

    public func pause() async {
        guard let target = selectedGroup?.target else { return }
        do {
            try await backend.pause(target: target)
            try? await Task.sleep(nanoseconds: 200_000_000)
            await refreshNowPlaying()
        } catch {
            errorMessage = "Failed to pause: \(error.localizedDescription)"
        }
    }

    public func next() async {
        guard let target = selectedGroup?.target else { return }
        do {
            try await backend.next(target: target)
            try? await Task.sleep(nanoseconds: 300_000_000)
            await refreshNowPlaying()
        } catch {
            errorMessage = "Failed to skip to next track: \(error.localizedDescription)"
        }
    }

    public func previous() async {
        guard let target = selectedGroup?.target else { return }
        do {
            try await backend.previous(target: target)
            try? await Task.sleep(nanoseconds: 300_000_000)
            await refreshNowPlaying()
        } catch {
            errorMessage = "Failed to go to previous track: \(error.localizedDescription)"
        }
    }

    public func refreshFavorites(ip: String? = nil) async {
        guard capabilities.supportsFavorites else {
            self.favorites = []
            return
        }

        let target: SonosTarget
        if let ip = ip, !ip.isEmpty {
            target = .local(ip)
        } else if let group = selectedGroup {
            target = group.target
        } else {
            return
        }

        do {
            let favs = try await backend.listFavorites(target: target)
            self.favorites = favs
        } catch {
            let desc = target.localIP ?? target.householdId ?? "active target"
            AppLogger.shared.warning("Failed to list favorites on \(desc): \(error)", category: "COORDINATOR")
        }
    }

    public func playFavorite(_ favorite: SonosFavorite) async {
        guard let target = selectedGroup?.target else { return }
        do {
            AppLogger.shared.log("Playing favorite '\(favorite.title)' (ID: \(favorite.id))", category: "COORDINATOR")
            try await backend.playFavorite(target: target, favoriteId: favorite.id)
            try? await Task.sleep(nanoseconds: 500_000_000)
            await refreshNowPlaying()
            if capabilities.supportsQueue {
                await refreshQueue()
            }
        } catch {
            errorMessage = "Failed to play favorite '\(favorite.title)': \(error.localizedDescription)"
            AppLogger.shared.error("playFavorite failed: \(error)", category: "COORDINATOR")
        }
    }

    public func playStream(url: String, title: String? = nil) async {
        guard capabilities.supportsAudioStreams else {
            errorMessage = "Audio stream URLs are not supported by the official Sonos cloud engine."
            return
        }
        guard let target = selectedGroup?.target else { return }
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else { return }
        let cleanTitle = (title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? title : nil

        do {
            AppLogger.shared.log("Starting audio stream \(trimmedURL)", category: "COORDINATOR")
            try await backend.playStream(target: target, url: trimmedURL, title: cleanTitle)

            let savedTitle = cleanTitle ?? URL(string: trimmedURL)?.host ?? "Audio Stream"
            settings.addRecentStream(SavedStream(title: savedTitle, url: trimmedURL))

            try? await Task.sleep(nanoseconds: 500_000_000)
            await refreshNowPlaying()
            if capabilities.supportsQueue {
                await refreshQueue()
            }
        } catch {
            errorMessage = "Failed to play stream: \(error.localizedDescription)"
            AppLogger.shared.error("playStream failed: \(error)", category: "COORDINATOR")
        }
    }
}
