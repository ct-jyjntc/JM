import Foundation
import Security

protocol UserSessionPersistence: Sendable {
    func load() throws -> PersistedUserSession?
    func save(_ session: PersistedUserSession) throws
    func delete() throws
}

struct KeychainUserSessionPersistence: UserSessionPersistence {
    private let service: String
    private let account: String

    init(service: String = Bundle.main.bundleIdentifier.map { "\($0).user-session" } ?? "com.luna.JMBoomMac.user-session",
         account: String = "current") {
        self.service = service
        self.account = account
    }

    func load() throws -> PersistedUserSession? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainSessionError(status: status)
        }
        guard let data = item as? Data else {
            throw KeychainSessionError(message: "Keychain 返回的登录数据格式不正确。")
        }

        return try JSONDecoder().decode(PersistedUserSession.self, from: data)
    }

    func save(_ session: PersistedUserSession) throws {
        let data = try JSONEncoder().encode(session)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        var addQuery = baseQuery
        attributes.forEach { addQuery[$0.key] = $0.value }

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw KeychainSessionError(status: updateStatus)
            }
            return
        }

        guard status == errSecSuccess else {
            throw KeychainSessionError(status: status)
        }
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainSessionError(status: status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

struct KeychainSessionError: LocalizedError {
    let message: String

    init(status: OSStatus) {
        message = SecCopyErrorMessageString(status, nil) as String? ?? "Keychain 错误 \(status)。"
    }

    init(message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}
