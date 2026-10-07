import Foundation
import Security
import LocalAuthentication

enum CredentialPresence { case present, missing, unknown }

enum Credentials {
    private static func query(_ account: String) -> [String: Any] { [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "local.achu.companion",
        kSecAttrAccount as String: account
    ] }
    static func bindLegacyConfiguration(settings: UserDefaults = .standard) {
        guard settings.string(forKey: "legacyTranslationCredentialScope") == nil,
              let base = settings.string(forKey: "baseURL"), !base.isEmpty,
              let scope = try? TranslationProfile.scope(provider: .openAI, baseURL: base) else { return }
        settings.set(scope, forKey: "legacyTranslationCredentialScope")
    }
    static func presence(provider: RemoteTranslationProvider, baseURL: String, settings: UserDefaults = CompanionPreferences.store,
                         lookup: (String) -> CredentialPresence = presenceAccount) -> CredentialPresence {
        guard let scope = try? TranslationProfile.scope(provider:provider,baseURL:baseURL) else { return .unknown }
        let result = lookup(scope)
        guard result == .missing, provider == .openAI, settings.string(forKey:"legacyTranslationCredentialScope") == scope else { return result }
        return lookup(provider.credentialAccount)
    }
    private static func presenceAccount(_ account: String) -> CredentialPresence {
        guard !CompanionPreferences.simulated else { return .unknown }
        var request = query(account)
        request[kSecReturnAttributes as String] = true
        request[kSecReturnData as String] = false
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        let context = LAContext(); context.interactionNotAllowed = true
        request[kSecUseAuthenticationContext as String] = context
        var attributes: CFTypeRef?
        guard context.interactionNotAllowed, let status = try? KeychainAccess.perform({ SecItemCopyMatching(request as CFDictionary, &attributes) }) else { return .unknown }
        switch status {
        case errSecSuccess: return .present
        case errSecItemNotFound: return .missing
        default: return .unknown // Locked/permission-limited is not a missing key.
        }
    }
    static func read(for provider: RemoteTranslationProvider = .openAI, baseURL: String = "", allowPrompt: Bool = false) throws -> String {
        guard !CompanionPreferences.simulated else { throw BridgeError.message("本机模拟不读取真实钥匙串。") }
        let scope = try TranslationProfile.scope(provider: provider, baseURL: baseURL)
        return try readBoundCredential(provider: provider, scope: scope, settings: .standard,
                                 read: { try readAccount($0, allowPrompt: allowPrompt) })
    }
    static func readAsync(for provider: RemoteTranslationProvider, baseURL: String, allowPrompt: Bool = false) async throws -> String {
        try await offMainRead { try read(for: provider, baseURL: baseURL, allowPrompt: allowPrompt) }
    }
    static func offMainRead<Value: Sendable>(busyRetryLimit: Int = 20, retryDelay: Duration = .milliseconds(100),
                            _ operation: @escaping @Sendable () throws -> Value) async throws -> Value {
        var retries = 0
        let limit = min(20, max(0, busyRetryLimit))
        while true {
            try Task.checkCancellation()
            do {
                let value = try await Task.detached(priority: .utility, operation: operation).value
                try Task.checkCancellation()
                return value
            } catch KeychainAccessError.busy {
                guard retries < limit else { throw KeychainAccessError.busy }
                retries += 1
                // The shared gate still fails immediately. Only read callers
                // yield briefly for a competing quota query; no worker waits
                // for the lock, no authentication error or HTTP call retries.
                try await Task.sleep(for: retryDelay)
            }
        }
    }
    static func readBoundCredential(provider: RemoteTranslationProvider, scope: String, settings: UserDefaults,
                              read: (String) throws -> String) throws -> String {
        let scoped = try read(scope)
        if !scoped.isEmpty || provider == .gemini { return scoped }
        guard settings.string(forKey: "legacyTranslationCredentialScope") == scope else { return "" }
        let legacy = try read(provider.credentialAccount)
        // The historical scope still binds this fallback; reading never migrates data.
        return legacy
    }
    static func readRequest(account: String, allowPrompt: Bool) -> [String: Any] {
        var request = query(account)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        let context = LAContext(); context.interactionNotAllowed = !allowPrompt
        request[kSecUseAuthenticationContext as String] = context
        return request
    }
    private static func readAccount(_ account: String, allowPrompt: Bool) throws -> String {
        let request = readRequest(account: account, allowPrompt: allowPrompt)
        var result: CFTypeRef?
        guard allowPrompt || (request[kSecUseAuthenticationContext as String] as? LAContext)?.interactionNotAllowed == true else { throw KeychainAccessError.unsafe }
        let status = try KeychainAccess.perform(allowPrompt: allowPrompt) { SecItemCopyMatching(request as CFDictionary, &result) }
        if status == errSecItemNotFound { return "" }
        if status == errSecInteractionNotAllowed || status == errSecAuthFailed {
            throw BridgeError.message("钥匙串暂不可用或需要确认访问权限。请解锁 Mac，并在翻译设置中点击「测试连接」统一确认；原文和已保存的密钥均保留。")
        }
        guard status == errSecSuccess, let data = result as? Data, let key = String(data: data, encoding: .utf8) else {
            throw BridgeError.message("无法读取钥匙串中的 API 密钥，请在设置中重新保存。")
        }
        return key
    }
    static func saveAsync(_ key: String, for provider: RemoteTranslationProvider, baseURL: String) async throws {
        _ = try await offMainRead(busyRetryLimit: 0) { try save(key, for: provider, baseURL: baseURL); return "" }
    }
    static func save(_ key: String, for provider: RemoteTranslationProvider = .openAI, baseURL: String = "") throws {
        guard !CompanionPreferences.simulated else { throw BridgeError.message("本机模拟不修改真实钥匙串。") }
        let scope = try TranslationProfile.scope(provider: provider, baseURL: baseURL)
        try saveAccount(key, account: scope)
        if provider == .openAI && UserDefaults.standard.string(forKey: "legacyTranslationCredentialScope") == scope {
            UserDefaults.standard.removeObject(forKey: "legacyTranslationCredentialScope")
            try saveAccount("", account: provider.credentialAccount)
        }
    }
    private static func saveAccount(_ key: String, account: String) throws {
        try KeychainAccess.perform { try saveAccountUnlocked(key, account: account) }
    }
    private static func saveAccountUnlocked(_ key: String, account: String) throws {
        let query = query(account)
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
