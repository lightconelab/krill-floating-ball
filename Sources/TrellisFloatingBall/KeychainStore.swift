import Foundation
import Security

enum KeychainStoreError: LocalizedError {
    case unexpectedStatus(OSStatus)
    case invalidData

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            return "Keychain 操作失败，状态码：\(status)"
        case .invalidData:
            return "Keychain 中的登录凭据数据无效"
        }
    }
}

struct KrillCredentials: Codable, Equatable {
    let email: String
    let password: String
}

final class KeychainStore {
    private enum Accounts {
        static let credentials = "krill-login-credentials"
        static let legacyToken = "krill-api-token"
    }

    let service: String

    private var didLoadCredentials = false
    private var cachedCredentials: KrillCredentials?

    init(service: String) {
        self.service = service
    }

    func loadCredentials() -> KrillCredentials? {
        if didLoadCredentials {
            return cachedCredentials
        }

        defer {
            didLoadCredentials = true
        }

        guard let data = loadData(account: Accounts.credentials) else {
            cachedCredentials = nil
            return nil
        }

        guard let credentials = try? JSONDecoder().decode(KrillCredentials.self, from: data),
              isValid(credentials)
        else {
            cachedCredentials = nil
            return nil
        }

        cachedCredentials = credentials
        return credentials
    }

    func cachedCredentialsIfLoaded() -> KrillCredentials? {
        guard didLoadCredentials else {
            return nil
        }
        return cachedCredentials
    }

    func hasStoredCredentials() -> Bool {
        hasStoredData(account: Accounts.credentials)
    }

    func saveCredentials(_ credentials: KrillCredentials) throws {
        let normalized = KrillCredentials(
            email: credentials.email.trimmingCharacters(in: .whitespacesAndNewlines),
            password: credentials.password
        )
        guard isValid(normalized),
              let data = try? JSONEncoder().encode(normalized)
        else {
            throw KeychainStoreError.invalidData
        }

        try saveData(data, account: Accounts.credentials)
        deleteData(account: Accounts.legacyToken)

        didLoadCredentials = true
        cachedCredentials = normalized
    }

    func deleteCredentials() {
        deleteData(account: Accounts.credentials)
        deleteData(account: Accounts.legacyToken)

        didLoadCredentials = true
        cachedCredentials = nil
    }

    private func isValid(_ credentials: KrillCredentials) -> Bool {
        credentials.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            && credentials.password.isEmpty == false
    }

    private func loadData(account: String) -> Data? {
        var query = keychainQuery(account: account)
        query.merge([
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]) { _, new in new }

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else {
            return nil
        }

        return result as? Data
    }

    private func hasStoredData(account: String) -> Bool {
        var query = keychainQuery(account: account)
        query.merge([
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]) { _, new in new }

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return status == errSecSuccess
    }

    private func saveData(_ data: Data, account: String) throws {
        let query = keychainQuery(account: account)
        let updateAttributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }

        guard updateStatus == errSecItemNotFound else {
            throw KeychainStoreError.unexpectedStatus(updateStatus)
        }

        var addQuery = query
        addQuery.merge([
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData as String: data
        ]) { _, new in new }
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainStoreError.unexpectedStatus(addStatus)
        }
    }

    private func deleteData(account: String) {
        SecItemDelete(keychainQuery(account: account) as CFDictionary)
    }

    private func keychainQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
