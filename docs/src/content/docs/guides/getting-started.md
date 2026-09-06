---
title: Introduction & Setup
description: How to install, configure, and run SonosFlow on macOS.
---

SonosFlow is a native macOS application engineered in Swift 5.9+ and SwiftUI for macOS 14 Sonoma and later. It connects directly to the `mcp-sonos` binary from [`homectl`](https://ghchinoy.github.io/homectl/) to control and monitor your Sonos system.

:::caution[Disclaimer]
SonosFlow is an independent open-source community tool. It is **not** an official Sonos product and is **not affiliated with, sponsored by, or endorsed by Sonos, Inc.**
:::

## Prerequisites

1. **macOS 14.0 (Sonoma) or newer**
2. **Xcode Command Line Tools / Swift 5.9+**
3. **`mcp-sonos` Binary**: Built from the `homectl` repository:
   ```bash
   cd /path/to/homectl
   make build
   # Binary generated at bin/mcp-sonos
   ```

## Quick Start

Clone or open the `sonos-swift-mcp` workspace:

```bash
cd /path/to/sonos-swift-mcp

# 1. Execute unit test suite
make test

# 2. Run the headless CLI verification spike
make spike

# 3. Launch the native macOS app
make run
```

## Binary Path Configuration

By default, SonosFlow looks for `mcp-sonos` at:
- `/Users/ghchinoy/projects/homectl/bin/mcp-sonos`
- `~/projects/homectl/bin/mcp-sonos`
- `~/go/bin/mcp-sonos`
- `/usr/local/bin/mcp-sonos`
- `/opt/homebrew/bin/mcp-sonos`

You can customize this path anytime in **Settings (`⌘,`)** using the file picker or by testing the connection with the interactive **Test** button.

## First Launch Experience

When SonosFlow opens:
1. It spawns the `mcp-sonos` process and performs the JSON-RPC handshake (`initialize` and `notifications/initialized`).
2. It queries `sonos_list_speakers` and `sonos_get_topology` to construct the list of active zone groups in your sidebar.
3. It automatically selects the first actively playing group (or your previously remembered group in `UserDefaults`).
4. It loads the current track, master volume, playback queue, and pinned favorites.
