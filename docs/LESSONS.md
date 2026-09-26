# SonosFlow Engineering Lessons Learned & Retrospectives

This document catalogs practical engineering lessons, debugging retrospectives, and protocol insights gained during the development and maintenance of SonosFlow.

---

## Retrospective Log

### 1. Probe Live MCP Endpoints Before Authoring Client Parsers (Sep 2026)
- **Context**: Integrating the official Sonos 27mcp cloud server (`https://mcp.ws.sonos.com/mcp`).
- **Symptom**: Initial client parsed zero zone groups and crashed on track metadata when tested live.
- **Root Cause**: The client parser was written against assumed JSON structures (`{"households": [...]}`) rather than inspecting the actual MCP 2024-11-05 payload wrapping (`content: [{"type": "text", "text": "..."}]`) and real Sonos cloud schema keys (`householdId`, `groupId`, `currentTrack`).
- **Remediation**: Always execute a read-only probe against real servers before writing or modifying client parsers. Extract real JSON outputs, redact private identifiers/IPs, and store them directly as unit test fixtures.

### 2. Introspect Property Names & Descriptions, Not Just JSONSchema Enums (Sep 2026)
- **Context**: Enabling dynamic capability detection for `control-bjv` (shuffle, repeat, crossfade in `sonos_queue_edit`).
- **Symptom**: Unit tests passed on artificial fixtures, but live detection on `homectl-sonos` would fail to activate shuffle/repeat buttons.
- **Root Cause**: The Go MCP SDK (`github.com/modelcontextprotocol/go-sdk`) derived `action` as a plain `type: string` with allowed actions described in text (`"Queue edit action: 'remove', 'clear', 'reorder', 'shuffle'..."`), while adding dedicated properties (`repeat_mode`, `enabled`). Client code expecting an `enum: [...]` array received empty results.
- **Remediation**: Use multi-tiered capability detection: check `hasProperty("repeat_mode")`, search property descriptions and enums via `propertyMentions`, and fall back to tool presence. File companion backend tasks (`bd create`) to formalize schema enums where appropriate.

### 3. Guarantee Strict Network Isolation in Unit Test Suites (Sep 2026)
- **Context**: Unit testing `SonosCoordinator.switchEngine(to: .cloud)`.
- **Symptom**: Test execution paused for over 3 seconds and logged live cloud broker responses using credentials found in the developer's macOS Keychain.
- **Root Cause**: The engine switch method hardcoded instantiation of the live `SonosCloudBackend()`.
- **Remediation**: Allow dependency injection (`customBackend:`) in coordinator methods. All 30+ unit tests in `SonosFlowTests.swift` must execute completely offline in <0.05s without accessing network sockets or host Keychain items.

### 4. Account for Astro Starlight Directory Depth on Image Paths (Sep 2026)
- **Context**: Embedding WebP screenshots in Markdown guides.
- **Symptom**: `make docs-build` failed with `[ImageNotFound] ../../assets/screenshots/...`.
- **Root Cause**: Files in `docs/src/content/docs/guides/` are three levels below `src/` (`guides/` -> `docs/` -> `content/` -> `src/`), requiring `../../../assets/screenshots/...` rather than `../../`.
- **Remediation**: Always execute `make docs-build` locally prior to pushing documentation updates to ensure all asset paths and links resolve.

### 5. Verify Repository State with Tools Before Reporting Completion (Sep 2026)
- **Context**: Communicating status of documentation updates.
- **Symptom**: Reported that an official blog link had been added when the file edit had not yet been applied.
- **Root Cause**: Reporting planned actions rather than verifying the git staging area.
- **Remediation**: Always verify file state via `rtk git diff` or `grep` before confirming completion in agent responses.

---

## Architectural Guidelines for Future Work

1. **Per-Speaker vs. Group Coordinator Targeting**:
   - Volume, transport, queue management, and shuffle/repeat are authoritative on the **Group Coordinator**.
   - Soundbar Home Theater EQ (Night Sound / Speech Enhancement - `control-2ic`) is strictly **per physical speaker** and must never be redirected to coordinators.
2. **Homectl 12-Tool Limit**:
   - The local `homectl-sonos` MCP server maintains a strict 12-tool footprint. Never propose adding a 13th tool; multiplex new actions into existing tool verbs (e.g. `sonos_queue_edit`).
3. **Watchdog Verification**:
   - Periodically execute `make official-spike` and diff `docs/official-mcp-tools.json` to monitor upstream Sonos cloud API evolution.
