import Foundation
import Network
import CryptoKit
import AppKit

// MARK: - PKCE Utilities

struct PKCE {
    static func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
    }

    static func generateCodeChallenge(for verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
    }
}

// MARK: - Token Cache

struct CachedToken: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date
    let clientID: String

    var isValid: Bool {
        return expiresAt > Date().addingTimeInterval(120) // at least 2 minutes validity remaining
    }
}

// MARK: - Loopback OAuth Server

actor LoopbackAuthListener {
    private var listener: NWListener?
    private var codeContinuation: CheckedContinuation<String, Error>?

    func start() async throws -> String {
        let listener = try NWListener(using: .tcp, on: 8080)
        self.listener = listener

        return try await withCheckedThrowingContinuation { continuation in
            self.codeContinuation = continuation

            listener.newConnectionHandler = { [weak self] connection in
                connection.start(queue: .global())
                connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, isComplete, error in
                    guard let data = data, let req = String(data: data, encoding: .utf8) else {
                        return
                    }

                    // Look for GET /callback?code=...
                    if let firstLine = req.components(separatedBy: "\r\n").first,
                       let range = firstLine.range(of: "code=") {
                        let afterCode = String(firstLine[range.upperBound...])
                        let code = afterCode.components(separatedBy: CharacterSet(charactersIn: " &")).first ?? ""

                        let html = """
                        HTTP/1.1 200 OK\r
                        Content-Type: text/html; charset=utf-8\r
                        Connection: close\r
                        \r
                        <!DOCTYPE html>
                        <html>
                        <head><title>SonosFlow Authorization Successful</title></head>
                        <body style="font-family: -apple-system, sans-serif; text-align: center; padding: 50px;">
                            <h2 style="color: #2e7d32;">SonosFlow: Authorization Successful!</h2>
                            <p>You may now close this browser tab and return to the terminal.</p>
                        </body>
                        </html>
                        """
                        connection.send(content: html.data(using: .utf8), completion: .contentProcessed({ _ in
                            connection.cancel()
                        }))

                        Task { [weak self] in
                            await self?.resumeWithCode(code)
                        }
                    }
                }
            }

            listener.stateUpdateHandler = { state in
                if case .failed(let err) = state {
                    continuation.resume(throwing: err)
                }
            }

            listener.start(queue: .global())
        }
    }

    private func resumeWithCode(_ code: String) {
        listener?.cancel()
        listener = nil
        codeContinuation?.resume(returning: code)
        codeContinuation = nil
    }

    func manualProvideCode(_ rawInput: String) {
        var clean = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.contains("code=") {
            let parts = clean.components(separatedBy: "code=")
            if parts.count > 1 {
                clean = parts[1].components(separatedBy: CharacterSet(charactersIn: " &#")).first ?? clean
            }
        }
        if !clean.isEmpty {
            resumeWithCode(clean)
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }
}

// MARK: - Main Spike Harness

@main
struct SonosOfficialMCPSpike {
    static let issuer = "https://mcp.ws.sonos.com"
    static let redirectURI = "http://localhost:8080/callback"
    static let mcpEndpoint = "https://mcp.ws.sonos.com/mcp"
    static let tokenCacheFile = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".official-token.json")

    static func main() async {
        setbuf(__stdoutp, nil)
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🌐 Official Sonos 27mcp Hosted Server Exploration Spike")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("📍 Target Endpoint: \(mcpEndpoint)")

        do {
            var accessToken: String = ""
            var clientID: String = ""

            // Check for cached valid token
            if let cachedData = try? Data(contentsOf: tokenCacheFile),
               let cached = try? JSONDecoder().decode(CachedToken.self, from: cachedData),
               cached.isValid {
                print("\n🔑 Found valid cached token (expires in \(Int(cached.expiresAt.timeIntervalSinceNow))s). Skipping browser login!")
                accessToken = cached.accessToken
                clientID = cached.clientID
            } else {
                // 1. Discover OAuth Configuration
                print("\n1️⃣  Discovering OAuth Authorization Metadata...")
                let discoURL = URL(string: "\(issuer)/.well-known/oauth-authorization-server")!
                let (discoData, _) = try await URLSession.shared.data(from: discoURL)
                guard let discoJSON = try JSONSerialization.jsonObject(with: discoData) as? [String: Any] else {
                    print("❌ Failed to parse authorization discovery JSON.")
                    exit(1)
                }
                let registerEndpoint = discoJSON["registration_endpoint"] as? String ?? "\(issuer)/mcp-oauth/register"
                let authEndpoint = discoJSON["authorization_endpoint"] as? String ?? "\(issuer)/mcp-oauth/authorize"
                let tokenEndpoint = discoJSON["token_endpoint"] as? String ?? "\(issuer)/mcp-oauth/token"
                print("✅ Discovered endpoints:")
                print("   • Register: \(registerEndpoint)")
                print("   • Authorize: \(authEndpoint)")
                print("   • Token:    \(tokenEndpoint)")

                // 2. Dynamic Client Registration (RFC 7591)
                print("\n2️⃣  Performing Dynamic Client Registration (RFC 7591)...")
                var regReq = URLRequest(url: URL(string: registerEndpoint)!)
                regReq.httpMethod = "POST"
                regReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
                let regPayload: [String: Any] = [
                    "client_name": "SonosFlow-Spike",
                    "redirect_uris": [redirectURI]
                ]
                regReq.httpBody = try JSONSerialization.data(withJSONObject: regPayload)
                let (regData, regResp) = try await URLSession.shared.data(for: regReq)
                guard let httpReg = regResp as? HTTPURLResponse, httpReg.statusCode == 200 || httpReg.statusCode == 201,
                      let regJSON = try JSONSerialization.jsonObject(with: regData) as? [String: Any],
                      let newClientID = regJSON["client_id"] as? String else {
                    print("❌ Dynamic Client Registration failed: \(String(data: regData, encoding: .utf8) ?? "")")
                    exit(1)
                }
                clientID = newClientID
                print("✅ Registered Client ID: \(clientID.prefix(25))...")

                // 3. PKCE Generation & Browser Authorization
                print("\n3️⃣  Generating PKCE verifier & starting local OAuth callback listener...")
                let verifier = PKCE.generateCodeVerifier()
                let challenge = PKCE.generateCodeChallenge(for: verifier)

                var authURLComponents = URLComponents(string: authEndpoint)!
                authURLComponents.queryItems = [
                    URLQueryItem(name: "response_type", value: "code"),
                    URLQueryItem(name: "client_id", value: clientID),
                    URLQueryItem(name: "redirect_uri", value: redirectURI),
                    URLQueryItem(name: "scope", value: "playback-control-all partner-content:read"),
                    URLQueryItem(name: "code_challenge", value: challenge),
                    URLQueryItem(name: "code_challenge_method", value: "S256"),
                    URLQueryItem(name: "state", value: UUID().uuidString)
                ]

                guard let authURL = authURLComponents.url else {
                    print("❌ Failed to construct authorization URL.")
                    exit(1)
                }

                print("🌐 Opening default browser for Sonos Account Authorization...")
                print("   URL: \(authURL.absoluteString)")
                NSWorkspace.shared.open(authURL)

                print("\n⏳ Listening on \(redirectURI) for OAuth callback...")
                print("   (After approving in the browser, you will be redirected automatically,")
                print("    or you can paste the redirected URL / authorization code here):")
                let listener = LoopbackAuthListener()
                Task.detached {
                    if let line = readLine() {
                        await listener.manualProvideCode(line)
                    }
                }
                let code = try await listener.start()
                print("✅ Captured authorization code: \(code.prefix(15))...")

                // 4. Token Exchange
                print("\n4️⃣  Exchanging code for Access Token...")
                var tokenReq = URLRequest(url: URL(string: tokenEndpoint)!)
                tokenReq.httpMethod = "POST"
                tokenReq.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

                let formParts: [String] = [
                    "grant_type=authorization_code",
                    "client_id=\(clientID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")",
                    "code=\(code.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")",
                    "redirect_uri=\(redirectURI.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")",
                    "code_verifier=\(verifier.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
                ]
                tokenReq.httpBody = formParts.joined(separator: "&").data(using: .utf8)

                let (tokenData, tokenResp) = try await URLSession.shared.data(for: tokenReq)
                guard let httpToken = tokenResp as? HTTPURLResponse, httpToken.statusCode == 200,
                      let tokenJSON = try JSONSerialization.jsonObject(with: tokenData) as? [String: Any],
                      let newAccessToken = tokenJSON["access_token"] as? String else {
                    print("❌ Token exchange failed: \(String(data: tokenData, encoding: .utf8) ?? "")")
                    exit(1)
                }

                accessToken = newAccessToken
                let refreshToken = tokenJSON["refresh_token"] as? String
                let scope = tokenJSON["scope"] as? String ?? ""
                let expiresIn = tokenJSON["expires_in"] as? Int ?? 86400
                print("✅ Acquired Access Token (expires in \(expiresIn)s, scopes: \(scope))")

                // Cache token locally for fast re-runs
                let cached = CachedToken(
                    accessToken: accessToken,
                    refreshToken: refreshToken,
                    expiresAt: Date().addingTimeInterval(TimeInterval(expiresIn)),
                    clientID: clientID
                )
                if let encoded = try? JSONEncoder().encode(cached) {
                    try? encoded.write(to: tokenCacheFile, options: .atomic)
                    print("💾 Saved token cache to .official-token.json")
                }
            }

            // 5. Connect to Sonos 27mcp & Handshake
            print("\n5️⃣  Connecting to Sonos 27mcp endpoint via JSON-RPC 2.0...")
            var initReq = URLRequest(url: URL(string: mcpEndpoint)!)
            initReq.httpMethod = "POST"
            initReq.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            initReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
            initReq.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")

            let initPayload: [String: Any] = [
                "jsonrpc": "2.0",
                "id": 1,
                "method": "initialize",
                "params": [
                    "protocolVersion": "2024-11-05",
                    "capabilities": [:] as [String: Any],
                    "clientInfo": [
                        "name": "SonosFlow-Spike",
                        "version": "1.0.0"
                    ]
                ]
            ]
            initReq.httpBody = try JSONSerialization.data(withJSONObject: initPayload)

            let t0 = Date()
            let (initData, initResp) = try await URLSession.shared.data(for: initReq)
            let initDuration = Date().timeIntervalSince(t0)

            let initJSON = try parseMCPResponse(data: initData, response: initResp)
            print("✅ Initialize handshake successful in \(Int(initDuration * 1000))ms:")
            if let res = initJSON["result"] as? [String: Any],
               let sInfo = res["serverInfo"] as? [String: Any] {
                print("   Server: \(sInfo["name"] ?? "Sonos 27mcp") v\(sInfo["version"] ?? "1.0")")
            }

            // Send notifications/initialized
            var notifReq = URLRequest(url: URL(string: mcpEndpoint)!)
            notifReq.httpMethod = "POST"
            notifReq.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            notifReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let notifPayload: [String: Any] = [
                "jsonrpc": "2.0",
                "method": "notifications/initialized",
                "params": [:] as [String: Any]
            ]
            notifReq.httpBody = try JSONSerialization.data(withJSONObject: notifPayload)
            _ = try? await URLSession.shared.data(for: notifReq)

            // 6. Query tools/list
            print("\n6️⃣  Fetching complete official tool inventory (tools/list)...")
            var listReq = URLRequest(url: URL(string: mcpEndpoint)!)
            listReq.httpMethod = "POST"
            listReq.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            listReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
            listReq.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")

            let listPayload: [String: Any] = [
                "jsonrpc": "2.0",
                "id": 2,
                "method": "tools/list",
                "params": [:] as [String: Any]
            ]
            listReq.httpBody = try JSONSerialization.data(withJSONObject: listPayload)

            let t1 = Date()
            let (listData, listResp) = try await URLSession.shared.data(for: listReq)
            let listDuration = Date().timeIntervalSince(t1)

            let listJSON = try parseMCPResponse(data: listData, response: listResp)

            guard let res = listJSON["result"] as? [String: Any],
                  let tools = res["tools"] as? [[String: Any]] else {
                print("❌ Failed to find tools in response: \(listJSON)")
                exit(1)
            }

            print("✅ Retrieved \(tools.count) tools from Sonos 27mcp in \(Int(listDuration * 1000))ms!\n")

            // Format and save to docs/official-mcp-tools.json
            let outputDir = URL(fileURLWithPath: "/Users/ghchinoy/projects/sonos-swift-mcp/docs")
            let outputFile = outputDir.appendingPathComponent("official-mcp-tools.json")
            let prettyData = try JSONSerialization.data(withJSONObject: tools, options: [.prettyPrinted, .sortedKeys])
            try prettyData.write(to: outputFile)
            print("💾 Saved full tool catalog to \(outputFile.path)")

            // Display tool overview
            print("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("📋 Official Sonos 27mcp Tools Inventory (\(tools.count) Tools):")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            for (idx, t) in tools.enumerated() {
                let name = t["name"] as? String ?? "unknown"
                let desc = t["description"] as? String ?? "No description"
                let shortDesc = desc.replacingOccurrences(of: "\n", with: " ").prefix(80)
                let paddedName = name.padding(toLength: 36, withPad: " ", startingAt: 0)
                let paddedIdx = String(format: "%02d", idx + 1)
                print(" [\(paddedIdx)] \(paddedName) - \(shortDesc)")
            }

            // 7. Live Query Benchmark: get_households_and_groups_and_players
            print("\n7️⃣  Executing live cloud query (get_households_and_groups_and_players)...")
            var queryReq = URLRequest(url: URL(string: mcpEndpoint)!)
            queryReq.httpMethod = "POST"
            queryReq.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            queryReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
            queryReq.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")

            let queryPayload: [String: Any] = [
                "jsonrpc": "2.0",
                "id": 3,
                "method": "tools/call",
                "params": [
                    "name": "get_households_and_groups_and_players",
                    "arguments": [:] as [String: Any]
                ]
            ]
            queryReq.httpBody = try JSONSerialization.data(withJSONObject: queryPayload)

            let tQuery = Date()
            let (queryData, queryResp) = try await URLSession.shared.data(for: queryReq)
            let queryLatency = Date().timeIntervalSince(tQuery)

            let queryJSON = try parseMCPResponse(data: queryData, response: queryResp)
            print("✅ Live cloud call succeeded in \(Int(queryLatency * 1000))ms round-trip!")
            if let res = queryJSON["result"] as? [String: Any] {
                if let structured = res["structuredContent"] as? [String: Any] {
                    let pretty = try? JSONSerialization.data(withJSONObject: structured, options: .prettyPrinted)
                    let str = String(data: pretty ?? Data(), encoding: .utf8) ?? ""
                    print("   Returned Cloud Topology Structure (first 500 chars):")
                    print("   " + str.prefix(500).replacingOccurrences(of: "\n", with: "\n   "))
                } else if let content = res["content"] as? [[String: Any]], let first = content.first, let text = first["text"] as? String {
                    print("   Returned Summary: \(text.prefix(300))")
                }
            }

            print("\n🎉 Official Sonos 27mcp exploration complete!")
            exit(0)
        } catch {
            print("\n❌ Error during official MCP exploration: \(error)")
            exit(1)
        }
    }

    /// Robust decoder supporting direct JSON, SSE 'data:' event lines, and JSON substrings
    static func parseMCPResponse(data: Data, response: URLResponse?) throws -> [String: Any] {
        if let http = response as? HTTPURLResponse {
            if http.statusCode >= 400 {
                let bodyStr = String(data: data, encoding: .utf8) ?? ""
                print("❌ HTTP \(http.statusCode) response from MCP server:")
                print(bodyStr)
                throw NSError(domain: "SonosOfficialMCP", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(bodyStr)"])
            }
        }

        // 1. Direct JSON parse
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return json
        }

        // 2. SSE line parsing: check for lines with data:
        let rawStr = String(data: data, encoding: .utf8) ?? ""
        let lines = rawStr.components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("data:") {
                let payload = trimmed.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
                if let lineData = payload.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] {
                    return json
                }
            }
        }

        // 3. Fallback: find outer-most JSON object {...}
        if let firstIdx = rawStr.firstIndex(of: "{"),
           let lastIdx = rawStr.lastIndex(of: "}") {
            let subStr = String(rawStr[firstIdx...lastIdx])
            if let subData = subStr.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: subData) as? [String: Any] {
                return json
            }
        }

        print("❌ Could not parse MCP response. Raw response body (length \(data.count) bytes):")
        print("----------------------------------------------------------------")
        print(rawStr)
        print("----------------------------------------------------------------")
        throw NSError(domain: "SonosOfficialMCP", code: -1, userInfo: [NSLocalizedDescriptionKey: "Malformed response: \(rawStr.prefix(200))"])
    }
}
