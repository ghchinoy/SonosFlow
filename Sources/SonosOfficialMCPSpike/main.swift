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

    static func main() async {
        setbuf(__stdoutp, nil)
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🌐 Official Sonos 27mcp Hosted Server Exploration Spike")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("📍 Target Endpoint: \(mcpEndpoint)")

        do {
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
                  let clientID = regJSON["client_id"] as? String else {
                print("❌ Dynamic Client Registration failed: \(String(data: regData, encoding: .utf8) ?? "")")
                exit(1)
            }
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
                  let accessToken = tokenJSON["access_token"] as? String else {
                print("❌ Token exchange failed: \(String(data: tokenData, encoding: .utf8) ?? "")")
                exit(1)
            }

            let scope = tokenJSON["scope"] as? String ?? ""
            let expiresIn = tokenJSON["expires_in"] as? Int ?? 0
            print("✅ Acquired Access Token (expires in \(expiresIn)s, scopes: \(scope))")

            // 5. Connect to Sonos 27mcp & List Tools
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
            let (initData, _) = try await URLSession.shared.data(for: initReq)
            let initDuration = Date().timeIntervalSince(t0)

            if let initJSON = try JSONSerialization.jsonObject(with: initData) as? [String: Any] {
                print("✅ Initialize handshake successful in \(Int(initDuration * 1000))ms:")
                if let res = initJSON["result"] as? [String: Any],
                   let sInfo = res["serverInfo"] as? [String: Any] {
                    print("   Server: \(sInfo["name"] ?? "Sonos 27mcp") v\(sInfo["version"] ?? "1.0")")
                }
            }

            // 6. Query tools/list
            print("\n6️⃣  Fetching complete official tool inventory (tools/list)...")
            var listReq = URLRequest(url: URL(string: mcpEndpoint)!)
            listReq.httpMethod = "POST"
            listReq.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            listReq.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let listPayload: [String: Any] = [
                "jsonrpc": "2.0",
                "id": 2,
                "method": "tools/list",
                "params": [:] as [String: Any]
            ]
            listReq.httpBody = try JSONSerialization.data(withJSONObject: listPayload)

            let t1 = Date()
            let (listData, _) = try await URLSession.shared.data(for: listReq)
            let listDuration = Date().timeIntervalSince(t1)

            guard let listJSON = try JSONSerialization.jsonObject(with: listData) as? [String: Any],
                  let res = listJSON["result"] as? [String: Any],
                  let tools = res["tools"] as? [[String: Any]] else {
                print("❌ Failed to parse tools/list response: \(String(data: listData, encoding: .utf8) ?? "")")
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
                let shortDesc = desc.replacingOccurrences(of: "\n", with: " ").prefix(85)
                print(String(format: " [%02d] %-32s - %@", idx + 1, name, String(shortDesc)))
            }

            print("\n🎉 Official Sonos 27mcp exploration complete!")
            exit(0)
        } catch {
            print("\n❌ Error during official MCP exploration: \(error)")
            exit(1)
        }
    }
}
