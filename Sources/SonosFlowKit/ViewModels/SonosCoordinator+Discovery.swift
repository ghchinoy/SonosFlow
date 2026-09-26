import Foundation

extension SonosCoordinator {
    /// Orders discovered speakers prioritizing active coordinator first, stationary/mains speakers next, and battery portables (Move, Roam) last.
    public nonisolated static func prioritizeSeedSpeakers(speakers: [SonosDevice], activeCoordinatorIP: String?) -> [String] {
        var orderedIPs: [String] = []

        // 1. If we have an active coordinator IP, try it first
        if let active = activeCoordinatorIP, !active.isEmpty {
            orderedIPs.append(active)
        }

        // 2. Stationary speakers (Arc, Play:1, Play:3, Port, Beam, One, Five, etc.)
        let stationary = speakers.filter { spk in
            let model = (spk.modelName ?? "").lowercased()
            let isPortable = model.contains("move") || model.contains("roam")
            return !isPortable && !orderedIPs.contains(spk.ip)
        }
        for spk in stationary {
            orderedIPs.append(spk.ip)
        }

        // 3. Portable/battery speakers (Move, Roam) as last-resort fallback
        let portables = speakers.filter { spk in
            let model = (spk.modelName ?? "").lowercased()
            let isPortable = model.contains("move") || model.contains("roam")
            return isPortable && !orderedIPs.contains(spk.ip)
        }
        for spk in portables {
            orderedIPs.append(spk.ip)
        }

        return orderedIPs.filter { !$0.isEmpty }
    }

    public func refreshAll(forceNetworkScan: Bool = false) async {
        guard serverStatus.isConnected else { return }

        // Check if local binary on disk was updated/recompiled
        if let local = backend as? LocalHomectlBackend, await local.service.client.isBinaryNewerOnDisk() {
            AppLogger.shared.log("Detected updated mcp-sonos binary on disk. Hot-reloading server...", category: "COORDINATOR")
            await reloadServer()
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        // MARK: - Cloud Discovery Route
        if backend.engine == .cloud {
            do {
                let topology = try await backend.getTopology(target: nil)
                self.groups = topology.groups
                AppLogger.shared.log("Discovered \(topology.groups.count) Sonos cloud groups", category: "COORDINATOR")

                for group in topology.groups {
                    if let np = try? await backend.getNowPlaying(target: group.target) {
                        self.groupPlaybackStates[group.id] = np.state
                    }
                }

                if let savedId = settings.selectedGroupId, let matched = topology.groups.first(where: { $0.id == savedId }) {
                    self.selectedGroup = matched
                } else if selectedGroup == nil || !topology.groups.contains(where: { $0.id == selectedGroup?.id }) {
                    if let playingGroup = topology.groups.first(where: { groupPlaybackStates[$0.id]?.uppercased() == "PLAYING" }) {
                        self.selectedGroup = playingGroup
                    } else {
                        self.selectedGroup = topology.groups.first
                    }
                    if let sel = self.selectedGroup {
                        settings.selectedGroupId = sel.id
                    }
                }

                if let active = self.selectedGroup {
                    await refreshActiveGroupData(group: active)
                }
                errorMessage = nil
            } catch {
                if groups.isEmpty {
                    errorMessage = "Failed to discover Sonos cloud groups: \(error.localizedDescription)"
                }
                AppLogger.shared.error("Cloud discovery failed: \(error)", category: "COORDINATOR")
            }
            return
        }

        // MARK: - Local UPnP Discovery Route
        do {
            let speakers = try await sonosService.listSpeakers(refresh: forceNetworkScan)
            guard !speakers.isEmpty else {
                if groups.isEmpty {
                    errorMessage = "No Sonos speakers discovered on the local network."
                }
                return
            }

            let candidateIPs = Self.prioritizeSeedSpeakers(
                speakers: speakers,
                activeCoordinatorIP: selectedGroup?.coordinatorIP
            )

            var topology: TopologyResult? = nil
            var lastError: Error? = nil

            for ip in candidateIPs {
                do {
                    topology = try await sonosService.getTopology(ip: ip)
                    break
                } catch {
                    lastError = error
                    AppLogger.shared.warning("Topology query failed on \(ip), failing over to next speaker: \(error)", category: "COORDINATOR")
                }
            }

            guard let topology = topology else {
                if let err = lastError {
                    if groups.isEmpty {
                        errorMessage = "Failed to connect to Sonos speakers: \(err.localizedDescription)"
                    }
                    AppLogger.shared.error("All \(candidateIPs.count) candidate speakers failed for topology: \(err)", category: "COORDINATOR")
                }
                return
            }

            self.groups = topology.groups
            AppLogger.shared.log("Discovered \(topology.groups.count) Sonos groups", category: "COORDINATOR")

            for group in topology.groups {
                if let coordIP = group.coordinatorIP {
                    if let np = try? await sonosService.getNowPlaying(ip: coordIP) {
                        self.groupPlaybackStates[group.id] = np.state
                    }
                }
            }

            if let savedId = settings.selectedGroupId, let matched = topology.groups.first(where: { $0.id == savedId }) {
                self.selectedGroup = matched
            } else if selectedGroup == nil || !topology.groups.contains(where: { $0.id == selectedGroup?.id }) {
                if let playingGroup = topology.groups.first(where: { groupPlaybackStates[$0.id]?.uppercased() == "PLAYING" }) {
                    self.selectedGroup = playingGroup
                } else {
                    self.selectedGroup = topology.groups.first
                }
                if let sel = self.selectedGroup {
                    settings.selectedGroupId = sel.id
                }
            }

            if let active = self.selectedGroup {
                await refreshActiveGroupData(group: active)
            }
            errorMessage = nil
        } catch {
            if groups.isEmpty {
                errorMessage = "Failed to refresh Sonos topology: \(error.localizedDescription)"
            }
            AppLogger.shared.error("refreshAll failed: \(error)", category: "COORDINATOR")
        }
    }

    public func selectGroup(_ group: TopologyGroup) async {
        self.selectedGroup = group
        self.settings.selectedGroupId = group.id
        await refreshActiveGroupData(group: group)
    }

    public func refreshActiveGroupData(group: TopologyGroup) async {
        await refreshNowPlaying()
        if capabilities.supportsQueue {
            await refreshQueue()
        } else {
            self.queueItems = []
            self.queueTotalMatches = 0
        }
        if capabilities.supportsFavorites {
            await refreshFavorites()
        }
        await refreshMemberVolumes(for: group)
    }
}
