import Foundation
import Security
import LocalAuthentication
import SQLite3
import CommonCrypto
import CryptoKit

struct ClaudeSession: Sendable {
    let key: String
    let organization: String
    let fingerprint: String
}

enum ClaudeDesktopSession {
    private struct Cookie {
        let host: String; let value: String; let encrypted: Data; let expires: Int64
    }
    private static func cookies(at path: String) throws -> (Int, [String: Cookie]) {
        var database: OpaquePointer?
        guard sqlite3_open_v2(path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let database else {
            if let database { sqlite3_close(database) }; throw ClaudeUsageError.desktopMissing
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 500)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT value FROM meta WHERE key='version'", -1, &statement, nil) == SQLITE_OK else { throw ClaudeUsageError.desktopMissing }
        let version = sqlite3_step(statement) == SQLITE_ROW ? Int(sqlite3_column_int(statement, 0)) : 0
        sqlite3_finalize(statement); statement = nil
        // Read only the active organization and its session. Never copy the cookie database.
        let sql = "SELECT name,host_key,value,encrypted_value,expires_utc FROM cookies WHERE host_key IN ('claude.ai','.claude.ai') AND name IN ('sessionKey','lastActiveOrg') ORDER BY last_update_utc DESC"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { throw ClaudeUsageError.desktopMissing }
        defer { sqlite3_finalize(statement) }
        var result: [String: Cookie] = [:]
        var step = sqlite3_step(statement)
        while step == SQLITE_ROW {
            func string(_ column: Int32) -> String { sqlite3_column_text(statement, column).map { String(cString: $0) } ?? "" }
            let name = string(0)
            if result[name] != nil { step = sqlite3_step(statement); continue }
            let size = Int(sqlite3_column_bytes(statement, 3))
            guard size <= 4096 else { throw ClaudeUsageError.desktopMissing }
            let encrypted = sqlite3_column_blob(statement, 3).map { Data(bytes: $0, count: size) } ?? Data()
            result[name] = Cookie(host: string(1), value: string(2), encrypted: encrypted, expires: sqlite3_column_int64(statement, 4))
            step = sqlite3_step(statement)
        }
        guard step == SQLITE_DONE else { throw ClaudeUsageError.desktopMissing }
        return (version, result)
    }
    static func read(allowPrompt: Bool = false) throws -> ClaudeSession {
        let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Claude/Cookies").path
        let (version, cookies) = try cookies(at: path)
        guard let session = cookies["sessionKey"], let org = cookies["lastActiveOrg"] else { throw ClaudeUsageError.desktopMissing }
        let chromeNow = Int64((Date().timeIntervalSince1970 + 11_644_473_600) * 1_000_000)
        guard session.expires == 0 || session.expires > chromeNow else { throw ClaudeUsageError.expired }
        var password = Data()
        if !session.encrypted.isEmpty || !org.encrypted.isEmpty {
            var item: CFTypeRef?
            let context = LAContext(); context.interactionNotAllowed = !allowPrompt
            let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                       kSecAttrService as String: "Claude Safe Storage",
                                       kSecReturnData as String: true,
                                       kSecMatchLimit as String: kSecMatchLimitOne,
                                       kSecUseAuthenticationContext as String: context]
            guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let value = item as? Data else { throw ClaudeUsageError.keychain }
            password = value
        }
        defer { password.resetBytes(in: 0..<password.count) }
        func value(_ cookie: Cookie) throws -> String {
            if !cookie.value.isEmpty { return cookie.value }
            return try decodeCookie(cookie.encrypted, password: password, host: cookie.host, version: version)
        }
        let key = try value(session); let organization = try value(org)
        _ = try ClaudeUsageRequest.make(sessionKey: key, organization: organization)
        let fingerprint = SHA256.hash(data: Data((key + ":" + organization.lowercased()).utf8)).map { String(format: "%02x", $0) }.joined()
        return .init(key: key, organization: organization.lowercased(), fingerprint: fingerprint)
    }
    static func decodeCookie(_ blob: Data, password: Data, host: String, version: Int) throws -> String {
        guard blob.starts(with: Data("v10".utf8)), blob.count > 3, (blob.count - 3).isMultiple(of: 16) else { throw ClaudeUsageError.desktopMissing }
        let salt = Array("saltysalt".utf8); var key = [UInt8](repeating: 0, count: 16)
        let derived = password.withUnsafeBytes { bytes in
            CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), bytes.bindMemory(to: Int8.self).baseAddress, password.count,
                                salt, salt.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), 1003, &key, key.count)
        }
        guard derived == kCCSuccess else { throw ClaudeUsageError.desktopMissing }
        defer { _ = key.withUnsafeMutableBytes { $0.initializeMemory(as: UInt8.self, repeating: 0) } }
        let cipher = blob.dropFirst(3); let iv = [UInt8](repeating: 32, count: 16)
        var clear = Data(count: cipher.count + 16); var length = 0
        let capacity = clear.count
        let status = clear.withUnsafeMutableBytes { output in
            cipher.withUnsafeBytes { input in
                CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding), key, key.count,
                        iv, input.baseAddress, cipher.count, output.baseAddress, capacity, &length)
            }
        }
        defer { clear.resetBytes(in: 0..<clear.count) }
        guard status == kCCSuccess else { throw ClaudeUsageError.desktopMissing }
        clear.count = length
        if version >= 24 {
            let expected = Data(SHA256.hash(data: Data(host.utf8)))
            guard clear.starts(with: expected) else { throw ClaudeUsageError.desktopMissing }
            clear.removeFirst(32)
        }
        guard let value = String(data: clear, encoding: .utf8) else { throw ClaudeUsageError.desktopMissing }
        return value
    }
}

enum ClaudeSessionStore {
    private static let service = "local.achu.companion.claude-session"
    static func read() throws -> ClaudeSession {
        var item: CFTypeRef?
        let context = LAContext(); context.interactionNotAllowed = true
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                   kSecReturnData as String: true, kSecUseAuthenticationContext as String: context]
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data,
              let fields = try? JSONDecoder().decode([String: String].self, from: data), let key = fields["session"], let org = fields["organization"] else { throw ClaudeUsageError.connection }
        _ = try ClaudeUsageRequest.make(sessionKey: key, organization: org)
        let fingerprint = SHA256.hash(data: Data((key + ":" + org.lowercased()).utf8)).map { String(format: "%02x", $0) }.joined()
        return .init(key: key, organization: org.lowercased(), fingerprint: fingerprint)
    }
    static func save(key: String, organization: String) throws {
        _ = try ClaudeUsageRequest.make(sessionKey: key, organization: organization)
        let data = try JSONEncoder().encode(["session": key, "organization": organization.lowercased()])
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "usage"]
        let updated = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updated == errSecSuccess { return }
        guard updated == errSecItemNotFound else { throw ClaudeUsageError.keychain }
        var attributes = query; attributes[kSecValueData as String] = data
        guard SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess else { throw ClaudeUsageError.keychain }
    }
    static func remove() { SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service] as CFDictionary) }
}
