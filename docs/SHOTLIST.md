# SonosFlow Screenshot Asset Catalog & Shot List

This internal catalog tracks all visual screenshot assets for SonosFlow documentation, guides, and README.

---

## Shot Inventory & Status

| # | Feature / Scene | Asset Name | Status | Used On | Notes |
|---|---|---|:---:|---|---|
| **01** | **Main Split View Window** | `main-window.webp` | `[x] Available` | README, Home (`index.mdx`), Getting Started, User Guide | Light mode, Office stereo pair selected, 176 tracks in queue. IP `192.168.4.99` blurred. |
| **02** | **Menu Bar Extra Companion** | `menubar-extra.webp` | `[x] Available` | Menu Bar Guide, User Guide | Status card with room dropdown, artwork, volume, and top 3 pinned favorites. |
| **03** | **Mode A Floating MiniPlayer** | `miniplayer.webp` | `[🔁 Retake Scheduled]` | MiniPlayer Guide, User Guide | Currently published. Retake scheduled to capture edge-to-edge layout after titlebar fix. |
| **04** | **Audio Stream Dialog** | `audio-stream.webp` | `[x] Available` | Radio Presets Guide, Media Controls Guide, User Guide | Sheet showing stream URL input, curated presets, and save button. IP blurred. |
| **05** | **Speaker Volumes Popover** | `group-volumes.webp` | `[ ] To Take` | Media Controls Guide, User Guide | Open by clicking `slider.horizontal.2` on a stereo pair (Office) or multi-room group. |
| **06** | **Queue Management: Hover & Menu** | `queue-reorder-menu.webp` | `[ ] To Take` | User Guide | Mouse hovering over a queue row showing the drag grip (`⠿`), hover trash icon, and right-click context menu. |
| **07** | **Active Filter Banner** | `queue-filtered.webp` | `[ ] To Take` | User Guide | Filter field with query (e.g. "ce"), showing active filter pill: `Showing 8 of 176 tracks matching "ce"`. |
| **08** | **Sonos Favorites Sheet** | `favorites-sheet.webp` | `[ ] To Take` | User Guide | Sheet displaying pinned Sonos Radio and YouTube Music favorites with cover artwork. |
| **09** | **Preferences / Settings Window** | `settings-window.webp` | `[ ] To Take` | Configuration Reference, User Guide | Preferences window showing effective path, polling slider, and artwork cache size stats. (Ensure paths are generic). |
| **10** | **macOS Control Center Now Playing** | `control-center.webp` | `[ ] To Take` | Media Controls Guide | macOS Control Center dropdown showing SonosFlow with cover art and scrubber. |
| **11** | **Stream Dialog: Saved Presets** | `stream-saved-presets.webp` | `[ ] To Take` | Radio Presets Guide | Audio stream dialog scrolled down showing user's "MY SAVED PRESETS" with purple star badges. |
| **12** | **App Menu Bar & Dock Menus** | `dock-menu.webp` | `[ ] To Take` | Keyboard Shortcuts, User Guide | Right-click contextual menu on macOS Dock icon showing transport controls and active rooms. |
| **13** | **Main Window in Dark Mode** | `main-window-dark.webp` | `[ ] To Take` | Home (`index.mdx`) | Alternative dark mode rendering for dark appearance showcase. |
| **14** | **MiniPlayer Morph Transition** | `miniplayer-morph.webp` | `[ ] Optional` | MiniPlayer Guide | Animated WebP or GIF recorded via Screen Recording showing `⌘M` window frame morphing. |

---

## Capture & Optimization Workflow

### 1. Window Capture with Native Drop Shadow
On macOS, press:
```
⇧ ⌘ 4
```
Then tap **`Space`** and click the target window. This captures the window with full Retina 2× resolution and transparent drop shadow.

### 2. Automatic WebP Conversion & IP Blurring
Run the repository conversion script:

```bash
# General conversion (e.g. Menu Bar Extra or MiniPlayer):
./scripts/screenshot-to-webp.sh /path/to/capture.png <output-name>

# With coordinator IP blurring (for full-window shots displaying local IPs):
./scripts/screenshot-to-webp.sh /path/to/capture.png <output-name> 788:252:926:292
```

The script:
1. Automatically blurs the coordinator IP bounding box if provided.
2. Compresses using Google `cwebp -q 82` with lossless alpha transparency.
3. Saves directly to `docs/src/assets/screenshots/<output-name>.webp`.

### 3. File Size & Storage Rules
- **Format**: WebP exclusively (`.webp`). Never commit raw PNGs or uncompressed JPEGs.
- **Location**: `docs/src/assets/screenshots/`.
- **Resolution**: Keep full 2× Retina dimensions so Starlight's image zoom plugin provides razor-sharp magnification.
