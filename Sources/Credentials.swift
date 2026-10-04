import Foundation
import Security

enum Credentials {
    private static func query(_ provider: RemoteTranslationProvider) -> [String: Any] { [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "local.achu.companion",
        kSecAttrAccount as String: provider.credentialAccount
    ] }
    static func read(for provider: RemoteTranslationProvider = .openAI) throws -> String {
        var request = query(provider)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess, let data = result as? Data, let key = String(data: data, encoding: .utf8) else {
            throw BridgeError.message("无法读取钥匙串中的 API 密钥，请在设置中重新保存。")
        }
        return key
    }
    static func save(_ key: String, for provider: RemoteTranslationProvider = .openAI) throws {
        let query = query(provider)
        if key.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw BridgeError.message("无法删除钥匙串密钥。") }
            return
        }
        let attributes = [kSecValueData as String: Data(key.utf8)]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item.merge(attributes) { _, new in new }
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw BridgeError.message("无法保存 API 密钥到钥匙串。") }
        } else if status != errSecSuccess { throw BridgeError.message("无法更新钥匙串中的 API 密钥。") }
    }
}
