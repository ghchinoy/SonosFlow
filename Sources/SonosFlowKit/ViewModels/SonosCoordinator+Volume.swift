import Foundation

extension SonosCoordinator {
    // MARK: - Master & Member Volume Controls

    public func setVolume(_ newVolume: Double) {
        lastUserVolumeChangeTime = Date()
        let clamped = max(0.0, min(100.0, newVolume))
        self.volume = clamped
        if clamped > 0 {
            self.isMuted = false
            self.previousVolume = clamped
        } else {
            self.isMuted = true
        }

        guard let ip = selectedGroup?.coordinatorIP else { return }

        volumeDebounceTask?.cancel()
        volumeDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms debounce
            guard !Task.isCancelled else { return }
            do {
                try await sonosService.setVolume(ip: ip, volume: Int(clamped))
            } catch {
                AppLogger.shared.warning("Failed to set volume on \(ip): \(error)", category: "COORDINATOR")
            }
        }
    }

    public func stepVolume(delta: Int) {
        let target = volume + Double(delta)
        setVolume(target)
    }

    public func toggleMute() {
        if isMuted || volume == 0 {
            let restore = previousVolume > 0 ? previousVolume : 20.0
            setVolume(restore)
        } else {
            previousVolume = volume > 0 ? volume : 20.0
            setVolume(0)
        }
    }

    public func refreshMemberVolumes(for group: TopologyGroup) async {
        for member in group.members {
            guard let ip = member.ip, !ip.isEmpty else { continue }
            if let np = try? await sonosService.getNowPlaying(ip: ip) {
                self.memberVolumes[ip] = Double(np.volume)
            }
        }
    }

    public func setMemberVolume(memberIP: String, volume: Double) {
        let clamped = max(0.0, min(100.0, volume))
        self.memberVolumes[memberIP] = clamped

        memberVolumeDebounceTasks[memberIP]?.cancel()
        memberVolumeDebounceTasks[memberIP] = Task {
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard !Task.isCancelled else { return }
            do {
                try await sonosService.setVolume(ip: memberIP, volume: Int(clamped))
            } catch {
                AppLogger.shared.warning("Failed to set member volume on \(memberIP): \(error)", category: "COORDINATOR")
            }
        }
    }
}
