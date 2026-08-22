import Foundation
import Security

enum ClerkKeychainMigration {
    static let legacyService = "cloud.cyberverse.AsterionMac.clerk"
    static let currentService = "cloud.cyberverse.Asterion.clerk"

    private static let deviceTokenAccount = "clerkDeviceToken"
    private static let clerkAccounts = [
        "cachedClient",
        "cachedClientServerDate",
        "cachedEnvironment",
        "watchSyncAuthState",
        "watchSyncAuthVersion",
        deviceTokenAccount,
        "watchSyncDeviceTokenState",
        "watchSyncDeviceTokenVersion",
        "clerkDeviceTokenSynced",
        "AttestKeyId",
        "pendingMagicLinkFlow",
    ]

    static func migrateLegacySessionIfNeeded() {
        migrateMissingItems(from: legacyService, to: currentService)
    }

    static func migrateMissingItems(from legacyService: String, to currentService: String) {
        let hasLegacySession = data(service: legacyService, account: "cachedClient") != nil
            || data(service: legacyService, account: deviceTokenAccount) != nil
        guard hasLegacySession else { return }

        for account in clerkAccounts where data(service: currentService, account: account) == nil {
            guard let legacyData = data(service: legacyService, account: account) else { continue }
            add(legacyData, service: currentService, account: account)
        }
    }

    static func data(service: String, account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else {
            return nil
        }
        return result as? Data
    }

    static func add(_ data: Data, service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else { return }
    }

    static func deleteItems(service: String) {
        for account in clerkAccounts {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ]
            SecItemDelete(query as CFDictionary)
        }
    }
}
