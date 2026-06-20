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
            return "Keychain 中的 Token 数据无效"
        }
    }
}

final class KeychainStore {
    let service: String
    let account: String

    private var didLoadToken = false
    private var cachedToken: String?

    init(service: String, account: String) {
        self.service = service
        self.account = account
    }

    func loadToken() -> String? {
        if didLoadToken {
            return cachedToken
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else {
            didLoadToken = true
            cachedToken = nil
            return nil
        }

        guard let data = result as? Data else {
            didLoadToken = true
            cachedToken = nil
            return nil
        }

        cachedToken = String(data: data, encoding: .utf8)
        didLoadToken = true
        return cachedToken
    }

    func saveToken(_ token: String) throws {
        let normalized = normalizedToken(token)
        guard let data = normalized.data(using: .utf8) else {
            throw KeychainStoreError.invalidData
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let updateAttributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)
        if updateStatus == errSecSuccess {
            didLoadToken = true
            cachedToken = normalized
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

        didLoadToken = true
        cachedToken = normalized
    }

    func deleteToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        SecItemDelete(query as CFDictionary)

        didLoadToken = true
        cachedToken = nil
    }

    private func normalizedToken(_ token: String) -> String {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("bearer ") {
            return String(trimmed.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }
}
