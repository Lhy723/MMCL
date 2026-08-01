import XCTest
@testable import MMCL

final class AccountPersistenceTests: XCTestCase {
    func testKeychainCredentialStoreRoundTripsAndDeletesTokens() throws {
        let accountID = UUID()
        let store = KeychainAccountCredentialStore(
            service: "melody.MMCL.tests.\(UUID().uuidString)"
        )
        let credentials = AccountCredentials(
            accessToken: "keychain-access-token",
            refreshToken: "keychain-refresh-token"
        )
        defer { try? store.deleteCredentials(for: accountID) }

        try store.save(credentials, for: accountID)
        XCTAssertEqual(try store.credentials(for: accountID), credentials)

        try store.deleteCredentials(for: accountID)
        XCTAssertNil(try store.credentials(for: accountID))
    }

    func testMinecraftAccountEncodingExcludesAuthenticationTokens() throws {
        let account = MinecraftAccount(
            username: "Steve",
            uuid: "minecraft-uuid",
            accessToken: "access-token-secret",
            refreshToken: "refresh-token-secret",
            type: .microsoft
        )

        let data = try JSONEncoder.mmcl.encode(account)
        let json = String(decoding: data, as: UTF8.self)

        XCTAssertFalse(json.contains("accessToken"))
        XCTAssertFalse(json.contains("refreshToken"))
        XCTAssertFalse(json.contains("access-token-secret"))
        XCTAssertFalse(json.contains("refresh-token-secret"))
    }

    func testSavingAccountsKeepsTokensOutOfJSONAndLoadsThemFromKeychainStore() throws {
        let fileURL = temporaryAccountsURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let credentialStore = InMemoryAccountCredentialStore()
        let persistence = AccountPersistence(
            fileURL: fileURL,
            credentialStore: credentialStore
        )
        let account = MinecraftAccount(
            username: "Steve",
            uuid: "minecraft-uuid",
            accessToken: "access-token-secret",
            refreshToken: "refresh-token-secret",
            expiresAt: Date(timeIntervalSince1970: 1_700_000_000),
            type: .microsoft
        )

        try persistence.saveAccounts([account])

        let json = String(decoding: try Data(contentsOf: fileURL), as: UTF8.self)
        XCTAssertFalse(json.contains("accessToken"))
        XCTAssertFalse(json.contains("refreshToken"))
        XCTAssertFalse(json.contains("access-token-secret"))
        XCTAssertFalse(json.contains("refresh-token-secret"))
        XCTAssertEqual(
            try credentialStore.credentials(for: account.id),
            AccountCredentials(accessToken: "access-token-secret", refreshToken: "refresh-token-secret")
        )

        let loaded = persistence.loadAccounts()
        XCTAssertEqual(loaded.first?.accessToken, "access-token-secret")
        XCTAssertEqual(loaded.first?.refreshToken, "refresh-token-secret")
    }

    func testLegacyAccountsMigrateTokensAndRewriteMetadataOnly() throws {
        let fileURL = temporaryAccountsURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let accountID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let legacyJSON = """
        [{
          "id": "\(accountID.uuidString)",
          "username": "Legacy",
          "uuid": "legacy-minecraft-uuid",
          "accessToken": "legacy-access-token",
          "refreshToken": "legacy-refresh-token",
          "expiresAt": "2026-08-01T00:00:00Z",
          "type": "microsoft"
        }]
        """
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(legacyJSON.utf8).write(to: fileURL)

        let credentialStore = InMemoryAccountCredentialStore()
        let persistence = AccountPersistence(
            fileURL: fileURL,
            credentialStore: credentialStore
        )

        do {
            _ = try JSONDecoder.mmcl.decode(
                [MinecraftAccount].self,
                from: Data(contentsOf: fileURL)
            )
        } catch {
            XCTFail("Legacy JSON should be decodable: \(error)")
        }

        let loaded = persistence.loadAccounts()

        XCTAssertEqual(loaded.first?.id, accountID)
        XCTAssertEqual(loaded.first?.accessToken, "legacy-access-token")
        XCTAssertEqual(loaded.first?.refreshToken, "legacy-refresh-token")
        XCTAssertEqual(
            try credentialStore.credentials(for: accountID),
            AccountCredentials(accessToken: "legacy-access-token", refreshToken: "legacy-refresh-token")
        )

        let migratedJSON = String(decoding: try Data(contentsOf: fileURL), as: UTF8.self)
        XCTAssertFalse(migratedJSON.contains("accessToken"))
        XCTAssertFalse(migratedJSON.contains("refreshToken"))
        XCTAssertFalse(migratedJSON.contains("legacy-access-token"))
        XCTAssertFalse(migratedJSON.contains("legacy-refresh-token"))

        let reloaded = persistence.loadAccounts()
        XCTAssertEqual(reloaded.first?.accessToken, "legacy-access-token")
        XCTAssertEqual(reloaded.first?.refreshToken, "legacy-refresh-token")
    }

    @MainActor
    func testDeletingAccountRemovesKeychainCredentials() throws {
        let fileURL = temporaryAccountsURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let credentialStore = InMemoryAccountCredentialStore()
        let persistence = AccountPersistence(
            fileURL: fileURL,
            credentialStore: credentialStore
        )
        let account = MinecraftAccount(
            username: "Delete me",
            uuid: "delete-me-uuid",
            accessToken: "access-token-secret",
            refreshToken: "refresh-token-secret",
            type: .microsoft
        )
        try persistence.saveAccounts([account])

        let store = LauncherStore(
            instances: [],
            downloadJobs: [],
            featuredProjects: [],
            diagnostics: [],
            javaRuntimes: [],
            availableVersions: [],
            accountPersistence: persistence
        )
        guard let loadedAccount = store.accounts.first else {
            return XCTFail("Expected the persisted account to load")
        }
        XCTAssertEqual(loadedAccount.id, account.id)

        store.deleteAccount(loadedAccount)

        XCTAssertTrue(store.accounts.isEmpty)
        XCTAssertNil(try credentialStore.credentials(for: account.id))
    }

    private func temporaryAccountsURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("MMCL-accounts-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("accounts.json")
    }
}

private final class InMemoryAccountCredentialStore: AccountCredentialStoring {
    private var storedCredentials: [UUID: AccountCredentials] = [:]

    func credentials(for accountID: UUID) throws -> AccountCredentials? {
        storedCredentials[accountID]
    }

    func save(_ credentials: AccountCredentials, for accountID: UUID) throws {
        storedCredentials[accountID] = credentials
    }

    func deleteCredentials(for accountID: UUID) throws {
        storedCredentials.removeValue(forKey: accountID)
    }
}
