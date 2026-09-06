---
title: System Media Keys, Streams & Group Volumes
description: Hardware media keys, internet radio stream playback, and individual speaker volume controls.
---

SonosFlow deeply integrates with macOS system features, allowing you to control whole-home audio using Apple hardware keys, stream custom web audio, and fine-tune speaker balances.

---

## 1. Hardware Media Keys & Control Center

SonosFlow connects directly to Apple's `MediaPlayer.framework` (`MPRemoteCommandCenter` and `MPNowPlayingInfoCenter`).

### Supported Inputs
- **F8 Key / Play-Pause Button**: Toggles playback on the active Sonos room.
- **F9 Key / Next Button**: Skips to the next track in the queue.
- **F7 Key / Previous Button**: Returns to the previous track.
- **AirPods & Bluetooth Headphones**: Tap or stem squeeze actions are mapped directly to Sonos transport actions.
- **Touch Bar & Media Keyboards**: Native scrubbing and playback buttons reflect live speaker status.

### macOS Control Center
Whenever audio is active, SonosFlow publishes metadata to the macOS Control Center Now Playing widget:
- Displays high-resolution album artwork loaded from the two-tier cache.
- Shows track title, artist, and album.
- Real-time elapsed time and total duration.
- Interactive play, pause, next, and previous buttons.

---

## 2. Audio Stream Player (`⌘U`)

SonosFlow supports streaming arbitrary audio streams—such as live internet radio, podcasts, or Icecast/Shoutcast URLs—directly into any Sonos room using `sonos_play_stream`.

### How to Use
1. Press **`⌘U`** or click **Stream** in the sidebar.
2. Paste any `http://` or `https://` audio stream URL (SonosFlow automatically pre-fills URLs copied to your clipboard).
3. Optionally enter a display title (e.g. *"My Favorite Radio"*).
4. Click **Play Stream** to start immediate playback.

### Curated Radio Presets
The stream dialog includes built-in one-click presets for popular independent radio stations:
- **SomaFM: Groove Salad** (Downtempo / Ambient)
- **KEXP 90.3 FM Seattle** (Indie / Alternative)
- **BBC Radio 6 Music** (Alternative / Eclectic)
- **SomaFM: Drone Zone** (Atmospheric Ambient)
- **WNYC 93.9 FM New York** (Public Radio / News)
- **SomaFM: DEF CON Radio** (Electronic / Hacker)

Recent custom streams are automatically saved and displayed for quick access.

---

## 3. Expandable Group & Individual Speaker Volumes

In a Sonos household, stereo pairs (e.g. paired Play:1s in an Office) and multi-room groups (e.g. TV Room Arc + Play:3 surrounds) often require balancing.

### Master vs. Individual Volume
- **Master Slider**: The primary transport slider adjusts the room's master volume, raising or lowering all speakers proportionally.
- **Individual Sliders**: When a group contains more than one physical speaker, a slider icon (`slider.horizontal.2`) appears beside the volume percentage.
- Clicking this button opens the **Speaker Volumes Popover**:
  - Displays each physical speaker with its room name and host/coordinator badge.
  - Allows adjusting each speaker's volume independently (0–100%) to dial in the perfect stereo or acoustic balance.
