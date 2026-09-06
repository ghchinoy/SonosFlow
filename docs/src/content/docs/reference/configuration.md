---
title: Configuration & Settings
description: Customization options, UserDefaults keys, and process parameters for SonosFlow.
---

SonosFlow settings are configured in the **Preferences (`⌘,`)** window and stored in macOS `UserDefaults`.

## Setting Options

### 1. Sonos MCP Server Binary Path
- **Key**: `sonosflow_mcp_binary_path`
- **Default**: Automatic discovery (`/Users/ghchinoy/projects/homectl/bin/mcp-sonos`, `~/go/bin/mcp-sonos`, etc.).
- **Purpose**: Defines the executable launched by `MCPClient`.
- **Diagnostics**: Use the "Test" button to execute an immediate JSON-RPC handshake check.

### 2. Polling Interval
- **Key**: `sonosflow_polling_interval`
- **Default**: `4.0` seconds (Range: `2.0` to `10.0` seconds).
- **Purpose**: Sets how frequently the background worker re-checks playback status and progress on the active coordinator.

### 3. Volume Step Delta
- **Key**: `sonosflow_volume_delta`
- **Default**: `5%` (Range: `1%` to `15%`).
- **Purpose**: Dictates the volume delta applied when pressing `⌘↑`, `⌘↓`, or the `-` and `+` step buttons.

### 4. Selected Group ID
- **Key**: `sonosflow_selected_group_id`
- **Default**: Persists the last active zone group selected by the user, automatically restored on app launch.

## Cache Management

In the **Album Artwork Disk Cache** section of Settings:
- **Storage Used**: Shows current disk footprint (e.g. `24.8 MB (142 covers)`).
- **Reveal in Finder**: Opens `~/Library/Caches/com.sonosflow.app/Artwork/`.
- **Clear Cache**: Clears both memory and disk caches.
