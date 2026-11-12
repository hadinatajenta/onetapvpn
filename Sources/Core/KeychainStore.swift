import Foundation
import Security

final class KeychainStore: CredentialsStoring {
    private let service = "com.erendt.onetapvpn"
    private let account = "credentials"
    private let label = "OneTapVPN credentials"

    func loadCredentials() throws -> Credentials? {
        if let credentials = try load(isDataProtection: true) {
            return credentials
        }
        return try load(isDataProtection: false)
    }

    private func load(isDataProtection: Bool) throws -> Credentials? {
        var query = baseQuery(isDataProtection: isDataProtection)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var queryResult: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &queryResult)
        if status == errSecItemNotFound {
            return nil
        }
        if isDataProtection && (status == errSecMissingEntitlement || status == errSecParam) {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
        guard let storedData = queryResult as? Data else {
            throw KeychainError.invalidData
        }
        do {
            return try JSONDecoder().decode(Credentials.self, from: storedData)
        } catch {
            throw KeychainError.invalidData
        }
    }

    func saveCredentials(_ credentials: Credentials) throws {
        let encodedCredentials = try JSONEncoder().encode(credentials)
        do {
            try save(encodedCredentials, isDataProtection: true)
            try? delete(isDataProtection: false)
        } catch KeychainError.unexpectedStatus(let status)
            where status == errSecMissingEntitlement || status == errSecParam {
            try save(encodedCredentials, isDataProtection: false)
            try? delete(isDataProtection: true)
        }
    }

    private func save(_ encodedCredentials: Data, isDataProtection: Bool) throws {
        let query = baseQuery(isDataProtection: isDataProtection)
        var updatedAttributes: [String: Any] = [
            kSecValueData as String: encodedCredentials,
            kSecAttrLabel as String: label
        ]
        if isDataProtection {
            updatedAttributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        }

        let updateStatus = SecItemUpdate(query as CFDictionary, updatedAttributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(updateStatus)
        }

        var addQuery = query
        addQuery[kSecValueData as String] = encodedCredentials
        addQuery[kSecAttrLabel as String] = label
        if isDataProtection {
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        }

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus == errSecDuplicateItem {
            let retryStatus = SecItemUpdate(query as CFDictionary, updatedAttributes as CFDictionary)
            guard retryStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(retryStatus)
            }
            return
        }
        guard addStatus == errSecSuccess else {
            throw KeychainError.unexpectedStatus(addStatus)
        }
    }

    func deleteCredentials() throws {
        var firstError: Error?
        for isDataProtection in [true, false] {
            do {
                try delete(isDataProtection: isDataProtection)
            } catch {
                if firstError == nil {
                    firstError = error
                }
            }
        }
        if let firstError {
            throw firstError
        }
    }

    private func delete(isDataProtection: Bool) throws {
        let status = SecItemDelete(baseQuery(isDataProtection: isDataProtection) as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound {
            return
        }
        if isDataProtection && (status == errSecMissingEntitlement || status == errSecParam) {
            return
        }
        throw KeychainError.unexpectedStatus(status)
    }

    private func baseQuery(isDataProtection: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false
        ]
        if isDataProtection {
            query[kSecUseDataProtectionKeychain as String] = true
        }
        return query
    }
}
