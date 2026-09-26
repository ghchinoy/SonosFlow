import Foundation
import CryptoKit
import Network
import AppKit

public actor CloudMCPClient {
    public static let defaultIssuer = "https://mcp.ws.sonos.com"
    public static let defaultMcpEndpoint = "https://mcp.ws.sonos.com/mcp"
    public static let defaultRedirectURI = "http://localhost:8080/callback"

    private let issuer: String
    private let mcpEndpoint: String
    private let redirectURI: String
    private let tokenStorage: CloudTokenStorage

    private var activeToken: CloudToken?
    private var requestIdCounter: Int = 0
    public private(set) var availableToolNames: Set<String> = []
    public private(set) var serverInfo: MCPServerInfo?

    public init(
        issuer: String = defaultIssuer,
        mcpEndpoint: String = defaultMcpEndpoint,
        redirectURI: String = defaultRedirectURI,
        tokenStorage: CloudTokenStorage = .shared
    ) {
        self.issuer = issuer
        self.mcpEndpoint = mcpEndpoint
        self.redirectURI = redirectURI
        self.tokenStorage = tokenStorage
    }

    public func hasValidToken() -> Bool {
        if let token = activeToken, token.isValid {
            return true
        }
        if let stored = tokenStorage.loadToken(), stored.isValid {
            self.activeToken = stored
            return true
        }
        return false
    }

    public func signOut() {
        self.activeToken = nil
        tokenStorage.clearToken()
        self.availableToolNames = []
        self.serverInfo = nil
    }

    // MARK: - OAuth Flow

    public func authenticate(parentWindow: NSWindow? = nil) async throws -> CloudToken {
        // 1. Discover OAuth Configuration
        let discoURL = URL(string: "\(issuer)/.well-known/oauth-authorization-server")!
        let (discoData, _) = try await URLSession.shared.data(from: discoURL)
        guard let discoJSON = try JSONSerialization.jsonObject(with: discoData) as? [String: Any] else {
            throw NSError(domain: "CloudMCPClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse Sonos authorization discovery JSON."])
        }

        let registerEndpoint = discoJSON["registration_endpoint"] as? String ?? "\(issuer)/mcp-oauth/register"
        let authEndpoint = discoJSON["authorization_endpoint"] as? String ?? "\(issuer)/mcp-oauth/authorize"
        let tokenEndpoint = discoJSON["token_endpoint"] as? String ?? "\(issuer)/mcp-oauth/token"

        // 2. Dynamic Client Registration (RFC 7591)
        var clientID: String = ""
        if let existing = tokenStorage.loadToken() {
            clientID = existing.clientID
        }

        if clientID.isEmpty {
            var regReq = URLRequest(url: URL(string: registerEndpoint)!)
            regReq.httpMethod = "POST"
            regReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let regPayload: [String: Any] = [
                "client_name": "SonosFlow-macOS",
                "redirect_uris": [redirectURI]
            ]
            regReq.httpBody = try JSONSerialization.data(withJSONObject: regPayload)
            let (regData, regResp) = try await URLSession.shared.data(for: regReq)
            guard let httpReg = regResp as? HTTPURLResponse, (httpReg.statusCode == 200 || httpReg.statusCode == 201),
                  let regJSON = try JSONSerialization.jsonObject(with: regData) as? [String: Any],
                  let newID = regJSON["client_id"] as? String else {
                throw NSError(domain: "CloudMCPClient", code: -2, userInfo: [NSLocalizedDescriptionKey: "Dynamic Client Registration failed."])
            }
            clientID = newID
        }

        // 3. PKCE Generation & Loopback Listener
        let verifier = generateCodeVerifier()
        let challenge = generateCodeChallenge(for: verifier)

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
            throw NSError(domain: "CloudMCPClient", code: -3, userInfo: [NSLocalizedDescriptionKey: "Malformed authorization URL."])
        }

        // Launch browser and wait on loopback port 8080
        _ = await MainActor.run {
            NSWorkspace.shared.open(authURL)
        }

        let code = try await LoopbackOAuthListener.listen(onPort: 8080)

        // 4. Token Exchange
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
            throw NSError(domain: "CloudMCPClient", code: -4, userInfo: [NSLocalizedDescriptionKey: "Sonos token exchange failed."])
        }

        let refreshToken = tokenJSON["refresh_token"] as? String
        let expiresIn = tokenJSON["expires_in"] as? Int ?? 86400
        let token = CloudToken(
            accessToken: newAccessToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(expiresIn)),
            clientID: clientID
        )

        tokenStorage.saveToken(token)
        self.activeToken = token
        return token
    }

    private func refreshTokenIfNeeded() async throws -> String {
        if let token = activeToken, token.isValid {
            return token.accessToken
        }
        if let stored = tokenStorage.loadToken(), stored.isValid {
            self.activeToken = stored
            return stored.accessToken
        }

        // Try refresh if refresh_token available
        if let stored = tokenStorage.loadToken(), let refreshToken = stored.refreshToken {
            let tokenEndpoint = "\(issuer)/mcp-oauth/token"
            var tokenReq = URLRequest(url: URL(string: tokenEndpoint)!)
            tokenReq.httpMethod = "POST"
            tokenReq.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

            let formParts: [String] = [
                "grant_type=refresh_token",
                "client_id=\(stored.clientID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")",
                "refresh_token=\(refreshToken.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
            ]
            tokenReq.httpBody = formParts.joined(separator: "&").data(using: .utf8)

            let (tokenData, tokenResp) = try await URLSession.shared.data(for: tokenReq)
            if let httpToken = tokenResp as? HTTPURLResponse, httpToken.statusCode == 200,
               let tokenJSON = try JSONSerialization.jsonObject(with: tokenData) as? [String: Any],
               let newAccessToken = tokenJSON["access_token"] as? String {
                let newRefreshToken = tokenJSON["refresh_token"] as? String ?? refreshToken
                let expiresIn = tokenJSON["expires_in"] as? Int ?? 86400
                let refreshed = CloudToken(
                    accessToken: newAccessToken,
                    refreshToken: newRefreshToken,
                    expiresAt: Date().addingTimeInterval(TimeInterval(expiresIn)),
                    clientID: stored.clientID
                )
                tokenStorage.saveToken(refreshed)
                self.activeToken = refreshed
                return newAccessToken
            }
        }

        throw NSError(domain: "CloudMCPClient", code: 401, userInfo: [NSLocalizedDescriptionKey: "Sonos authorization expired. Please sign in to Sonos Cloud in Settings."])
    }

    // MARK: - MCP Protocol Handshake

    public func initialize() async throws -> (serverInfo: MCPServerInfo, tools: [MCPTool]) {
        let token = try await refreshTokenIfNeeded()

        // 1. Send initialize
        requestIdCounter += 1
        var initReq = URLRequest(url: URL(string: mcpEndpoint)!)
        initReq.httpMethod = "POST"
        initReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        initReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        initReq.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")

        let initPayload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": requestIdCounter,
            "method": "initialize",
            "params": [
                "protocolVersion": "2024-11-05",
                "capabilities": [:] as [String: Any],
                "clientInfo": [
                    "name": "SonosFlow-macOS",
                    "version": "1.0.0"
                ]
            ]
        ]
        initReq.httpBody = try JSONSerialization.data(withJSONObject: initPayload)

        let (initData, initResp) = try await URLSession.shared.data(for: initReq)
        let initJSON = try Self.parseMCPResponse(data: initData, response: initResp)

        var sInfo = MCPServerInfo(name: "Sonos 27mcp", version: "1.0")
        if let res = initJSON["result"] as? [String: Any],
           let rawInfo = res["serverInfo"] as? [String: Any] {
            sInfo = MCPServerInfo(
                name: rawInfo["name"] as? String ?? "Sonos 27mcp",
                version: rawInfo["version"] as? String ?? "1.0"
            )
        }
        self.serverInfo = sInfo

        // 2. Send notifications/initialized
        var notifReq = URLRequest(url: URL(string: mcpEndpoint)!)
        notifReq.httpMethod = "POST"
        notifReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        notifReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let notifPayload: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "notifications/initialized",
            "params": [:] as [String: Any]
        ]
        notifReq.httpBody = try JSONSerialization.data(withJSONObject: notifPayload)
        _ = try? await URLSession.shared.data(for: notifReq)

        // 3. Query tools/list
        requestIdCounter += 1
        var listReq = URLRequest(url: URL(string: mcpEndpoint)!)
        listReq.httpMethod = "POST"
        listReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        listReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        listReq.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")

        let listPayload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": requestIdCounter,
            "method": "tools/list",
            "params": [:] as [String: Any]
        ]
        listReq.httpBody = try JSONSerialization.data(withJSONObject: listPayload)

        let (listData, listResp) = try await URLSession.shared.data(for: listReq)
        let listJSON = try Self.parseMCPResponse(data: listData, response: listResp)

        var parsedTools: [MCPTool] = []
        if let res = listJSON["result"] as? [String: Any],
           let rawTools = res["tools"] as? [[String: Any]] {
            for t in rawTools {
                if let name = t["name"] as? String {
                    let desc = t["description"] as? String ?? ""
                    parsedTools.append(MCPTool(name: name, description: desc))
                }
            }
        }

        self.availableToolNames = Set(parsedTools.map(\.name))
        return (sInfo, parsedTools)
    }

    // MARK: - Tool Invocation

    public func callTool(name: String, arguments: [String: Any] = [:]) async throws -> Any {
        let token = try await refreshTokenIfNeeded()
        requestIdCounter += 1

        var req = URLRequest(url: URL(string: mcpEndpoint)!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")

        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": requestIdCounter,
            "method": "tools/call",
            "params": [
                "name": name,
                "arguments": arguments
            ]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, resp) = try await URLSession.shared.data(for: req)
        let json = try Self.parseMCPResponse(data: data, response: resp)

        if let err = json["error"] as? [String: Any] {
            let msg = err["message"] as? String ?? "Unknown MCP Error"
            let code = err["code"] as? Int ?? -1
            throw NSError(domain: "CloudMCPClient", code: code, userInfo: [NSLocalizedDescriptionKey: msg])
        }

        if let result = json["result"] {
            return result
        }

        return json
    }

    // MARK: - Helper Decoders

    static func parseMCPResponse(data: Data, response: URLResponse?) throws -> [String: Any] {
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            let bodyStr = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "CloudMCPClient", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(bodyStr)"])
        }

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return json
        }

        let rawStr = String(data: data, encoding: .utf8) ?? ""
        for line in rawStr.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("data:") {
                let payload = trimmed.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
                if let lineData = payload.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] {
                    return json
                }
            }
        }

        if let firstIdx = rawStr.firstIndex(of: "{"),
           let lastIdx = rawStr.lastIndex(of: "}") {
            let subStr = String(rawStr[firstIdx...lastIdx])
            if let subData = subStr.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: subData) as? [String: Any] {
                return json
            }
        }

        throw NSError(domain: "CloudMCPClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Malformed response: \(rawStr.prefix(200))"])
    }

    private func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
    }

    private func generateCodeChallenge(for verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
    }
}

// MARK: - Loopback OAuth Listener

private actor LoopbackOAuthListener {
    private var listener: NWListener?
    private var codeContinuation: CheckedContinuation<String, Error>?

    static func listen(onPort port: UInt16) async throws -> String {
        let loopback = LoopbackOAuthListener()
        return try await loopback.start(port: port)
    }

    func start(port: UInt16) async throws -> String {
        let listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port)!)
        self.listener = listener

        return try await withCheckedThrowingContinuation { continuation in
            self.codeContinuation = continuation

            listener.newConnectionHandler = { [weak self] connection in
                connection.start(queue: .global())
                connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, _, _ in
                    guard let data = data, let req = String(data: data, encoding: .utf8) else {
                        return
                    }

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
                            <p>You may now close this browser tab and return to SonosFlow.</p>
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
}
