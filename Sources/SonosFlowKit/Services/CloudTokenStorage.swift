import Foundation
import Security

public struct CloudToken: Codable, Sendable, Equatable {
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

/// Thread-safe persistence abstraction for OAuth tokens.
public protocol CloudTokenStore: Sendable {
    func loadToken() -> CloudToken?
    func saveToken(_ token: CloudToken)
    func clearToken()
}

/// Keychain-backed production token store. Never mirrors tokens into plaintext UserDefaults or files.
public final class CloudTokenStorage: CloudTokenStore, @unchecked Sendable {
    public static let shared = CloudTokenStorage()

    private let serviceKey = "com.ghchinoy.SonosFlow.cloudToken"
    private let accountKey = "SonosOfficialMCP"
    private let legacyDefaultsKey = "sonosflow_cloud_token_fallback"

    public init() {
        // Purge any legacy plaintext token left in UserDefaults by earlier versions.
        UserDefaults.standard.removeObject(forKey: legacyDefaultsKey)
    }

    public func loadToken() -> CloudToken? {
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

        return nil
    }

    public func saveToken(_ token: CloudToken) {
        guard let data = try? JSONEncoder().encode(token) else { return }

        // Ensure legacy plaintext key is never present
        UserDefaults.standard.removeObject(forKey: legacyDefaultsKey)

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

        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        if addStatus != errSecSuccess {
            AppLogger.shared.warning("Keychain token save returned status \(addStatus)", category: "AUTH")
        }
    }

    public func clearToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceKey,
            kSecAttrAccount as String: accountKey
        ]
        SecItemDelete(query as CFDictionary)
        UserDefaults.standard.removeObject(forKey: legacyDefaultsKey)
    }
}

/// Isolated in-memory token store for unit tests (touches neither Keychain nor UserDefaults).
public final class InMemoryCloudTokenStore: CloudTokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var token: CloudToken?

    public init(token: CloudToken? = nil) {
        self.token = token
    }

    public func loadToken() -> CloudToken? {
        lock.lock()
        defer { lock.unlock() }
        return token
    }

    public func saveToken(_ token: CloudToken) {
        lock.lock()
        defer { lock.unlock() }
        self.token = token
    }

    public func clearToken() {
        lock.lock()
        defer { lock.unlock() }
        self.token = nil
    }
}
