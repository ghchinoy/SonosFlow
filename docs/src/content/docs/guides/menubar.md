---
title: Menu Bar Extra Companion
description: Controlling whole-home Sonos audio directly from the macOS status bar.
---

SonosFlow registers a native macOS `MenuBarExtra` companion that remains available in your menu bar even when the main window is hidden or minimized.

## Status Icon

- **Playing**: An active speaker wave icon (`speaker.wave.3.fill`) signals that audio is currently playing in your selected group.
- **Idle / Paused**: A neutral speaker icon (`hifispeaker`) indicates that playback is stopped or paused.

## Menu Bar Controls

![SonosFlow Menu Bar Extra](../../../assets/screenshots/menubar-extra.webp)
*Figure: The Menu Bar Extra companion card showing room selector, now playing track, volume, and pinned favorites.*

Clicking the menu bar icon reveals a compact, lightweight control card:

1. **Active Room Switcher**:
   - A dropdown menu listing all discovered Sonos zone groups and stereo pairs.
   - Switch active rooms with a single click without opening the main window.
2. **Now Playing Card**:
   - 54×54 pt artwork thumbnail.
   - Title, artist, and elapsed / total duration.
3. **Transport & Volume**:
   - Backward, Play/Pause, and Forward buttons.
   - Compact volume slider and percentage readout.
4. **Quick Pinned Favorites**:
   - Instant access to your top 3 pinned Sonos favorites (e.g. YouTube Music playlists, Sonos Radio stations).
5. **Quick Shortcuts**:
   - **Open SonosFlow**: Brings the full window to the foreground.
   - **Miniplayer**: Jumps straight into compact floating miniplayer mode.
   - **Quit**: Gracefully shuts down the app and terminates the `mcp-sonos` child process.
