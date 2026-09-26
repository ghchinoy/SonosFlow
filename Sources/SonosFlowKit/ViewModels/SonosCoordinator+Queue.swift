import Foundation

extension SonosCoordinator {
    // MARK: - Queue Management

    public func refreshQueue(ip: String? = nil) async {
        guard capabilities.supportsQueue else {
            self.queueItems = []
            self.queueTotalMatches = 0
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

        isLoadingQueue = true
        defer { isLoadingQueue = false }

        do {
            var allItems: [QueueItem] = []
            var startIndex = 0
            var totalMatches = 0
            let batchSize = 100
            let maxTracks = 1000 // Safety cap

            repeat {
                let q = try await backend.getQueue(target: target, start: startIndex, count: batchSize)
                totalMatches = q.totalMatches
                allItems.append(contentsOf: q.items)
                startIndex += q.returned

                if q.returned == 0 || allItems.count >= totalMatches || allItems.count >= maxTracks {
                    break
                }
            } while allItems.count < totalMatches

            self.queueItems = allItems
            self.queueTotalMatches = totalMatches
            let desc = target.localIP ?? target.groupId ?? "active target"
            AppLogger.shared.log("Loaded \(allItems.count) of \(totalMatches) queue tracks on \(desc)", category: "COORDINATOR")
        } catch {
            let desc = target.localIP ?? target.groupId ?? "active target"
            AppLogger.shared.warning("Failed to refresh queue for \(desc): \(error)", category: "COORDINATOR")
        }
    }

    public func playQueueItem(_ item: QueueItem) async {
        guard capabilities.supportsQueue else { return }
        guard let target = selectedGroup?.target else { return }
        do {
            let desc = target.localIP ?? target.groupId ?? "target"
            AppLogger.shared.log("Seeking track \(item.position) ('\(item.title)') on \(desc)", category: "COORDINATOR")
            try await backend.seekTrack(target: target, track: item.position)
            if nowPlaying?.isPlaying != true {
                try? await backend.play(target: target)
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
            await refreshNowPlaying()
        } catch {
            errorMessage = "Failed to play queue track: \(error.localizedDescription)"
            AppLogger.shared.error("playQueueItem failed: \(error)", category: "COORDINATOR")
        }
    }

    public func removeQueueItem(_ item: QueueItem) async {
        guard capabilities.supportsQueueEdit else { return }
        guard let target = selectedGroup?.target else { return }
        let priorItems = self.queueItems
        let priorTotal = self.queueTotalMatches

        // Optimistic UI removal
        if let idx = self.queueItems.firstIndex(where: { $0.id == item.id }) {
            self.queueItems.remove(at: idx)
            self.queueTotalMatches = max(0, self.queueTotalMatches - 1)
        }

        do {
            let desc = target.localIP ?? target.groupId ?? "target"
            AppLogger.shared.log("Removing track \(item.position) ('\(item.title)') from queue on \(desc)", category: "COORDINATOR")
            try await backend.removeTrackFromQueue(target: target, track: item.position, count: 1)
            try? await Task.sleep(nanoseconds: 200_000_000)
            await refreshQueue()
            await refreshNowPlaying()
        } catch {
            // Rollback on failure
            self.queueItems = priorItems
            self.queueTotalMatches = priorTotal
            errorMessage = "Failed to remove track: \(error.localizedDescription)"
            AppLogger.shared.error("removeQueueItem failed: \(error)", category: "COORDINATOR")
        }
    }

    public func moveQueueItems(from source: IndexSet, to destination: Int) async {
        guard capabilities.supportsQueueEdit else { return }
        guard let target = selectedGroup?.target, let sourceIdx = source.first else { return }
        let priorItems = self.queueItems

        // Optimistic local reorder
        var updated = queueItems
        updated.move(fromOffsets: source, toOffset: destination)
        self.queueItems = updated

        // Compute 1-based Sonos UPnP indices
        let startingIndex = sourceIdx + 1
        let insertBefore = destination + 1

        do {
            let desc = target.localIP ?? target.groupId ?? "target"
            AppLogger.shared.log("Reordering queue on \(desc): track \(startingIndex) -> before \(insertBefore)", category: "COORDINATOR")
            try await backend.reorderQueue(
                target: target,
                startingIndex: startingIndex,
                numberOfTracks: source.count,
                insertBefore: insertBefore
            )
            try? await Task.sleep(nanoseconds: 300_000_000)
            await refreshQueue()
        } catch {
            // Rollback on failure
            self.queueItems = priorItems
            errorMessage = "Failed to reorder queue: \(error.localizedDescription)"
            AppLogger.shared.error("moveQueueItems failed: \(error)", category: "COORDINATOR")
        }
    }

    public func playNextInQueue(_ item: QueueItem) async {
        guard capabilities.supportsQueueEdit else { return }
        guard let target = selectedGroup?.target else { return }
        do {
            let desc = target.localIP ?? target.groupId ?? "target"
            AppLogger.shared.log("Moving track \(item.position) ('\(item.title)') to play next on \(desc)", category: "COORDINATOR")
            try await backend.reorderToPlayNext(target: target, track: item.position, count: 1)
            try? await Task.sleep(nanoseconds: 300_000_000)
            await refreshQueue()
        } catch {
            errorMessage = "Failed to move track to play next: \(error.localizedDescription)"
            AppLogger.shared.error("playNextInQueue failed: \(error)", category: "COORDINATOR")
        }
    }

    public func clearQueue() async {
        guard capabilities.supportsQueueEdit else { return }
        guard let target = selectedGroup?.target else { return }
        let priorItems = self.queueItems
        let priorTotal = self.queueTotalMatches

        // Optimistic wipe
        self.queueItems = []
        self.queueTotalMatches = 0

        do {
            let desc = target.localIP ?? target.groupId ?? "target"
            AppLogger.shared.log("Clearing all tracks from queue on \(desc)", category: "COORDINATOR")
            try await backend.clearQueue(target: target)
            try? await Task.sleep(nanoseconds: 200_000_000)
            await refreshQueue()
            await refreshNowPlaying()
        } catch {
            // Rollback on failure
            self.queueItems = priorItems
            self.queueTotalMatches = priorTotal
            errorMessage = "Failed to clear queue: \(error.localizedDescription)"
            AppLogger.shared.error("clearQueue failed: \(error)", category: "COORDINATOR")
        }
    }
}
