import Foundation

extension SonosCoordinator {
    // MARK: - Queue Management

    public func refreshQueue(ip: String? = nil) async {
        guard let targetIP = ip ?? selectedGroup?.coordinatorIP else { return }
        isLoadingQueue = true
        defer { isLoadingQueue = false }

        do {
            var allItems: [QueueItem] = []
            var startIndex = 0
            var totalMatches = 0
            let batchSize = 100
            let maxTracks = 1000 // Safety cap

            repeat {
                let q = try await sonosService.getQueue(ip: targetIP, start: startIndex, count: batchSize)
                totalMatches = q.totalMatches
                allItems.append(contentsOf: q.items)
                startIndex += q.returned

                if q.returned == 0 || allItems.count >= totalMatches || allItems.count >= maxTracks {
                    break
                }
            } while allItems.count < totalMatches

            self.queueItems = allItems
            self.queueTotalMatches = totalMatches
            AppLogger.shared.log("Loaded \(allItems.count) of \(totalMatches) queue tracks on \(targetIP)", category: "COORDINATOR")
        } catch {
            AppLogger.shared.warning("Failed to refresh queue for \(targetIP): \(error)", category: "COORDINATOR")
        }
    }

    public func playQueueItem(_ item: QueueItem) async {
        guard let ip = selectedGroup?.coordinatorIP else { return }
        do {
            AppLogger.shared.log("Seeking track \(item.position) ('\(item.title)') on \(ip)", category: "COORDINATOR")
            try await sonosService.seekTrack(ip: ip, track: item.position)
            // Immediately start playing if paused
            if nowPlaying?.isPlaying != true {
                try? await sonosService.play(ip: ip)
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
            await refreshNowPlaying(ip: ip)
        } catch {
            errorMessage = "Failed to play queue track: \(error.localizedDescription)"
            AppLogger.shared.error("playQueueItem failed: \(error)", category: "COORDINATOR")
        }
    }

    public func removeQueueItem(_ item: QueueItem) async {
        guard let ip = selectedGroup?.coordinatorIP else { return }
        let priorItems = self.queueItems
        let priorTotal = self.queueTotalMatches

        // Optimistic UI removal
        if let idx = self.queueItems.firstIndex(where: { $0.id == item.id }) {
            self.queueItems.remove(at: idx)
            self.queueTotalMatches = max(0, self.queueTotalMatches - 1)
        }

        do {
            AppLogger.shared.log("Removing track \(item.position) ('\(item.title)') from queue on \(ip)", category: "COORDINATOR")
            try await sonosService.removeTrackFromQueue(ip: ip, track: item.position)
            try? await Task.sleep(nanoseconds: 200_000_000)
            await refreshQueue(ip: ip)
            await refreshNowPlaying(ip: ip)
        } catch {
            // Rollback on failure
            self.queueItems = priorItems
            self.queueTotalMatches = priorTotal
            errorMessage = "Failed to remove track: \(error.localizedDescription)"
            AppLogger.shared.error("removeQueueItem failed: \(error)", category: "COORDINATOR")
        }
    }

    public func moveQueueItems(from source: IndexSet, to destination: Int) async {
        guard let ip = selectedGroup?.coordinatorIP, let sourceIdx = source.first else { return }
        let priorItems = self.queueItems

        // Optimistic local reorder
        var updated = queueItems
        updated.move(fromOffsets: source, toOffset: destination)
        self.queueItems = updated

        // Compute 1-based Sonos UPnP indices
        let startingIndex = sourceIdx + 1
        let insertBefore = destination + 1

        do {
            AppLogger.shared.log("Reordering queue on \(ip): track \(startingIndex) -> before \(insertBefore)", category: "COORDINATOR")
            try await sonosService.reorderQueue(
                ip: ip,
                startingIndex: startingIndex,
                numberOfTracks: source.count,
                insertBefore: insertBefore
            )
            try? await Task.sleep(nanoseconds: 300_000_000)
            await refreshQueue(ip: ip)
        } catch {
            // Rollback on failure
            self.queueItems = priorItems
            errorMessage = "Failed to reorder queue: \(error.localizedDescription)"
            AppLogger.shared.error("moveQueueItems failed: \(error)", category: "COORDINATOR")
        }
    }

    public func playNextInQueue(_ item: QueueItem) async {
        guard let ip = selectedGroup?.coordinatorIP else { return }
        do {
            AppLogger.shared.log("Moving track \(item.position) ('\(item.title)') to play next on \(ip)", category: "COORDINATOR")
            try await sonosService.reorderToPlayNext(ip: ip, track: item.position)
            try? await Task.sleep(nanoseconds: 300_000_000)
            await refreshQueue(ip: ip)
        } catch {
            errorMessage = "Failed to move track to play next: \(error.localizedDescription)"
            AppLogger.shared.error("playNextInQueue failed: \(error)", category: "COORDINATOR")
        }
    }

    public func clearQueue() async {
        guard let ip = selectedGroup?.coordinatorIP else { return }
        let priorItems = self.queueItems
        let priorTotal = self.queueTotalMatches

        // Optimistic wipe
        self.queueItems = []
        self.queueTotalMatches = 0

        do {
            AppLogger.shared.log("Clearing all tracks from queue on \(ip)", category: "COORDINATOR")
            try await sonosService.clearQueue(ip: ip)
            try? await Task.sleep(nanoseconds: 200_000_000)
            await refreshQueue(ip: ip)
            await refreshNowPlaying(ip: ip)
        } catch {
            // Rollback on failure
            self.queueItems = priorItems
            self.queueTotalMatches = priorTotal
            errorMessage = "Failed to clear queue: \(error.localizedDescription)"
            AppLogger.shared.error("clearQueue failed: \(error)", category: "COORDINATOR")
        }
    }
}
