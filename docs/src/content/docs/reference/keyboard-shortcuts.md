---
title: Keyboard Shortcuts
description: Complete reference for all global and contextual keyboard shortcuts in SonosFlow.
---

SonosFlow is designed around keyboard-first ergonomics adhering to Apple's Human Interface Guidelines.

## Global Playback Shortcuts

| Shortcut | Action | Description |
|---|---|---|
| **`Space`** | Play / Pause | Toggles playback on the active speaker group (ignored when typing in text fields). |
| **`F8`** | Play / Pause | Hardware media key on Mac keyboard (Apple Remote Command). |
| **`⌘ →`** | Next Track | Skips to the next track in the queue. |
| **`F9`** | Next Track | Hardware media key on Mac keyboard. |
| **`⌘ ←`** | Previous Track | Skips back to the previous track or restarts the current track. |
| **`F7`** | Previous Track | Hardware media key on Mac keyboard. |
| **`⌘ ↑`** | Volume Up | Increases master volume on the active coordinator by the configured step (default +5%). |
| **`⌘ ↓`** | Volume Down | Decreases master volume on the active coordinator by the configured step (default -5%). |
| **`⌘ ⌥ ↓`** | Mute / Unmute | Toggles volume mute on the active speaker group (restores previous level on unmute). |
| **`⌘ U`** | Audio Stream | Opens the Audio Stream Player dialog with presets and custom URL input. |

## Queue Interaction Shortcuts

| Shortcut | Action | Description |
|---|---|---|
| **`↑` / `↓`** | Navigate Queue | Move highlighted row selection up and down in the playback queue. |
| **`Return`** | Play Selected | Start playback of the currently highlighted queue track. |
| **`Delete` / `⌫`** | Remove Selected | Remove the highlighted song from the playback queue. |
| **`Esc`** | Clear Filter | When searching the queue, immediately clears the search query and restores all tracks. |
| **`⌘ ⌫`** | Clear Queue | Prompts confirmation dialog to wipe all tracks from the queue on active room. |

## Window & Navigation Shortcuts

| Shortcut | Action | Description |
|---|---|---|
| **`⌘ M`** | Toggle MiniPlayer | Morphs the window into the floating Mode A MiniPlayer (or restores full window). |
| **`Esc`** | Exit MiniPlayer | Restores the full window when in MiniPlayer mode (without an active filter). |
| **`⌘ R`** | Refresh | Re-queries the Sonos network topology and current queue. |
| **`⌘ ⇧ R`** | Reload MCP Server | Restarts the `mcp-sonos` process and reloads all registered tools. |
| **`⌘ F`** | Favorites | Opens the Pinned Favorites sheet. |
| **`⌘ 1...9`** | Switch Room | Switches active speaker group to room #1 through #9. |
| **`⌘ ,`** | Settings | Opens the SonosFlow Preferences window. |
| **`⌘ Q`** | Quit | Shuts down the application and cleanly terminates the `mcp-sonos` child process. |
