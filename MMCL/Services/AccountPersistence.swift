import Foundation
import Security

struct AccountCredentials: Equatable {
    let accessToken: String
    let refreshToken: String

    var isEmpty: Bool {
        accessToken.isEmpty && refreshToken.isEmpty
    }
}

protocol AccountCredentialStoring {
    func credentials(for accountID: UUID) throws -> AccountCredentials?
    func save(_ credentials: AccountCredentials, for accountID: UUID) throws
    func deleteCredentials(for accountID: UUID) throws
}

enum AccountCredentialStoreError: LocalizedError, Equatable {
    case unexpectedStatus(operation: String, status: OSStatus)
    case invalidStoredData

    var errorDescription: String? {
        switch self {
        case let .unexpectedStatus(operation, status):
            return "Keychain \(operation) failed with status \(status)."
        case .invalidStoredData:
            return "Keychain returned invalid account credential data."
        }
    }
}

struct KeychainAccountCredentialStore: AccountCredentialStoring {
    static let defaultService = "melody.MMCL.account-tokens"

    let service: String

    init(service: String = KeychainAccountCredentialStore.defaultService) {
        self.service = service
    }

    func credentials(for accountID: UUID) throws -> AccountCredentials? {
        let accessToken = try read(.accessToken, for: accountID)
        let refreshToken = try read(.refreshToken, for: accountID)

        guard accessToken != nil || refreshToken != nil else { return nil }
        return AccountCredentials(
            accessToken: accessToken ?? "",
            refreshToken: refreshToken ?? ""
        )
    }

    func save(_ credentials: AccountCredentials, for accountID: UUID) throws {
        try write(credentials.accessToken, kind: .accessToken, for: accountID)
        try write(credentials.refreshToken, kind: .refreshToken, for: accountID)
    }

    func deleteCredentials(for accountID: UUID) throws {
        for kind in TokenKind.allCases {
            let status = SecItemDelete(query(for: accountID, kind: kind) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw AccountCredentialStoreError.unexpectedStatus(
                    operation: "deleting \(kind.rawValue)",
                    status: status
                )
            }
        }
    }

    private enum TokenKind: String, CaseIterable {
        case accessToken
        case refreshToken
    }

    private func read(_ kind: TokenKind, for accountID: UUID) throws -> String? {
        var itemQuery = query(for: accountID, kind: kind)
        itemQuery[kSecReturnData as String] = true
        itemQuery[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(itemQuery as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw AccountCredentialStoreError.unexpectedStatus(
                operation: "reading \(kind.rawValue)",
                status: status
            )
        }
        guard let data = result as? Data else {
            throw AccountCredentialStoreError.invalidStoredData
        }
        guard let token = String(data: data, encoding: .utf8) else {
            throw AccountCredentialStoreError.invalidStoredData
        }
        return token
    }

    private func write(_ value: String, kind: TokenKind, for accountID: UUID) throws {
        if value.isEmpty {
            let status = SecItemDelete(query(for: accountID, kind: kind) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw AccountCredentialStoreError.unexpectedStatus(
                    operation: "deleting empty \(kind.rawValue)",
                    status: status
                )
            }
            return
        }

        let updateAttributes: [String: Any] = [
            kSecValueData as String: Data(value.utf8)
        ]
        let itemQuery = query(for: accountID, kind: kind)
        let updateStatus = SecItemUpdate(
            itemQuery as CFDictionary,
            updateAttributes as CFDictionary
        )

        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw AccountCredentialStoreError.unexpectedStatus(
                operation: "updating \(kind.rawValue)",
                status: updateStatus
            )
        }

        var addQuery = itemQuery
        addQuery[kSecValueData as String] = Data(value.utf8)
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw AccountCredentialStoreError.unexpectedStatus(
                operation: "saving \(kind.rawValue)",
                status: addStatus
            )
        }
    }

    private func query(for accountID: UUID, kind: TokenKind) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "\(accountID.uuidString).\(kind.rawValue)"
        ]
    }
}

struct AccountPersistence {
    let fileURL: URL
    let credentialStore: AccountCredentialStoring

    init(
        fileURL: URL? = nil,
        credentialStore: AccountCredentialStoring = KeychainAccountCredentialStore()
    ) {
        self.fileURL = fileURL ?? Self.defaultFileURL
        self.credentialStore = credentialStore
    }

    func loadAccounts() -> [MinecraftAccount] {
        guard let data = try? Data(contentsOf: fileURL),
              let records = try? JSONDecoder.mmcl.decode([PersistedMinecraftAccount].self, from: data) else {
            return []
        }

        var accounts: [MinecraftAccount] = []
        var needsRewrite = false
        var migrationSucceeded = true

        for record in records {
            var account = record.account
            var storedCredentials: AccountCredentials?

            do {
                storedCredentials = try credentialStore.credentials(for: account.id)
            } catch {
                // A legacy record still gives us a chance to preserve the session below.
            }

            if storedCredentials == nil, let legacyCredentials = record.legacyCredentials {
                do {
                    try credentialStore.save(legacyCredentials, for: account.id)
                    storedCredentials = legacyCredentials
                } catch {
                    // Keep the legacy token in memory and leave the file untouched so the
                    // user can retry migration without having to log in again.
                    migrationSucceeded = false
                }
            }

            if let storedCredentials {
                account.accessToken = storedCredentials.accessToken
                account.refreshToken = storedCredentials.refreshToken
            }
            accounts.append(account)

            if record.hasLegacyCredentialFields {
                needsRewrite = true
            }
        }

        if needsRewrite && migrationSucceeded {
            try? writeMetadata(accounts)
        }

        return accounts
    }

    func saveAccounts(_ accounts: [MinecraftAccount]) throws {
        for account in accounts {
            let credentials = AccountCredentials(
                accessToken: account.accessToken,
                refreshToken: account.refreshToken
            )
            if credentials.isEmpty {
                try credentialStore.deleteCredentials(for: account.id)
            } else {
                try credentialStore.save(credentials, for: account.id)
            }
        }

        try writeMetadata(accounts)
    }

    func deleteCredentials(for accountID: UUID) throws {
        try credentialStore.deleteCredentials(for: accountID)
    }

    private func writeMetadata(_ accounts: [MinecraftAccount]) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let records = accounts.map { PersistedMinecraftAccount(account: $0) }
        let data = try JSONEncoder.mmcl.encode(records)
        try data.write(to: fileURL, options: .atomic)
    }

    private static var defaultFileURL: URL {
        let applicationSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser

        return applicationSupportURL
            .appendingPathComponent("MMCL", isDirectory: true)
            .appendingPathComponent("accounts.json")
    }
}

private struct PersistedMinecraftAccount: Codable {
    let id: UUID
    let username: String
    let uuid: String
    let xuid: String
    let expiresAt: Date
    let type: MinecraftAccount.AccountType
    let appliedSkin: SkinInfo?

    // These are decoded only to migrate the pre-Keychain format. They are never encoded.
    let accessToken: String?
    let refreshToken: String?
    let hasLegacyCredentialFields: Bool

    private enum CodingKeys: String, CodingKey {
        case id
        case username
        case uuid
        case xuid
        case accessToken
        case refreshToken
        case expiresAt
        case type
        case appliedSkin
    }

    init(account: MinecraftAccount) {
        id = account.id
        username = account.username
        uuid = account.uuid
        xuid = account.xuid
        expiresAt = account.expiresAt
        type = account.type
        appliedSkin = account.appliedSkin
        accessToken = nil
        refreshToken = nil
        hasLegacyCredentialFields = false
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        username = try container.decode(String.self, forKey: .username)
        uuid = try container.decodeIfPresent(String.self, forKey: .uuid) ?? ""
        xuid = try container.decodeIfPresent(String.self, forKey: .xuid) ?? ""
        accessToken = try container.decodeIfPresent(String.self, forKey: .accessToken)
        refreshToken = try container.decodeIfPresent(String.self, forKey: .refreshToken)
        expiresAt = try container.decodeIfPresent(Date.self, forKey: .expiresAt) ?? Date()
        type = try container.decodeIfPresent(MinecraftAccount.AccountType.self, forKey: .type) ?? .offline
        appliedSkin = try container.decodeIfPresent(SkinInfo.self, forKey: .appliedSkin)
        hasLegacyCredentialFields = container.contains(.accessToken) || container.contains(.refreshToken)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(username, forKey: .username)
        try container.encode(uuid, forKey: .uuid)
        try container.encode(xuid, forKey: .xuid)
        try container.encode(expiresAt, forKey: .expiresAt)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(appliedSkin, forKey: .appliedSkin)
    }

    var account: MinecraftAccount {
        MinecraftAccount(
            id: id,
            username: username,
            uuid: uuid,
            xuid: xuid,
            accessToken: accessToken ?? "",
            refreshToken: refreshToken ?? "",
            expiresAt: expiresAt,
            type: type,
            appliedSkin: appliedSkin
        )
    }

    var legacyCredentials: AccountCredentials? {
        let credentials = AccountCredentials(
            accessToken: accessToken ?? "",
            refreshToken: refreshToken ?? ""
        )
        return credentials.isEmpty ? nil : credentials
    }
}
