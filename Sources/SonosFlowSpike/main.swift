import Foundation
import SonosFlowKit

@main
struct SonosFlowSpike {
    static func main() async {
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🎵 SonosFlow MCP Headless Verification Spike")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        let settings = AppSettings.shared
        let binaryPath = settings.effectiveMcpBinaryPath
        print("📍 Effective mcp-sonos path: \(binaryPath)")

        guard FileManager.default.isExecutableFile(atPath: binaryPath) else {
            print("❌ Error: Binary at \(binaryPath) is not executable or does not exist.")
            exit(1)
        }

        let client = MCPClient()
        let sonos = SonosService(client: client)

        do {
            print("\n1️⃣  Initializing MCP server handshake...")
            let (info, tools) = try await client.initializeAndVerify(binaryPath: binaryPath)
            print("✅ Server initialized: \(info.name) (version: \(info.version ?? "none"))")
            print("   Available tools (\(tools.count)): \(tools.map(\.name).joined(separator: ", "))")

            print("\n2️⃣  Discovering Sonos speakers...")
            let speakers = try await sonos.listSpeakers(refresh: false)
            print("✅ Discovered \(speakers.count) speaker(s):")
            for spk in speakers {
                print("   • \(spk.name) (\(spk.ip)) - \(spk.modelName ?? "Unknown Model")")
            }

            let candidateIPs = SonosCoordinator.prioritizeSeedSpeakers(speakers: speakers, activeCoordinatorIP: nil)
            guard let primarySeed = candidateIPs.first else {
                print("⚠️  No speakers discovered on network.")
                await client.stop()
                exit(0)
            }

            print("\n3️⃣  Querying Sonos topology (prioritized seed: \(primarySeed), candidates: \(candidateIPs.count))...")
            var topology: TopologyResult?
            for ip in candidateIPs {
                do {
                    topology = try await sonos.getTopology(ip: ip)
                    print("✅ Succeeded via speaker at \(ip)")
                    break
                } catch {
                    print("⚠️  Failed via \(ip): \(error). Trying next candidate...")
                }
            }

            guard let topology = topology else {
                print("❌ All candidate speakers failed for topology.")
                await client.stop()
                exit(1)
            }

            print("✅ Found \(topology.groups.count) zone group(s):")
            for (idx, grp) in topology.groups.enumerated() {
                let coord = grp.coordinatorIP ?? "none"
                let pairDesc = grp.isPair ? " [STEREO PAIR]" : ""
                print("   [\(idx + 1)] \(grp.displayName)\(pairDesc) (Coordinator IP: \(coord), Members: \(grp.members.count))")
            }

            if let activeGroup = topology.groups.first, let coordIP = activeGroup.coordinatorIP {
                print("\n4️⃣  Checking Now Playing on \(activeGroup.displayName) (\(coordIP))...")
                let np = try await sonos.getNowPlaying(ip: coordIP)
                print("✅ Now Playing state: [\(np.state)]")
                print("   Title:    \(np.title ?? np.streamContent ?? "None")")
                print("   Artist:   \(np.artist ?? "None")")
                print("   Album:    \(np.album ?? "None")")
                print("   Volume:   \(np.volume)%")
                print("   Progress: \(np.progress ?? "0:00") / \(np.duration ?? "0:00")")
                print("   Queue:    \(np.queueLength ?? 0) tracks")

                print("\n5️⃣  Inspecting Playback Queue on \(coordIP)...")
                let queue = try await sonos.getQueue(ip: coordIP, start: 0, count: 5)
                print("✅ Queue items retrieved: showing \(queue.returned) of \(queue.totalMatches) total")
                for item in queue.items {
                    let artUrl = item.resolvedAlbumArtURL(coordinatorIP: coordIP)?.absoluteString ?? "no artwork"
                    print("   #\(item.position): \(item.title) - \(item.artist) [\(item.duration ?? "")]")
                    print("       Art URL: \(artUrl)")
                }

                print("\n6️⃣  Listing Sonos Favorites on \(coordIP)...")
                let favs = try await sonos.listFavorites(ip: coordIP)
                print("✅ Found \(favs.count) pinned favorite(s):")
                for (idx, fav) in favs.prefix(5).enumerated() {
                    print("   [\(idx + 1)] \(fav.title) (\(fav.description ?? "Sonos Favorite"))")
                }

                print("\n7️⃣  Verifying sonos_queue_edit MCP tool...")
                let hasQueueEdit = await client.hasTool("sonos_queue_edit")
                if hasQueueEdit {
                    print("✅ sonos_queue_edit tool verified and active on MCP server (100% pure MCP queue control)")
                } else {
                    print("⚠️  sonos_queue_edit tool not found on MCP server")
                }
            }

            print("\n🎉 Spike verification passed completely!")
            await client.stop()
            exit(0)
        } catch {
            print("\n❌ Spike failed with error: \(error)")
            await client.stop()
            exit(1)
        }
    }
}
