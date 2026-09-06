---
title: Two-Tier Artwork Caching
description: Mechanics of the in-memory and persistent SHA-256 disk cache for album covers.
---

Sonos devices and streaming providers serve artwork in two different ways:
1. **Local Sonos UPnP Relative URLs**: `/getaa?s=1&u=x-sonos-http%3a...` served on the speaker at HTTP port `1400`.
2. **Cloud Streaming CDN URLs**: `https://yt3.googleusercontent.com/...` (YouTube Music) or `https://i.scdn.co/...` (Spotify).

SonosFlow standardizes these into a high-performance **two-tier cache**.

## Two-Tier Pipeline

```
Artwork Request (URL)
         │
         ▼
 ┌───────────────┐  HIT
 │ Memory Cache  ├────────► Return NSImage (<1ms)
 └───────┬───────┘
         │ MISS
         ▼
 ┌───────────────┐  HIT
 │  Disk Cache   ├────────► Load JPEG data, populate Memory Cache, return
 └───────┬───────┘
         │ MISS
         ▼
 ┌───────────────┐
 │ Network Fetch ├────────► Atomic disk write, populate Memory Cache, return
 └───────────────┘
```

### Tier 1: In-Memory `NSCache`
- Stores up to 200 decoded `NSImage` instances in memory (~100 MB budget).
- Delivers instantaneous rendering when scrolling up and down long playback queues.

### Tier 2: Persistent Disk Cache
- **Storage Location**: `~/Library/Caches/com.sonosflow.app/Artwork/`
- **Keying Algorithm**: SHA-256 hex digest of the normalized absolute URL string:
  ```swift
  let hash = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
  let fileURL = artworkDir.appendingPathComponent("\(hash).jpg")
  ```
- **Atomicity**: Downloaded bytes are written with `Data.write(to:options: .atomic)` to prevent half-written or corrupted image files if the app closes mid-transfer.

## Title Bar Proxy Icon Integration

Because images are guaranteed to be stored on disk as standard JPEG files, `ArtworkCache.cachedFileURL(for: url)` returns a genuine file URL:

```swift
if let fileURL = await ArtworkCache.shared.cachedFileURL(for: artURL) {
    window.representedURL = fileURL
}
```

This unlocks macOS's built-in file proxy mechanics: dragging the document icon out of the title bar exports the cached JPEG directly to Finder or other applications.
