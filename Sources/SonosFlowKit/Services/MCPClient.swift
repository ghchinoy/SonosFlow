import Foundation

public actor MCPClient {
    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var isRunning: Bool = false
    private var pendingRequests: [Int: CheckedContinuation<[String: Any], Error>] = [:]
    private var requestIdCounter: Int = 0
    private var buffer = Data()
    private var stdoutContinuation: AsyncStream<Data>.Continuation?
    private var streamReaderTask: Task<Void, Never>?
    public private(set) var availableToolNames: Set<String> = []
    public private(set) var currentBinaryPath: String?
    public private(set) var binaryStartedModificationDate: Date?

    public init() {}

    public func hasTool(_ name: String) -> Bool {
        return availableToolNames.contains(name)
    }

    /// Checks if the binary file on disk has a modification timestamp newer than when the current process started.
    public func isBinaryNewerOnDisk() -> Bool {
        guard let path = currentBinaryPath, let startedMtime = binaryStartedModificationDate else {
            return false
        }
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let currentMtime = attrs[.modificationDate] as? Date else {
            return false
        }
        return currentMtime > startedMtime
    }

    public func isConnected() -> Bool {
        return isRunning && process?.isRunning == true
    }

    public func start(binaryPath: String) throws {
        if isRunning {
            stop()
        }

        guard FileManager.default.isExecutableFile(atPath: binaryPath) else {
            let err = "Binary at '\(binaryPath)' is not executable or does not exist."
            AppLogger.shared.error(err, category: "MCP")
            throw NSError(domain: "MCPClient", code: 1, userInfo: [NSLocalizedDescriptionKey: err])
        }

        AppLogger.shared.log("Launching mcp-sonos binary at: \(binaryPath)", category: "MCP")

        self.currentBinaryPath = binaryPath
        if let attrs = try? FileManager.default.attributesOfItem(atPath: binaryPath),
           let mtime = attrs[.modificationDate] as? Date {
            self.binaryStartedModificationDate = mtime
        } else {
            self.binaryStartedModificationDate = nil
        }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: binaryPath)
        p.arguments = []

        // Inherit environment with PATH
        p.environment = ProcessInfo.processInfo.environment

        let sin = Pipe()
        let sout = Pipe()
        let serr = Pipe()

        p.standardInput = sin
        p.standardOutput = sout
        p.standardError = serr

        self.process = p
        self.stdinPipe = sin
        self.stdoutPipe = sout
        self.stderrPipe = serr

        // Log stderr for diagnostics
        serr.fileHandleForReading.readabilityHandler = { h in
            let data = h.availableData
            if !data.isEmpty, let msg = String(data: data, encoding: .utf8) {
                let trimmed = msg.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    AppLogger.shared.log(trimmed, category: "MCP-STDERR")
                }
            }
        }

        // Setup FIFO ordered stdout stream processing
        let (stream, continuation) = AsyncStream<Data>.makeStream()
        self.stdoutContinuation = continuation

        sout.fileHandleForReading.readabilityHandler = { h in
            let data = h.availableData
            if !data.isEmpty {
                continuation.yield(data)
            }
        }

        self.streamReaderTask = Task { [weak self] in
            for await chunk in stream {
                guard let self = self else { break }
                await self.handleStdoutData(chunk)
            }
        }

        p.terminationHandler = { [weak self] proc in
            Task { [weak self] in
                await self?.handleProcessTerminated(exitCode: proc.terminationStatus)
            }
        }

        try p.run()
        self.isRunning = true
        AppLogger.shared.log("mcp-sonos process started (PID: \(p.processIdentifier))", category: "MCP")
    }

    private func handleProcessTerminated(exitCode: Int32) {
        AppLogger.shared.warning("mcp-sonos process exited with code \(exitCode)", category: "MCP")
        isRunning = false
        for (_, continuation) in pendingRequests {
            continuation.resume(throwing: NSError(domain: "MCPClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "mcp-sonos exited unexpectedly (code \(exitCode))."]))
        }
        pendingRequests.removeAll()
    }

    public func stop() {
        isRunning = false
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        stdoutContinuation?.finish()
        stdoutContinuation = nil
        streamReaderTask?.cancel()
        streamReaderTask = nil

        if let p = process, p.isRunning {
            p.terminationHandler = nil
            p.terminate()
            AppLogger.shared.log("mcp-sonos process terminated", category: "MCP")
        }
        process = nil
        stdinPipe = nil
        stdoutPipe = nil
        stderrPipe = nil
        binaryStartedModificationDate = nil

        for (_, continuation) in pendingRequests {
            continuation.resume(throwing: NSError(domain: "MCPClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Process stopped."]))
        }
        pendingRequests.removeAll()
    }

    private func handleStdoutData(_ data: Data) {
        buffer.append(data)
        var linesToProcess: [String] = []

        while let newlineRange = buffer.range(of: Data([0x0A])) {
            let lineData = buffer.subdata(in: 0..<newlineRange.lowerBound)
            buffer.removeSubrange(0..<newlineRange.upperBound)
            if let str = String(data: lineData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !str.isEmpty {
                linesToProcess.append(str)
            }
        }

        for line in linesToProcess {
            if let jsonData = line.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                if let reqId = json["id"] as? Int, let continuation = pendingRequests.removeValue(forKey: reqId) {
                    continuation.resume(returning: json)
                }
            }
        }
    }

    private func nextRequestId() -> Int {
        requestIdCounter += 1
        return requestIdCounter
    }

    public func sendRequest(method: String, params: [String: Any], timeoutSeconds: TimeInterval = 20.0) async throws -> [String: Any] {
        guard isRunning, let stdin = stdinPipe?.fileHandleForWriting else {
            throw NSError(domain: "MCPClient", code: 2, userInfo: [NSLocalizedDescriptionKey: "Sonos MCP Server is not running."])
        }

        let reqId = nextRequestId()
        let requestDict: [String: Any] = [
            "jsonrpc": "2.0",
            "id": reqId,
            "method": method,
            "params": params
        ]

        let data = try JSONSerialization.data(withJSONObject: requestDict, options: [])

        // Schedule timeout watchdog
        Task { [weak self, reqId] in
            try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
            await self?.handleTimeout(reqId: reqId, method: method, timeoutSeconds: timeoutSeconds)
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.pendingRequests[reqId] = continuation
            stdin.write(data)
            stdin.write("\n".data(using: .utf8)!)
        }
    }

    private func handleTimeout(reqId: Int, method: String, timeoutSeconds: TimeInterval) {
        if let continuation = pendingRequests.removeValue(forKey: reqId) {
            let err = "MCP request '\(method)' (ID: \(reqId)) timed out after \(Int(timeoutSeconds))s"
            AppLogger.shared.error(err, category: "MCP")
            continuation.resume(throwing: NSError(domain: "MCPClient", code: 408, userInfo: [NSLocalizedDescriptionKey: err]))
        }
    }

    public func sendNotification(method: String, params: [String: Any] = [:]) throws {
        guard isRunning, let stdin = stdinPipe?.fileHandleForWriting else { return }
        let notifDict: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method,
            "params": params
        ]
        let data = try JSONSerialization.data(withJSONObject: notifDict, options: [])
        stdin.write(data)
        stdin.write("\n".data(using: .utf8)!)
    }

    public func initializeAndVerify(binaryPath: String) async throws -> (serverInfo: MCPServerInfo, tools: [MCPTool]) {
        try start(binaryPath: binaryPath)

        // 1. Initialize with 12s timeout
        let initResponse = try await sendRequest(
            method: "initialize",
            params: [
                "protocolVersion": "2024-11-05",
                "capabilities": [:] as [String: Any],
                "clientInfo": [
                    "name": "SonosFlow",
                    "version": "1.0.0"
                ]
            ],
            timeoutSeconds: 12.0
        )

        var serverInfo = MCPServerInfo(name: "homectl-sonos", version: "1.0.0")
        if let result = initResponse["result"] as? [String: Any],
           let sInfo = result["serverInfo"] as? [String: Any] {
            serverInfo = MCPServerInfo(
                name: sInfo["name"] as? String ?? "homectl-sonos",
                version: sInfo["version"] as? String
            )
        }

        // 2. Initialized notification
        try sendNotification(method: "notifications/initialized")

        // 3. List tools with 12s timeout
        let toolsResponse = try await sendRequest(method: "tools/list", params: [:], timeoutSeconds: 12.0)
        var toolsList: [MCPTool] = []

        if let result = toolsResponse["result"] as? [String: Any],
           let tools = result["tools"] as? [[String: Any]] {
            for t in tools {
                let name = t["name"] as? String ?? ""
                let desc = t["description"] as? String
                toolsList.append(MCPTool(name: name, description: desc))
            }
        }

        self.availableToolNames = Set(toolsList.map(\.name))
        AppLogger.shared.log("Sonos MCP initialized: \(serverInfo.name) v\(serverInfo.version ?? ""), tools: \(toolsList.map(\.name))", category: "MCP")
        return (serverInfo, toolsList)
    }

    public func callTool(name: String, arguments: [String: Any], timeoutSeconds: TimeInterval = 15.0) async throws -> [String: Any] {
        let response = try await sendRequest(
            method: "tools/call",
            params: [
                "name": name,
                "arguments": arguments
            ],
            timeoutSeconds: timeoutSeconds
        )

        if let errorObj = response["error"] as? [String: Any] {
            let msg = errorObj["message"] as? String ?? "Unknown MCP Error"
            AppLogger.shared.error("MCP RPC error calling \(name): \(msg)", category: "MCP")
            throw NSError(domain: "MCPClient", code: 3, userInfo: [NSLocalizedDescriptionKey: msg])
        }

        guard let result = response["result"] as? [String: Any] else {
            throw NSError(domain: "MCPClient", code: 4, userInfo: [NSLocalizedDescriptionKey: "Invalid tool response format"])
        }

        if let isError = result["isError"] as? Bool, isError {
            var errorDetails = "Tool reported error"
            if let content = result["content"] as? [[String: Any]],
               let first = content.first,
               let text = first["text"] as? String {
                errorDetails = text
            }
            AppLogger.shared.error("Tool \(name) failed: \(errorDetails)", category: "MCP")
            throw NSError(domain: "MCPClient", code: 5, userInfo: [NSLocalizedDescriptionKey: errorDetails])
        }

        return result
    }

    /// Decodes a tool call result object into a Decodable type
    public static func decodeResult<T: Decodable>(_ result: [String: Any], as type: T.Type) throws -> T {
        let decoder = JSONDecoder()

        // 1. Check structuredContent
        if let structured = result["structuredContent"] {
            let data = try JSONSerialization.data(withJSONObject: structured, options: [])
            return try decoder.decode(T.self, from: data)
        }

        // 2. Check content array for JSON text
        if let content = result["content"] as? [[String: Any]] {
            for item in content {
                if let text = item["text"] as? String,
                   (text.hasPrefix("{") || text.hasPrefix("[")),
                   let data = text.data(using: .utf8) {
                    if let decoded = try? decoder.decode(T.self, from: data) {
                        return decoded
                    }
                }
            }
        }

        // 3. Fallback: serialize result directly
        let data = try JSONSerialization.data(withJSONObject: result, options: [])
        return try decoder.decode(T.self, from: data)
    }
}
