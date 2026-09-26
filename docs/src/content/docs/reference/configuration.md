---
title: Configuration & Settings
description: Customization options, UserDefaults keys, and process parameters for SonosFlow.
---

SonosFlow settings are configured in the **Preferences (`⌘,`)** window and stored in macOS `UserDefaults` and the macOS Keychain.

## Setting Options

### 1. Sonos Control Engine
- **Key**: `sonosflow_control_engine`
- **Options**: `local` (default) or `cloud`.
- **Purpose**: Controls whether SonosFlow routes through the local edge-first engine (`homectl-sonos` over stdio pipe) or the official hosted SaaS endpoint (`mcp.ws.sonos.com/mcp` over TLS).
- **Behavior & Gating**:
  - **Local**: Enables full 188-track drag-and-drop queue management (`Q:0`), hover track deletion, local radio stream URLs (`⌘U`), and <10ms responsiveness.
  - **Cloud**: Uses official OAuth 2.1 PKCE authentication. Replaces the queue pane with a single-track "Up Next" preview card, and hides local stream players.

### 2. Local homectl MCP Server Binary Path
- **Key**: `sonosflow_mcp_binary_path`
- **Default**: Automatic discovery (`~/projects/homectl/bin/mcp-sonos`, `~/go/bin/mcp-sonos`, etc.).
- **Purpose**: Defines the local executable launched by `LocalHomectlBackend`.
- **Diagnostics**: Use the "Test" button to execute an immediate JSON-RPC handshake check.

### 3. Official Sonos Cloud Account (OAuth 2.1 PKCE)
- **Keychain Service**: `com.ghchinoy.SonosFlow.cloudToken`
- **Purpose**: Stores access and refresh tokens acquired through dynamic client registration (RFC 7591) and browser PKCE authorization.
- **Sign In / Sign Out**: Interactive button opens the browser for authorization; "Test Connection" pings `mcp.ws.sonos.com/mcp` `tools/list`.

### 4. Active Server Capabilities
- A live diagnostic card showing every feature supported by the currently connected engine:
  - Transport & Playback
  - Volume & Mute Control
  - Sonos Favorites
  - Full Playback Queue Management (Local only)
  - Direct Audio Stream Player (Local only)
  - Registered MCP Tools count

### 5. Polling Interval
- **Key**: `sonosflow_polling_interval`
- **Default**: `4.0` seconds for Local, `6.0` seconds for Cloud (Range: `2.0` to `10.0` seconds).
- **Purpose**: Sets how frequently the background worker re-checks playback status and progress on the active group.

### 6. Volume Step Delta
- **Key**: `sonosflow_volume_delta`
- **Default**: `5%` (Range: `1%` to `15%`).
- **Purpose**: Dictates the volume delta applied when pressing `⌘↑`, `⌘↓`, or the `-` and `+` step buttons.

### 7. Selected Group ID
- **Key**: `sonosflow_selected_group_id`
- **Default**: Persists the last active zone group selected by the user, automatically restored on app launch.

## Cache Management

In the **Album Artwork Disk Cache** section of Settings:
- **Storage Used**: Shows current disk footprint (e.g. `24.8 MB (142 covers)`).
- **Reveal in Finder**: Opens `~/Library/Caches/com.sonosflow.app/Artwork/`.
- **Clear Cache**: Clears both memory and disk caches.
