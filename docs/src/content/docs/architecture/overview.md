---
title: System Architecture
description: Overview of SonosFlow's modular Swift package architecture and concurrency model.
---

SonosFlow is designed around Swift 5.9+ modern structured concurrency, modular library separation, and clean unidirectional data flow.

## Architectural Layers

```
┌────────────────────────────────────────────────────────┐
│                      SonosFlow                         │
│   (App Target, AppDelegate, WindowGroup, MenuBarExtra)  │
└───────────────────────────┬────────────────────────────┘
                            │
┌───────────────────────────▼────────────────────────────┐
│                    SonosFlowKit                        │
│                                                        │
│  ┌───────────────────────┐  ┌───────────────────────┐  │
│  │         Views         │  │      ViewModels       │  │
│  │ (MainSplit, MiniPlayer│  │   (SonosCoordinator)  │  │
│  │  QueueList, Sidebar)  │  │      @MainActor       │  │
│  └───────────┬───────────┘  └───────────┬───────────┘  │
│              │                          │              │
│              └────────────┬─────────────┘              │
│                           │                            │
│  ┌────────────────────────▼─────────────────────────┐  │
│  │                    Services                      │  │
│  │  ┌───────────────┐ ┌───────────────┐ ┌────────┐  │  │
│  │  │  SonosService │ │ ArtworkCache  │ │ Logger │  │  │
│  │  └───────┬───────┘ └───────────────┘ └────────┘  │  │
│  │          │                                       │  │
│  │  ┌───────▼───────┐                               │  │
│  │  │   MCPClient   │                               │  │
│  │  └───────┬───────┘                               │  │
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
The single source of truth for the entire application. It manages:
- Current server connection status (`disconnected`, `connecting`, `connected`, `error`).
- Discovered zone groups, stereo pairs, and room states.
- Active Now Playing state, progress fraction, and volume.
- Queue items and total count.
- Mode A MiniPlayer window morphing state.

### 2. `SonosService`
Domain-level service wrapping low-level MCP JSON-RPC tool calls into typed Swift structs (`TopologyResult`, `QueueResult`, `NowPlayingResult`, `SonosFavorite`).

### 3. `ArtworkCache` (`actor`)
Actor-isolated caching engine managing in-memory `NSCache` and SHA-256 keyed persistent disk files in `~/Library/Caches/com.sonosflow.app/Artwork/`.

### 4. `MCPClient` (`actor`)
Low-level process manager that launches `mcp-sonos`, configures standard input/output/error pipes, serializes requests with monotonic IDs, and matches asynchronous responses via `CheckedContinuation`.
