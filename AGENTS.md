<!-- headroom:rtk-instructions -->
# RTK (Rust Token Killer) - Token-Optimized Commands

When running shell commands, **always prefix with `rtk`**. This reduces context
usage by 60-90% with zero behavior change. If rtk has no filter for a command,
it passes through unchanged — so it is always safe to use.

## Key Commands
```bash
# Git (59-80% savings)
rtk git status          rtk git diff            rtk git log

# Files & Search (60-75% savings)
rtk ls <path>           rtk read <file>         rtk grep <pattern>
rtk find <pattern>      rtk diff <file>

# Test (90-99% savings) — shows failures only
rtk pytest tests/       rtk cargo test          rtk test <cmd>

# Build & Lint (80-90% savings) — shows errors only
rtk tsc                 rtk lint                rtk cargo build
rtk prettier --check    rtk mypy                rtk ruff check

# Analysis (70-90% savings)
rtk err <cmd>           rtk log <file>          rtk json <file>
rtk summary <cmd>       rtk deps                rtk env

# GitHub (26-87% savings)
rtk gh pr view <n>      rtk gh run list         rtk gh issue list

# Infrastructure (85% savings)
rtk docker ps           rtk kubectl get         rtk docker logs <c>

# Package managers (70-90% savings)
rtk pip list            rtk pnpm install        rtk npm run <script>
```

## Rules
- In command chains, prefix each segment: `rtk git add . && rtk git commit -m "msg"`
- For debugging, use raw command without rtk prefix
- `rtk proxy <cmd>` runs command without filtering but tracks usage
<!-- /headroom:rtk-instructions -->

# SonosFlow Agent Guidelines

## ⚠️ Official Sonos 27mcp Tool Inventory Watchdog
Sonos explicitly notes in their official hosted MCP server documentation that tool names, signatures, and capabilities **"will evolve without notice for agentic use"**.

Whenever updating this application, changing backends, or doing maintenance:
1. **Periodically Run the Exploration Spike**:
   ```bash
   make official-spike
   ```
2. **Review Schema Differences**: Check `git diff docs/official-mcp-tools.json` to see if Sonos added, renamed, or deprecated any tools at `https://mcp.ws.sonos.com/mcp`.
3. **Verify Feature Gating**: Never hardcode assumptions that a specific cloud tool exists. Always route feature availability through `ServerCapabilities` and `tools/list` negotiation so missing or renamed tools gracefully degrade rather than crash.

---

## 🛠️ Operational Rules & Core Mandates

1. **Protocol & Parser Verification**:
   - Never write or rewrite MCP client parsers against assumed response structures.
   - Run a read-only live probe against the real target server (`mcp-sonos` or `https://mcp.ws.sonos.com/mcp`) first.
   - Derive test fixtures directly from captured, redacted live payloads.
   - For an archive of specific protocol debugging insights, read **`docs/LESSONS.md`**.

2. **Strict Unit Test Isolation**:
   - Unit tests (`SonosFlowTests.swift`) must **NEVER** initiate outbound network connections or access developer Keychain credentials.
   - Always inject `MockSonosBackend` or `MockSonosService` for test isolation. All tests must execute offline in under 1 second.

3. **Dynamic Capability Introspection**:
   - Do not rely solely on `enum` arrays in `inputSchema` for capability discovery. Servers may express choices in property descriptions or through dedicated property presence (e.g. `repeat_mode` in `sonos_queue_edit`).
   - Use `MCPTool.hasProperty` and `MCPTool.propertyMentions` alongside `enumValues`.

4. **Homectl Collaboration Protocol**:
   - **Never edit files in `~/projects/homectl` directly.**
   - Request backend enhancements exclusively via `bd create` tasks in the homectl repository.
   - Respect homectl's **strict 12-tool limit**: always propose new action verbs inside existing tools (like `sonos_queue_edit` or `sonos_control`) rather than proposing new top-level tools.
   - Sound settings (Home Theater EQ) belong to **individual physical speakers**, whereas playback and transport commands belong to **Group Coordinators**. Never route speaker EQ commands through coordinators.

5. **Release Verification Checklist**:
   - Before completing tasks, always execute:
     ```bash
     make test && make docs-build && make install
     ```
   - Synchronize test count citations across `README.md`, `docs/user-guide.md`, and `docs/src/content/docs/guides/getting-started.md`.
   - After pushing to `origin main`, watch GitHub Actions deploy using `gh run watch`.


