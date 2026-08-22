import Foundation
import Testing
@testable import AsterionMac

struct ClerkKeychainMigrationTests {
    @Test func copiesMissingCachedClientEvenWhenCurrentServiceHasADeviceToken() {
        let legacyService = "cloud.cyberverse.Asterion.test.legacy.\(UUID().uuidString)"
        let currentService = "cloud.cyberverse.Asterion.test.current.\(UUID().uuidString)"
        defer {
            ClerkKeychainMigration.deleteItems(service: legacyService)
            ClerkKeychainMigration.deleteItems(service: currentService)
        }

        let cachedClient = Data("legacy-client".utf8)
        let legacyToken = Data("legacy-token".utf8)
        let currentToken = Data("current-token".utf8)

        ClerkKeychainMigration.add(cachedClient, service: legacyService, account: "cachedClient")
        ClerkKeychainMigration.add(legacyToken, service: legacyService, account: "clerkDeviceToken")
        ClerkKeychainMigration.add(currentToken, service: currentService, account: "clerkDeviceToken")

        ClerkKeychainMigration.migrateMissingItems(from: legacyService, to: currentService)

        #expect(ClerkKeychainMigration.data(service: currentService, account: "cachedClient") == cachedClient)
        #expect(ClerkKeychainMigration.data(service: currentService, account: "clerkDeviceToken") == currentToken)
    }

    @Test func doesNotOverwriteAnExistingCachedClient() {
        let legacyService = "cloud.cyberverse.Asterion.test.legacy.\(UUID().uuidString)"
        let currentService = "cloud.cyberverse.Asterion.test.current.\(UUID().uuidString)"
        defer {
            ClerkKeychainMigration.deleteItems(service: legacyService)
            ClerkKeychainMigration.deleteItems(service: currentService)
        }

        ClerkKeychainMigration.add(Data("legacy-client".utf8), service: legacyService, account: "cachedClient")
        ClerkKeychainMigration.add(Data("current-client".utf8), service: currentService, account: "cachedClient")

        ClerkKeychainMigration.migrateMissingItems(from: legacyService, to: currentService)

        #expect(
            ClerkKeychainMigration.data(service: currentService, account: "cachedClient")
                == Data("current-client".utf8)
        )
    }
}
