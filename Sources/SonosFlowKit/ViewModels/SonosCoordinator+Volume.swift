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

        guard let target = selectedGroup?.target else { return }

        volumeDebounceTask?.cancel()
        volumeDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms debounce
            guard !Task.isCancelled else { return }
            do {
                try await backend.setVolume(target: target, volume: Int(clamped))
            } catch {
                let desc = target.localIP ?? target.groupId ?? "target"
                AppLogger.shared.warning("Failed to set volume on \(desc): \(error)", category: "COORDINATOR")
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

    private func memberTarget(for member: TopologyMember, in group: TopologyGroup) -> SonosTarget? {
        if let ip = member.ip, !ip.isEmpty {
            return .local(ip)
        }
        if !member.uuid.isEmpty {
            return .cloud(householdId: group.householdId ?? "", groupId: group.id, playerId: member.uuid)
        }
        return nil
    }

    public func refreshMemberVolumes(for group: TopologyGroup) async {
        for member in group.members {
            guard let target = memberTarget(for: member, in: group) else { continue }
            if let vol = try? await backend.getPlayerVolume(target: target) {
                self.memberVolumes[member.id] = Double(vol)
            }
        }
    }

    public func setMemberVolume(member: TopologyMember, in group: TopologyGroup, volume: Double) {
        guard let target = memberTarget(for: member, in: group) else { return }
        let clamped = max(0.0, min(100.0, volume))
        let key = member.id
        self.memberVolumes[key] = clamped

        memberVolumeDebounceTasks[key]?.cancel()
        memberVolumeDebounceTasks[key] = Task {
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard !Task.isCancelled else { return }
            do {
                try await backend.setPlayerVolume(target: target, volume: Int(clamped))
            } catch {
                let desc = target.localIP ?? target.playerId ?? key
                AppLogger.shared.warning("Failed to set member volume on \(desc): \(error)", category: "COORDINATOR")
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
                try await backend.setPlayerVolume(target: .local(memberIP), volume: Int(clamped))
            } catch {
                AppLogger.shared.warning("Failed to set member volume on \(memberIP): \(error)", category: "COORDINATOR")
            }
        }
    }
}
