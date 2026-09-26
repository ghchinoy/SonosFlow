import Foundation
import AppKit

extension SonosCoordinator {
    // MARK: - Playback, Transport & Audio Streams

    /// Resolves the album art URL for the currently playing track/stream
    public var currentArtworkURL: URL? {
        guard let coordIP = selectedGroup?.coordinatorIP else { return nil }
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
        guard let targetIP = ip ?? selectedGroup?.coordinatorIP else { return }
        do {
            let np = try await sonosService.getNowPlaying(ip: targetIP)
            self.nowPlaying = np
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

            // Self-healing queue recovery:
            // If speaker reports tracks in the queue, but our local queueItems list is empty,
            // quietly refresh the queue in background so the UI self-heals.
            if let qLen = np.queueLength, qLen > 0 && queueItems.isEmpty && !isLoadingQueue {
                Task { [weak self] in
                    await self?.refreshQueue(ip: targetIP)
                }
            }
        } catch {
            AppLogger.shared.warning("Failed to refresh now playing for \(targetIP): \(error)", category: "COORDINATOR")
        }
    }

    public func seekTime(seconds: Double) async {
        guard let ip = selectedGroup?.coordinatorIP else { return }
        let totalSecs = max(0, Int(seconds))
        let hours = totalSecs / 3600
        let minutes = (totalSecs % 3600) / 60
        let secs = totalSecs % 60
        let target = String(format: "%02d:%02d:%02d", hours, minutes, secs)
        do {
            try await sonosService.control(ip: ip, action: "seek_time", target: target)
            await refreshNowPlaying(ip: ip)
        } catch {
            AppLogger.shared.warning("Failed to seek to \(target) on \(ip): \(error)", category: "COORDINATOR")
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
        guard let ip = selectedGroup?.coordinatorIP else { return }
        do {
            try await sonosService.play(ip: ip)
            try? await Task.sleep(nanoseconds: 200_000_000)
            await refreshNowPlaying(ip: ip)
        } catch {
            errorMessage = "Failed to play: \(error.localizedDescription)"
        }
    }

    public func pause() async {
        guard let ip = selectedGroup?.coordinatorIP else { return }
        do {
            try await sonosService.pause(ip: ip)
            try? await Task.sleep(nanoseconds: 200_000_000)
            await refreshNowPlaying(ip: ip)
        } catch {
            errorMessage = "Failed to pause: \(error.localizedDescription)"
        }
    }

    public func next() async {
        guard let ip = selectedGroup?.coordinatorIP else { return }
        do {
            try await sonosService.next(ip: ip)
            try? await Task.sleep(nanoseconds: 300_000_000)
            await refreshNowPlaying(ip: ip)
        } catch {
            errorMessage = "Failed to skip to next track: \(error.localizedDescription)"
        }
    }

    public func previous() async {
        guard let ip = selectedGroup?.coordinatorIP else { return }
        do {
            try await sonosService.previous(ip: ip)
            try? await Task.sleep(nanoseconds: 300_000_000)
            await refreshNowPlaying(ip: ip)
        } catch {
            errorMessage = "Failed to go to previous track: \(error.localizedDescription)"
        }
    }

    public func refreshFavorites(ip: String? = nil) async {
        guard let targetIP = ip ?? selectedGroup?.coordinatorIP else { return }
        do {
            let favs = try await sonosService.listFavorites(ip: targetIP)
            self.favorites = favs
        } catch {
            AppLogger.shared.warning("Failed to list favorites on \(targetIP): \(error)", category: "COORDINATOR")
        }
    }

    public func playFavorite(_ favorite: SonosFavorite) async {
        guard let ip = selectedGroup?.coordinatorIP else { return }
        do {
            AppLogger.shared.log("Playing favorite '\(favorite.title)' (ID: \(favorite.id)) on \(ip)", category: "COORDINATOR")
            try await sonosService.playFavorite(ip: ip, favoriteId: favorite.id)
            try? await Task.sleep(nanoseconds: 500_000_000)
            await refreshNowPlaying(ip: ip)
            await refreshQueue(ip: ip)
        } catch {
            errorMessage = "Failed to play favorite '\(favorite.title)': \(error.localizedDescription)"
            AppLogger.shared.error("playFavorite failed: \(error)", category: "COORDINATOR")
        }
    }

    public func playStream(url: String, title: String? = nil) async {
        guard let ip = selectedGroup?.coordinatorIP else { return }
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else { return }
        let cleanTitle = (title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? title : nil

        do {
            AppLogger.shared.log("Starting audio stream \(trimmedURL) on \(ip)", category: "COORDINATOR")
            try await sonosService.playStream(ip: ip, url: trimmedURL, title: cleanTitle)

            let savedTitle = cleanTitle ?? URL(string: trimmedURL)?.host ?? "Audio Stream"
            settings.addRecentStream(SavedStream(title: savedTitle, url: trimmedURL))

            try? await Task.sleep(nanoseconds: 500_000_000)
            await refreshNowPlaying(ip: ip)
            await refreshQueue(ip: ip)
        } catch {
            errorMessage = "Failed to play stream: \(error.localizedDescription)"
            AppLogger.shared.error("playStream failed: \(error)", category: "COORDINATOR")
        }
    }
}
