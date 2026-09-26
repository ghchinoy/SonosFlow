import Foundation
import Security

public struct CloudToken: Codable, Sendable {
    public let accessToken: String
    public let refreshToken: String?
    public let expiresAt: Date
    public let clientID: String

    public init(accessToken: String, refreshToken: String?, expiresAt: Date, clientID: String) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.clientID = clientID
    }

    public var isValid: Bool {
        return expiresAt > Date().addingTimeInterval(60) // valid for at least 1 more minute
    }
}

public final class CloudTokenStorage: @unchecked Sendable {
    public static let shared = CloudTokenStorage()

    private let serviceKey = "com.ghchinoy.SonosFlow.cloudToken"
    private let accountKey = "SonosOfficialMCP"
    private let fallbackDefaultsKey = "sonosflow_cloud_token_fallback"

    public func loadToken() -> CloudToken? {
        // 1. Try Keychain
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceKey,
            kSecAttrAccount as String: accountKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data {
            if let token = try? JSONDecoder().decode(CloudToken.self, from: data) {
                return token
            }
        }

        // 2. Try UserDefaults fallback
        if let data = UserDefaults.standard.data(forKey: fallbackDefaultsKey),
           let token = try? JSONDecoder().decode(CloudToken.self, from: data) {
            return token
        }

        // 3. Try repo-local .official-token.json (if running during development/spikes)
        let localFile = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".official-token.json")
        if let data = try? Data(contentsOf: localFile),
           let token = try? JSONDecoder().decode(CloudToken.self, from: data) {
            // Persist to keychain for next time
            saveToken(token)
            return token
        }

        return nil
    }

    public func saveToken(_ token: CloudToken) {
        guard let data = try? JSONEncoder().encode(token) else { return }

        // Save to Keychain
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceKey,
            kSecAttrAccount as String: accountKey
        ]

        SecItemDelete(query as CFDictionary)

        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceKey,
            kSecAttrAccount as String: accountKey,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        SecItemAdd(attributes as CFDictionary, nil)

        // Also save to defaults as fallback for sandboxed tests
        UserDefaults.standard.set(data, forKey: fallbackDefaultsKey)
    }

    public func clearToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceKey,
            kSecAttrAccount as String: accountKey
        ]
        SecItemDelete(query as CFDictionary)
        UserDefaults.standard.removeObject(forKey: fallbackDefaultsKey)
    }
}
