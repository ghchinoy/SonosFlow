---
title: Introduction & Setup
description: How to install, configure, and run SonosFlow on macOS.
---

SonosFlow is a native macOS application engineered in Swift 5.9+ and SwiftUI for macOS 14 Sonoma and later. It supports two control engines: the local edge-first [`homectl`](https://ghchinoy.github.io/homectl/) MCP server over stdio pipes, and the official hosted **Sonos 27mcp server** over TLS.

:::caution[Disclaimer]
SonosFlow is an independent open-source community tool. It is **not** an official Sonos product and is **not affiliated with, sponsored by, or endorsed by Sonos, Inc.**
:::

## Prerequisites

1. **macOS 14.0 (Sonoma) or newer**
2. **Xcode Command Line Tools / Swift 5.9+**
3. **Backend Choice**:
   - **Local Engine (`homectl-sonos`) [Recommended Default]**: Built from the `homectl` repository (`make build` at `bin/mcp-sonos`).
   - **Sonos Cloud Engine (The Sonos 27mcp server)**: No local binary required; simply sign in with your Sonos account in **Settings (`⌘,`)**.

## Quick Start

Clone or open the repository:

```bash
git clone https://github.com/ghchinoy/SonosFlow.git
cd SonosFlow

# 1. Execute unit test suite (29 tests)
make test

# 2. Launch the native macOS app in debug mode
make run
```

## Installing Locally (`make install`)

To install the optimized release `.app` bundle into your personal applications folder:

```bash
# Build release bundle and install to ~/Applications/SonosFlow.app
make install

# Launch installed app
open ~/Applications/SonosFlow.app
```

To install system-wide for all users:
```bash
make install INSTALL_DIR=/Applications
```

To uninstall:
```bash
make uninstall
```
*(Your settings, Keychain tokens, and album artwork cache are safely preserved).*

## Binary Path Configuration

By default, SonosFlow looks for `mcp-sonos` at:
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

![SonosFlow Main Window](../../../assets/screenshots/main-window.webp)
*Figure 1: SonosFlow main window featuring room selection sidebar, hero now-playing card with album artwork, and full playback queue.*
