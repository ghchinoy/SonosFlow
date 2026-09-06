import XCTest
@testable import SonosFlowKit

final class SonosFlowTests: XCTestCase {

    // MARK: - Topology Models & Group Resolution

    func testTopologyDecoding() throws {
        let json = """
        {
            "count": 2,
            "groups": [
                {
                    "id": "RINCON_MOVE:1",
                    "coordinator_uuid": "RINCON_MOVE",
                    "is_pair": false,
                    "members": [
                        {
                            "uuid": "RINCON_MOVE",
                            "room_name": "Move 2",
                            "ip": "192.168.4.120",
                            "is_coordinator": true
                        }
                    ]
                },
                {
                    "id": "RINCON_OFFICE:2",
                    "coordinator_uuid": "RINCON_OFFICE_L",
                    "is_pair": true,
                    "members": [
                        {
                            "uuid": "RINCON_OFFICE_L",
                            "room_name": "Office",
                            "ip": "192.168.4.99",
                            "is_coordinator": true
                        },
                        {
                            "uuid": "RINCON_OFFICE_R",
                            "room_name": "Office",
                            "ip": "192.168.4.98",
                            "is_coordinator": false,
                            "invisible": true
                        }
                    ]
                }
            ]
        }
        """

        let data = json.data(using: .utf8)!
        let topology = try JSONDecoder().decode(TopologyResult.self, from: data)

        XCTAssertEqual(topology.count, 2)
        XCTAssertEqual(topology.groups.count, 2)

        let moveGroup = topology.groups[0]
        XCTAssertEqual(moveGroup.displayName, "Move 2")
        XCTAssertEqual(moveGroup.coordinatorIP, "192.168.4.120")
        XCTAssertFalse(moveGroup.isPair)
        XCTAssertEqual(moveGroup.subtitle, "Standalone")

        let officeGroup = topology.groups[1]
        XCTAssertEqual(officeGroup.displayName, "Office")
        XCTAssertEqual(officeGroup.coordinatorIP, "192.168.4.99")
        XCTAssertTrue(officeGroup.isPair)
        XCTAssertEqual(officeGroup.subtitle, "Stereo Pair (2 speakers)")
    }

    // MARK: - Queue Result Decoding

    func testQueueResultDecoding() throws {
        let json = """
        {
            "items": [
                {
                    "position": 1,
                    "track_id": "Q:0/1",
                    "title": "Poison",
                    "artist": "Alice Cooper",
                    "album": "Trash",
                    "uri": "x-sonos-http:track1.mp3",
                    "album_art_uri": "/getaa?s=1&u=track1",
                    "duration": "0:04:29"
                },
                {
                    "position": 2,
                    "track_id": "Q:0/2",
                    "title": "Bed of Nails",
                    "artist": "Alice Cooper",
                    "album": "Trash",
                    "uri": "x-sonos-http:track2.mp3",
                    "album_art_uri": "https://images.example.com/art2.jpg",
                    "duration": "0:04:20"
                }
            ],
            "returned": 2,
            "total_matches": 2,
            "start_index": 0
        }
        """

        let data = json.data(using: .utf8)!
        let result = try JSONDecoder().decode(QueueResult.self, from: data)

        XCTAssertEqual(result.returned, 2)
        XCTAssertEqual(result.totalMatches, 2)
        XCTAssertEqual(result.items.count, 2)

        let track1 = result.items[0]
        XCTAssertEqual(track1.position, 1)
        XCTAssertEqual(track1.title, "Poison")
        XCTAssertEqual(track1.artist, "Alice Cooper")
        XCTAssertEqual(track1.album, "Trash")

        let resolvedURL1 = track1.resolvedAlbumArtURL(coordinatorIP: "192.168.4.120")
        XCTAssertEqual(resolvedURL1?.absoluteString, "http://192.168.4.120:1400/getaa?s=1&u=track1")

        let track2 = result.items[1]
        let resolvedURL2 = track2.resolvedAlbumArtURL(coordinatorIP: "192.168.4.120")
        XCTAssertEqual(resolvedURL2?.absoluteString, "https://images.example.com/art2.jpg")
    }

    // MARK: - Now Playing & Time Parsing

    func testNowPlayingCalculations() throws {
        let json = """
        {
            "ip": "192.168.4.120",
            "state": "PLAYING",
            "volume": 25,
            "title": "Poison",
            "artist": "Alice Cooper",
            "album": "Trash",
            "duration": "0:04:00",
            "progress": "0:01:00",
            "queue_length": 10
        }
        """

        let data = json.data(using: .utf8)!
        let np = try JSONDecoder().decode(NowPlayingResult.self, from: data)

        XCTAssertTrue(np.isPlaying)
        XCTAssertFalse(np.isPaused)
        XCTAssertFalse(np.isStopped)
        XCTAssertEqual(np.displayTitle, "Poison")
        XCTAssertEqual(np.displaySubtitle, "Alice Cooper — Trash")
        XCTAssertEqual(np.durationSeconds, 240.0)
        XCTAssertEqual(np.progressSeconds, 60.0)
        XCTAssertEqual(np.progressFraction, 0.25, accuracy: 0.001)
    }

    func testDurationParsing() {
        XCTAssertEqual(parseDurationSeconds("0:04:29"), 269.0)
        XCTAssertEqual(parseDurationSeconds("1:02:15"), 3735.0)
        XCTAssertEqual(parseDurationSeconds("02:30"), 150.0)
        XCTAssertEqual(parseDurationSeconds("45"), 45.0)
        XCTAssertEqual(parseDurationSeconds(nil), 0.0)
        XCTAssertEqual(parseDurationSeconds(""), 0.0)
    }

    // MARK: - Favorites Resolution

    func testFavoritesDecoding() throws {
        let json = """
        {
            "count": 1,
            "favorites": [
                {
                    "id": "FV:2/4",
                    "title": "Heather's holiday music",
                    "type": "object.itemobject.item.sonos-favorite",
                    "album_art_uri": "https://yt3.googleusercontent.com/art.png",
                    "description": "YouTube Music"
                }
            ]
        }
        """

        let data = json.data(using: .utf8)!
        let res = try JSONDecoder().decode(ListFavoritesResult.self, from: data)

        XCTAssertEqual(res.count, 1)
        let fav = res.favorites[0]
        XCTAssertEqual(fav.title, "Heather's holiday music")
        XCTAssertEqual(fav.description, "YouTube Music")
        XCTAssertEqual(fav.resolvedAlbumArtURL(coordinatorIP: "192.168.4.120")?.absoluteString, "https://yt3.googleusercontent.com/art.png")
    }

    // MARK: - MCP Decoding Resilience

    func testMCPDecodingFallback() throws {
        // Test decoding from structuredContent
        let structuredPayload: [String: Any] = [
            "structuredContent": [
                "count": 1,
                "groups": [
                    [
                        "id": "GRP1",
                        "coordinator_uuid": "U1",
                        "is_pair": false,
                        "members": [
                            [
                                "uuid": "U1",
                                "room_name": "Living Room",
                                "ip": "192.168.1.50",
                                "is_coordinator": true
                            ]
                        ]
                    ]
                ]
            ]
        ]

        let decoded1 = try MCPClient.decodeResult(structuredPayload, as: TopologyResult.self)
        XCTAssertEqual(decoded1.count, 1)
        XCTAssertEqual(decoded1.groups.first?.displayName, "Living Room")

        // Test decoding from content array text
        let contentPayload: [String: Any] = [
            "content": [
                ["type": "text", "text": "Found 1 Sonos zone group(s)"],
                ["type": "text", "text": "{\"count\":1,\"groups\":[{\"id\":\"GRP2\",\"coordinator_uuid\":\"U2\",\"is_pair\":false,\"members\":[{\"uuid\":\"U2\",\"room_name\":\"Bedroom\",\"ip\":\"192.168.1.51\",\"is_coordinator\":true}]}]}"]
            ]
        ]

        let decoded2 = try MCPClient.decodeResult(contentPayload, as: TopologyResult.self)
        XCTAssertEqual(decoded2.count, 1)
        XCTAssertEqual(decoded2.groups.first?.displayName, "Bedroom")
    }

    // MARK: - Disk Artwork Cache Tests

    func testArtworkCacheDiskStorage() async throws {
        let testURL = URL(string: "http://192.168.4.120:1400/getaa?s=1&u=test-track")!
        let fileURL = await ArtworkCache.shared.diskFileURL(for: testURL)

        XCTAssertTrue(fileURL.path.hasSuffix(".jpg"))
        XCTAssertTrue(fileURL.path.contains("com.sonosflow.app/Artwork"))

        let stats = await ArtworkCache.shared.calculateDiskUsage()
        XCTAssertGreaterThanOrEqual(stats.bytes, 0)
        XCTAssertGreaterThanOrEqual(stats.count, 0)
    }

    // MARK: - Queue Mutation Logic Tests

    func testQueueReorderingLogic() {
        var queue = [
            QueueItem(position: 1, trackID: "Q:0/1", title: "Track A", artist: "Artist A"),
            QueueItem(position: 2, trackID: "Q:0/2", title: "Track B", artist: "Artist B"),
            QueueItem(position: 3, trackID: "Q:0/3", title: "Track C", artist: "Artist C")
        ]

        // Move first item (Track A) to after Track C (index 3)
        queue.move(fromOffsets: IndexSet(integer: 0), toOffset: 3)

        XCTAssertEqual(queue[0].title, "Track B")
        XCTAssertEqual(queue[1].title, "Track C")
        XCTAssertEqual(queue[2].title, "Track A")
    }

    func testQueueRemovalLogic() {
        var queue = [
            QueueItem(position: 1, trackID: "Q:0/1", title: "Track A", artist: "Artist A"),
            QueueItem(position: 2, trackID: "Q:0/2", title: "Track B", artist: "Artist B"),
            QueueItem(position: 3, trackID: "Q:0/3", title: "Track C", artist: "Artist C")
        ]

        // Remove Track B
        queue.removeAll(where: { $0.trackID == "Q:0/2" })

        XCTAssertEqual(queue.count, 2)
        XCTAssertEqual(queue[0].title, "Track A")
        XCTAssertEqual(queue[1].title, "Track C")
    }

    func testMCPToolCheck() async {
        let client = MCPClient()
        let hasNonExistent = await client.hasTool("non_existent_tool")
        XCTAssertFalse(hasNonExistent)
    }

    func testQueueEditPayloads() {
        let removeArgs: [String: Any] = [
            "ip": "192.168.4.120",
            "action": "remove",
            "track": 2,
            "count": 1
        ]
        XCTAssertEqual(removeArgs["action"] as? String, "remove")
        XCTAssertEqual(removeArgs["track"] as? Int, 2)

        let reorderArgs: [String: Any] = [
            "ip": "192.168.4.120",
            "action": "reorder",
            "track": 3,
            "count": 1,
            "insert_before": 1
        ]
        XCTAssertEqual(reorderArgs["action"] as? String, "reorder")
        XCTAssertEqual(reorderArgs["insert_before"] as? Int, 1)

        let playNextArgs: [String: Any] = [
            "ip": "192.168.4.120",
            "action": "reorder",
            "track": 4,
            "count": 1,
            "as_next": true
        ]
        XCTAssertEqual(playNextArgs["as_next"] as? Bool, true)

        let clearArgs: [String: Any] = [
            "ip": "192.168.4.120",
            "action": "clear"
        ]
        XCTAssertEqual(clearArgs["action"] as? String, "clear")
    }

    func testPrioritizeSeedSpeakers() {
        let speakers = [
            SonosDevice(name: "Move 2", ip: "192.168.4.120", rinconID: "R1", modelName: "Sonos Move 2"),
            SonosDevice(name: "Office", ip: "192.168.4.99", rinconID: "R2", modelName: "Sonos Play:1"),
            SonosDevice(name: "TV Room", ip: "192.168.4.100", rinconID: "R3", modelName: "Sonos Arc"),
            SonosDevice(name: "Roam", ip: "192.168.4.150", rinconID: "R4", modelName: "Sonos Roam"),
            SonosDevice(name: "Whole House", ip: "192.168.4.101", rinconID: "R5", modelName: "Sonos Port")
        ]

        // 1. Without active coordinator
        let sorted = SonosCoordinator.prioritizeSeedSpeakers(speakers: speakers, activeCoordinatorIP: nil)
        // Stationary speakers should come before Move and Roam
        XCTAssertEqual(sorted.prefix(3), ["192.168.4.99", "192.168.4.100", "192.168.4.101"])
        XCTAssertEqual(sorted.suffix(2), ["192.168.4.120", "192.168.4.150"])

        // 2. With active coordinator specified (even if Move), it should be first
        let sortedWithActive = SonosCoordinator.prioritizeSeedSpeakers(speakers: speakers, activeCoordinatorIP: "192.168.4.100")
        XCTAssertEqual(sortedWithActive.first, "192.168.4.100")
    }
}
