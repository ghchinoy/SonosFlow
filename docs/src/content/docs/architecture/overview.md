---
title: System Architecture
description: Overview of SonosFlow's modular Swift package architecture and concurrency model.
---

---
title: System Architecture
description: Overview of SonosFlow's dual-engine Swift package architecture, concurrency model, and protocol abstraction.
---

import { Image } from 'astro:assets';
import archDiagram from '../../../assets/diagrams/architecture.webp';

SonosFlow is designed around Swift 5.9+ modern structured concurrency, modular library separation, and clean unidirectional data flow across two interchangeable Model Context Protocol (MCP) engines.

## Architectural Layers

<div align="center">
  <Image src={archDiagram} alt="SonosFlow Dual-Engine System Architecture Diagram" width={780} />
</div>

## Core Architecture & Domain Modules

### 1. `SonosCoordinator` (`@MainActor`)
The single source of truth for the entire application, partitioned into 5 focused domain extensions:
- **`SonosCoordinator.swift`**: Core `@MainActor` state, engine switching, settings bindings, and process lifecycle.
- **`SonosCoordinator+Discovery.swift`**: Seed speaker prioritization (stationary mains -> battery portables), failover logic, and zone topology management across Local and Cloud.
- **`SonosCoordinator+Queue.swift`**: Multi-page queue pagination (188+ tracks), track seeking, optimistic reordering, removal, and queue clearing.
- **`SonosCoordinator+Volume.swift`**: Master volume debouncing, mute toggling with level restoration, and per-speaker member balancing.
- **`SonosCoordinator+Playback.swift`**: Transport controls, now-playing synchronization, stream playback, shuffle/repeat toggling, and favorites.

### 2. `ServerCapabilities`
Dynamic capability negotiation registry built upon connecting to an MCP server. Instead of hardcoding feature availability against engine names, `ServerCapabilities` dynamically inspects the active server's `tools/list` response, property definitions, and input schemas:
- **`supportsQueue` / `supportsQueueEdit`**: Direct 188-track drag-and-drop queue management and deletion (`Q:0`). Enabled on Local; replaced by "Up Next" preview on Cloud.
- **`supportsAudioStreams`**: Direct UPnP live audio stream URLs (`⌘U`). Enabled on Local; cleanly hidden on Cloud.
- **`supportsShuffleRepeat` / `supportsCrossfade`**: Discovered dynamically by checking whether `sonos_queue_edit` supports `shuffle`/`repeat`/`crossfade` actions, or via `get_shuffle_repeat_crossfade` on Cloud.
- **`supportsVolumeControl` & `supportsFavorites`**: Active across both engines.

### 3. `SonosBackend` (`Protocol`)
A unified interface decoupling SwiftUI views from communication transports. Dispatches commands through a neutral `SonosTarget`:
- `.local(ip)`: Routes to the authoritative Group Coordinator IP on the local subnet.
- `.cloud(householdId, groupId, playerId)`: Routes to the cloud broker via household and group identifiers.

### 4. `LocalHomectlBackend`
Edge-first engine that spawns the local [`homectl`](https://ghchinoy.github.io/homectl/) `mcp-sonos` binary over standard input/output pipes conforming to MCP `2024-11-05`:
- **Sub-10ms Dispatch**: Instant local execution with zero cloud transit.
- **Zero Configuration**: Automatic local subnet discovery without logins, accounts, or internet dependencies.
- **`MCPClient`**: Uses an `AsyncStream<Data>` pipeline on stdout to guarantee strict FIFO sequential processing of incoming chunks, preventing buffer fragmentation on large payloads. Monotonically sequences requests and matches responses via `CheckedContinuation`.

### 5. `SonosCloudBackend`
Cloud-mediated engine communicating with the official [Sonos 27mcp server](https://www.sonos.com/en-us/blog/meet-sonos-27) hosted at `https://mcp.ws.sonos.com/mcp`:
- **OAuth 2.1 PKCE**: Implements RFC 7591 dynamic client registration with token persistence in the macOS Keychain (`com.ghchinoy.SonosFlow.cloudToken`).
- **Remote / VLAN Access**: Allows controlling household audio across guest subnets, VPNs, or away from home.
- **Universal Payload Unwrapping**: Unwraps MCP text content objects (`content: [{"type": "text", "text": "..."}]`) and maps cloud data structures.

### 6. Platform Services
- **`ArtworkCache` (`actor`)**: Actor-isolated caching engine managing in-memory `NSCache` and SHA-256 keyed persistent disk files in `~/Library/Caches/com.sonosflow.app/Artwork/`. Binds cover art directly to window title-bar proxy icons for drag-and-drop export.
- **`NowPlayingMediaManager` (`@MainActor`)**: Bridges Sonos playback to Apple's `MediaPlayer` framework, routing hardware media keys (F7, F8, F9, AirPods) and publishing metadata to the macOS Control Center Now Playing widget.
