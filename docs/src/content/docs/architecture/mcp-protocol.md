---
title: Direct MCP Integration
description: How SonosFlow communicates with the homectl Sonos MCP server via stdio JSON-RPC 2.0.
---

SonosFlow connects directly to the `mcp-sonos` binary provided by [`homectl`](https://ghchinoy.github.io/homectl/). Rather than relying on an HTTP daemon or intermediate proxy, it uses local process piping conforming to the Model Context Protocol (MCP) standard `2024-11-05`.

## Lifecycle & Handshake

When SonosFlow boots:

1. **Process Launch**:
   - `MCPClient` executes `mcp-sonos` with an open `stdin`, `stdout`, and `stderr` pipe.
2. **Initialize Request**:
   ```json
   {
     "jsonrpc": "2.0",
     "id": 1,
     "method": "initialize",
     "params": {
       "protocolVersion": "2024-11-05",
       "capabilities": {},
       "clientInfo": {
         "name": "SonosFlow",
         "version": "1.0.0"
       }
     }
   }
   ```
3. **Initialized Notification**:
   ```json
   {
     "jsonrpc": "2.0",
     "method": "notifications/initialized",
     "params": {}
   }
   ```
4. **Tool Inventory (`tools/list`)**:
   - SonosFlow queries registered tools and validates that `sonos_get_topology`, `sonos_get_now_playing`, `sonos_get_queue`, `sonos_control`, `sonos_set_volume`, and `sonos_list_favorites` are available.

## Tool Invocation Flow

When invoking a tool:
```
SwiftUI View
    │
    ▼
SonosCoordinator (Debounce & State Guard)
    │
    ▼
SonosService.getQueue(ip: "192.168.4.120", start: 0, count: 100)
    │
    ▼
MCPClient.callTool(name: "sonos_get_queue", arguments: [...])
    │  [Writes JSON line to stdin with ID: 4]
    ▼
mcp-sonos child process (Go SDK)
    │  [Dispatches SOAP/UPnP to speaker port 1400]
    │  [Writes JSON line to stdout with ID: 4]
    ▼
MCPClient.handleStdoutData()
    │  [Matches continuation by reqId: 4]
    ▼
MCPClient.decodeResult(as: QueueResult.self)
    │
    ▼
SonosCoordinator updates @Published queueItems
```

## Resilience & Structured Content

The Go MCP SDK returns tool results containing both `structuredContent` (raw dictionary object) and `content` (human-readable string array). SonosFlow's `MCPClient.decodeResult` checks:
1. `result["structuredContent"]` directly.
2. Falls back to scanning `result["content"]` text blocks for valid JSON arrays or objects.
3. Falls back to serializing the top-level `result` dictionary.

This dual-mode decoder guarantees that API schema variations across MCP server versions will not break client decoding.
