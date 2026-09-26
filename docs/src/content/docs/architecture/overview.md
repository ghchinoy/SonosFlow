---
title: System Architecture
description: Overview of SonosFlow's modular Swift package architecture and concurrency model.
---

SonosFlow is designed around Swift 5.9+ modern structured concurrency, modular library separation, and clean unidirectional data flow.

## Architectural Layers

```
┌────────────────────────────────────────────────────────┐
│                      SonosFlow                         │
│  (App Target: WindowGroup, MenuBarExtra, Dock Menu)    │
└───────────────────────────┬────────────────────────────┘
                            │
┌───────────────────────────▼────────────────────────────┐
│                    SonosFlowKit                        │
│                                                        │
│  ┌─────────────────────────┐ ┌──────────────────────┐  │
│  │      SwiftUI Views      │ │   SonosCoordinator   │  │
│  │ (MainSplit, MiniPlayer, │ │     (@MainActor)     │  │
│  │  QueueList, StreamSheet,│ │  (Split into 5 domain│  │
│  │  GroupVolume, Sidebar)  │ │     extensions)      │  │
│  └───────────┬─────────────┘ └──────────┬───────────┘  │
│              │                          │              │
│              └────────────┬─────────────┘              │
│                           │                            │
│  ┌────────────────────────▼─────────────────────────┐  │
│  │               Services & Caching                 │  │
│  │  ┌──────────────┐ ┌──────────────┐ ┌──────────┐  │  │
│  │  │ SonosService │ │ ArtworkCache │ │ MediaMgr │  │  │
│  │  └───────┬──────┘ └──────────────┘ └──────────┘  │  │
│  │          │                                       │  │
│  │  ┌───────▼──────┐                                │  │
│  │  │  MCPClient   │ (FIFO AsyncStream Pipe Reader) │  │
│  │  └───────┬──────┘                                │  │
│  └──────────┼───────────────────────────────────────┘  │
└─────────────┼──────────────────────────────────────────┘
              │ (stdio JSON-RPC 2.0)
┌─────────────▼──────────────────────────────────────────┐
│                   mcp-sonos (Go)                       │
│             homectl Sonos MCP Server                   │
└────────────────────────────────────────────────────────┘
```

## Core Modules

### 1. `SonosCoordinator` (`@MainActor`)
The single source of truth for the entire application, partitioned into 5 focused domain extensions:
- **`SonosCoordinator.swift`**: Core `@MainActor` state, initializer, media manager configuration, and process lifecycle.
- **`SonosCoordinator+Discovery.swift`**: Stationary-first seed prioritization, candidate failover (Move 2 -> Play:1), and group topology refresh.
- **`SonosCoordinator+Queue.swift`**: Multi-page queue pagination (188+ tracks), track seeking, optimistic reordering, removal, and queue clearing.
- **`SonosCoordinator+Volume.swift`**: Master volume debouncing, mute toggling, and per-speaker member balancing.
- **`SonosCoordinator+Playback.swift`**: Transport controls, now-playing synchronization, streams, and favorites.

### 2. `SonosService`
Domain-level service wrapping low-level MCP JSON-RPC tool calls to the [`homectl`](https://ghchinoy.github.io/homectl/) Sonos server into typed Swift structs (`TopologyResult`, `QueueResult`, `NowPlayingResult`, `SonosFavorite`).

### 3. `ArtworkCache` (`actor`)
Actor-isolated caching engine managing in-memory `NSCache` and SHA-256 keyed persistent disk files in `~/Library/Caches/com.sonosflow.app/Artwork/`.

### 4. `NowPlayingMediaManager` (`@MainActor`)
Bridges Sonos playback to macOS `MPRemoteCommandCenter` (hardware keys F7, F8, F9, AirPods) and `MPNowPlayingInfoCenter` (Control Center Now Playing widget).

### 5. `MCPClient` (`actor`)
Low-level process manager that launches `mcp-sonos`. Uses an `AsyncStream<Data>` pipeline on stdout to guarantee strict FIFO sequential processing of incoming chunks, preventing buffer fragmentation on large payloads. Monotonically sequences requests and matches responses via `CheckedContinuation`.
