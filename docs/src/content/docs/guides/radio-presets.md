---
title: Internet Radio & Custom Presets
description: Guide to streaming live audio and saving custom radio presets in SonosFlow.
---

SonosFlow allows you to stream arbitrary internet radio streams, podcasts, and Icecast/Shoutcast links directly to any room on your Sonos network via the Model Context Protocol.

---

## Opening the Stream Player

![Audio Stream Player](../../../assets/screenshots/audio-stream.webp)
*Figure: The Audio Stream Player modal dialog with direct URL entry, curated presets, and save action.*

Press **`⌘U`**, click the **Stream** button in the sidebar footer, or select **Playback → Play Audio Stream...** in the macOS menu bar.

### Automatic Clipboard Detection
When you copy any stream link starting with `http://` or `https://` in Safari, Chrome, or Terminal, opening the stream dialog (`⌘U`) automatically pre-fills the URL into the input field.

---

## Playing a Stream

1. Paste or edit the stream URL (e.g. `https://stream.example.com/live.mp3`).
2. Optionally enter a station name (e.g. *"Radio Paradise Mellow"*).
3. Click **Play in Room** (or press `Return`).
4. Playback starts immediately on the selected Sonos group coordinator.

---

## Curated Presets

SonosFlow includes high-fidelity, ad-free stream presets ready for 1-click playback:

| Preset Name | Genre / Format | Stream URL |
|---|---|---|
| **SomaFM: Groove Salad** | Downtempo / Ambient | `https://ice1.somafm.com/groovesalad-128-mp3` |
| **KEXP 90.3 FM Seattle** | Indie / Alternative | `https://kexp.streamguys1.com/kexp128.mp3` |
| **BBC Radio 6 Music** | Alternative / Eclectic | `http://stream.live.vc.bbcmedia.co.uk/bbc_6music` |
| **SomaFM: Drone Zone** | Atmospheric Ambient | `https://ice1.somafm.com/dronezone-128-mp3` |
| **WNYC 93.9 FM New York** | Public Radio / News | `https://fm939.wnyc.org/wnycfm-web` |
| **SomaFM: DEF CON Radio** | Electronic / Cyberpunk | `https://ice1.somafm.com/defcon-128-mp3` |

Clicking any preset chip immediately tunes your active room to that station.

---

## Saving Custom Presets

You can build your own personalized station library:

1. Type or paste your custom radio URL into the **Stream URL** field.
2. Enter the station name in **Optional Display Title**.
3. Click **Save Preset** (`bookmark.fill`).
4. Your station appears under **MY SAVED PRESETS** with a dedicated purple star badge.
5. Saved presets persist permanently in macOS `UserDefaults`.

### Removing Custom Presets
Hover over any saved preset and click the red trash icon (`trash`) to remove it from your library.
