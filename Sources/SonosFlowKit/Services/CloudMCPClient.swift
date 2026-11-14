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
    private let tokenStorage: any CloudTokenStore
    private let urlSession: URLSession

    private var activeToken: CloudToken?
    private var requestIdCounter: Int = 0
    public private(set) var availableToolNames: Set<String> = []
    public private(set) var serverInfo: MCPServerInfo?

    public init(
        issuer: String = defaultIssuer,
        mcpEndpoint: String = defaultMcpEndpoint,
        redirectURI: String = defaultRedirectURI,
        tokenStorage: any CloudTokenStore = CloudTokenStorage.shared,
        urlSession: URLSession = .shared
    ) {
        self.issuer = issuer
        self.mcpEndpoint = mcpEndpoint
        self.redirectURI = redirectURI
        self.tokenStorage = tokenStorage
        self.urlSession = urlSession
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
        guard let discoURL = URL(string: "\(issuer)/.well-known/oauth-authorization-server"),
              discoURL.scheme?.lowercased() == "https" else {
            throw NSError(domain: "CloudMCPClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid OAuth issuer URL."])
        }
        let (discoData, _) = try await urlSession.data(from: discoURL)
        guard let discoJSON = try JSONSerialization.jsonObject(with: discoData) as? [String: Any] else {
            throw NSError(domain: "CloudMCPClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse Sonos authorization discovery JSON."])
        }

        let registerEndpoint = discoJSON["registration_endpoint"] as? String ?? "\(issuer)/mcp-oauth/register"
        let authEndpoint = discoJSON["authorization_endpoint"] as? String ?? "\(issuer)/mcp-oauth/authorize"
        let tokenEndpoint = discoJSON["token_endpoint"] as? String ?? "\(issuer)/mcp-oauth/token"

        for endpoint in [registerEndpoint, authEndpoint, tokenEndpoint] {
            guard Self.isSecureHTTPSURL(endpoint) else {
                throw NSError(domain: "CloudMCPClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Discovered OAuth endpoint must use HTTPS: \(endpoint)"])
            }
        }

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
            let (regData, regResp) = try await urlSession.data(for: regReq)
            guard let httpReg = regResp as? HTTPURLResponse, (httpReg.statusCode == 200 || httpReg.statusCode == 201),
                  let regJSON = try JSONSerialization.jsonObject(with: regData) as? [String: Any],
                  let newID = regJSON["client_id"] as? String else {
                throw NSError(domain: "CloudMCPClient", code: -2, userInfo: [NSLocalizedDescriptionKey: "Dynamic Client Registration failed."])
            }
            clientID = newID
        }

        // 3. PKCE Generation & Loopback Listener (with CSRF state verification)
        let verifier = generateCodeVerifier()
        let challenge = generateCodeChallenge(for: verifier)
        let expectedState = UUID().uuidString

        var authURLComponents = URLComponents(string: authEndpoint)!
        authURLComponents.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: "playback-control-all partner-content:read"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: expectedState)
        ]

        guard let authURL = authURLComponents.url else {
            throw NSError(domain: "CloudMCPClient", code: -3, userInfo: [NSLocalizedDescriptionKey: "Malformed authorization URL."])
        }

        // Launch browser and wait on loopback port 8080 (120s timeout)
        _ = await MainActor.run {
            NSWorkspace.shared.open(authURL)
        }

        let code = try await LoopbackOAuthListener.listen(onPort: 8080, expectedState: expectedState, timeoutSeconds: 120)

        // 4. Token Exchange
        var tokenReq = URLRequest(url: URL(string: tokenEndpoint)!)
        tokenReq.httpMethod = "POST"
        tokenReq.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var bodyComponents = URLComponents()
        bodyComponents.queryItems = [
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "code_verifier", value: verifier)
        ]
        tokenReq.httpBody = bodyComponents.percentEncodedQuery?.data(using: .utf8)

        let (tokenData, tokenResp) = try await urlSession.data(for: tokenReq)
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
            guard Self.isSecureHTTPSURL(tokenEndpoint), let tokenURL = URL(string: tokenEndpoint) else {
                throw NSError(domain: "CloudMCPClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid token endpoint."])
            }
            var tokenReq = URLRequest(url: tokenURL)
            tokenReq.httpMethod = "POST"
            tokenReq.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

            var bodyComponents = URLComponents()
            bodyComponents.queryItems = [
                URLQueryItem(name: "grant_type", value: "refresh_token"),
                URLQueryItem(name: "client_id", value: stored.clientID),
                URLQueryItem(name: "refresh_token", value: refreshToken)
            ]
            tokenReq.httpBody = bodyComponents.percentEncodedQuery?.data(using: .utf8)

            let (tokenData, tokenResp) = try await urlSession.data(for: tokenReq)
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

        let (initData, initResp) = try await urlSession.data(for: initReq)
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
        _ = try? await urlSession.data(for: notifReq)

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

        let (listData, listResp) = try await urlSession.data(for: listReq)
        let listJSON = try Self.parseMCPResponse(data: listData, response: listResp)

        var parsedTools: [MCPTool] = []
        if let res = listJSON["result"] as? [String: Any],
           let rawTools = res["tools"] as? [[String: Any]] {
            for t in rawTools {
                if let name = t["name"] as? String {
                    let desc = t["description"] as? String ?? ""
                    var schemaJSON: String? = nil
                    if let schema = t["inputSchema"],
                       let data = try? JSONSerialization.data(withJSONObject: schema) {
                        schemaJSON = String(data: data, encoding: .utf8)
                    }
                    parsedTools.append(MCPTool(name: name, description: desc, inputSchemaJSON: schemaJSON))
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

        let (data, resp) = try await urlSession.data(for: req)
        let json = try Self.parseMCPResponse(data: data, response: resp)

        if let err = json["error"] as? [String: Any] {
            let msg = err["message"] as? String ?? "Unknown MCP Error"
            let code = err["code"] as? Int ?? -1
            throw NSError(domain: "CloudMCPClient", code: code, userInfo: [NSLocalizedDescriptionKey: msg])
        }

        if let resultDict = json["result"] as? [String: Any] {
            if let isError = resultDict["isError"] as? Bool, isError {
                var errDetail = "Tool \(name) returned an error."
                if let content = resultDict["content"] as? [[String: Any]],
                   let text = content.first?["text"] as? String {
                    errDetail = text
                }
                throw NSError(domain: "CloudMCPClient", code: -5, userInfo: [NSLocalizedDescriptionKey: errDetail])
            }
            return resultDict
        }

        if let result = json["result"] {
            return result
        }

        return json
    }

    // MARK: - Security & Helper Decoders

    public static func isSecureHTTPSURL(_ raw: String) -> Bool {
        guard let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(),
              scheme == "https",
              let host = url.host,
              !host.isEmpty else {
            return false
        }
        return true
    }

    /// Parses an OAuth callback HTTP request line (`GET /callback?code=...&state=... HTTP/1.1`)
    /// and validates the CSRF `state` parameter.
    public static func parseOAuthCallback(request: String, expectedState: String) throws -> String {
        guard let firstLine = request.components(separatedBy: "\r\n").first else {
            throw NSError(domain: "CloudMCPClient", code: -10, userInfo: [NSLocalizedDescriptionKey: "Malformed OAuth callback request."])
        }
        let parts = firstLine.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 2 else {
            throw NSError(domain: "CloudMCPClient", code: -10, userInfo: [NSLocalizedDescriptionKey: "Missing request target in OAuth callback."])
        }
        let target = String(parts[1])
        guard let comps = URLComponents(string: "http://localhost\(target)") else {
            throw NSError(domain: "CloudMCPClient", code: -10, userInfo: [NSLocalizedDescriptionKey: "Invalid OAuth callback URL."])
        }

        let items = comps.queryItems ?? []
        if let oauthErr = items.first(where: { $0.name == "error" })?.value {
            let desc = items.first(where: { $0.name == "error_description" })?.value ?? oauthErr
            throw NSError(domain: "CloudMCPClient", code: -11, userInfo: [NSLocalizedDescriptionKey: "OAuth denied: \(desc)"])
        }

        guard let returnedState = items.first(where: { $0.name == "state" })?.value,
              returnedState == expectedState else {
            throw NSError(domain: "CloudMCPClient", code: -12, userInfo: [NSLocalizedDescriptionKey: "OAuth state mismatch (possible CSRF attempt)."])
        }

        guard let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            throw NSError(domain: "CloudMCPClient", code: -13, userInfo: [NSLocalizedDescriptionKey: "Missing authorization code in OAuth callback."])
        }

        return code
    }

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
    private var timeoutTask: Task<Void, Never>?

    static func listen(onPort port: UInt16, expectedState: String, timeoutSeconds: TimeInterval = 120) async throws -> String {
        let loopback = LoopbackOAuthListener()
        return try await loopback.start(port: port, expectedState: expectedState, timeoutSeconds: timeoutSeconds)
    }

    func start(port: UInt16, expectedState: String, timeoutSeconds: TimeInterval) async throws -> String {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host.ipv4(.loopback),
            port: NWEndpoint.Port(rawValue: port)!
        )
        let listener = try NWListener(using: params)
        self.listener = listener

        return try await withCheckedThrowingContinuation { continuation in
            self.codeContinuation = continuation

            self.timeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                await self?.fail(with: NSError(domain: "CloudMCPClient", code: 408, userInfo: [NSLocalizedDescriptionKey: "Sonos sign-in timed out after \(Int(timeoutSeconds))s."]))
            }

            listener.newConnectionHandler = { [weak self] connection in
                connection.start(queue: .global())
                connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, _ in
                    guard let data = data, let req = String(data: data, encoding: .utf8) else {
                        connection.cancel()
                        return
                    }

                    // Ignore browser pre-requests like /favicon.ico
                    if req.hasPrefix("GET /favicon.ico") {
                        let notFound = "HTTP/1.1 404 Not Found\r\nConnection: close\r\n\r\n"
                        connection.send(content: notFound.data(using: .utf8), completion: .contentProcessed({ _ in
                            connection.cancel()
                        }))
                        return
                    }

                    do {
                        let code = try CloudMCPClient.parseOAuthCallback(request: req, expectedState: expectedState)
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
                    } catch {
                        let html = """
                        HTTP/1.1 400 Bad Request\r
                        Content-Type: text/html; charset=utf-8\r
                        Connection: close\r
                        \r
                        <!DOCTYPE html>
                        <html>
                        <head><title>SonosFlow Authorization Failed</title></head>
                        <body style="font-family: -apple-system, sans-serif; text-align: center; padding: 50px;">
                            <h2 style="color: #c62828;">SonosFlow: Authorization Failed</h2>
                            <p>Please return to SonosFlow and try signing in again.</p>
                        </body>
                        </html>
                        """
                        connection.send(content: html.data(using: .utf8), completion: .contentProcessed({ _ in
                            connection.cancel()
                        }))
                        Task { [weak self] in
                            await self?.fail(with: error)
                        }
                    }
                }
            }

            listener.stateUpdateHandler = { [weak self] state in
                if case .failed(let err) = state {
                    Task { [weak self] in
                        await self?.fail(with: err)
                    }
                }
            }

            listener.start(queue: .global())
        }
    }

    private func resumeWithCode(_ code: String) {
        timeoutTask?.cancel()
        timeoutTask = nil
        listener?.cancel()
        listener = nil
        codeContinuation?.resume(returning: code)
        codeContinuation = nil
    }

    private func fail(with error: Error) {
        timeoutTask?.cancel()
        timeoutTask = nil
        listener?.cancel()
        listener = nil
        codeContinuation?.resume(throwing: error)
        codeContinuation = nil
    }
}
