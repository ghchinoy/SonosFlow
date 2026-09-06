---
title: Troubleshooting & Diagnostics
description: Diagnosing network, process, or artwork issues with SonosFlow.
---

## Common Issues & Resolutions

### 1. "mcp-sonos process exited unexpectedly"
- **Cause**: The `mcp-sonos` binary could not be found, is missing execute permissions, or failed to start.
- **Fix**: Check `Settings (⌘,)` and verify that the "Effective Path" points to a valid executable (e.g. `/path/to/homectl/bin/mcp-sonos`). Run `make build` in the `homectl` repository if the binary has not been compiled.

### 2. "No speakers discovered on network"
- **Cause**: The Mac is on a separate VLAN or WiFi subnet where mDNS / UPnP discovery is blocked.
- **Fix**: Ensure the Mac and Sonos speakers are connected to the same subnet. Click "Rescan Network" in the sidebar or run `make spike` in Terminal to test raw SSDP/mDNS discovery.

### 3. Missing Album Art Thumbnails
- **Cause**: Port `1400` on the speaker is blocked or the media stream does not provide artwork metadata.
- **Fix**: Open `Settings (⌘,)` and click "Clear Cache" to force a fresh fetch, or test whether `http://<speaker-ip>:1400/getaa?...` is reachable with `curl`.

## Inspecting Logs

SonosFlow writes comprehensive application and subprocess diagnostics to:
```bash
~/Library/Logs/SonosFlow/sonosflow.log
```

To monitor logs in real time:
```bash
tail -f ~/Library/Logs/SonosFlow/sonosflow.log
```
Or click **Reveal Log** in the Settings window (`⌘,`).
