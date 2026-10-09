import Foundation
import Security

// File-based Keychain ignores LAContext's per-query UI setting. All app-owned
// Security item operations share this gate; it never changes an ACL or a key.
enum KeychainAccessError: LocalizedError {
    case busy, unsafe, mainThreadPrompt
    var errorDescription: String? {
        switch self {
        case .busy: return "钥匙串正在处理另一项操作。原文和已保存信息保留，请稍后重试。"
        case .unsafe: return "无法确认钥匙串的无弹窗状态，已停止访问。请重启伴侣后重试，已保存信息保留。"
        case .mainThreadPrompt: return "系统授权必须在后台处理，请使用「测试连接」或「连接额度」。"
        }
    }
}
final class KeychainAccessGate: @unchecked Sendable {
    private let lock = NSLock()
    private var unsafe = false
    private let set: (Bool) -> OSStatus
    private let get: () -> Bool?
    init(set: @escaping (Bool) -> OSStatus, get: @escaping () -> Bool?) { self.set = set; self.get = get }
    func perform<T>(allowPrompt: Bool = false, _ operation: () throws -> T) throws -> T {
        guard lock.try() else { throw KeychainAccessError.busy }
        defer { lock.unlock() }
        guard !unsafe else { throw KeychainAccessError.unsafe }
        guard !allowPrompt || !Thread.isMainThread else { throw KeychainAccessError.mainThreadPrompt }
        guard set(false) == errSecSuccess, get() == false else { unsafe = true; throw KeychainAccessError.unsafe }
        if allowPrompt {
            guard set(true) == errSecSuccess, get() == true else { unsafe = true; _ = set(false); throw KeychainAccessError.unsafe }
        }
        let result = Result { try operation() }
        guard set(false) == errSecSuccess, get() == false else { unsafe = true; throw KeychainAccessError.unsafe }
        return try result.get()
    }
}
enum KeychainAccess {
    // Deliberate deprecated-API compatibility: existing items use the legacy
    // file-based keychain. LAContext alone was observed not to suppress its UI.
    static let shared = KeychainAccessGate(set: { SecKeychainSetUserInteractionAllowed($0) }, get: {
        var allowed: DarwinBoolean = true
        guard SecKeychainGetUserInteractionAllowed(&allowed) == errSecSuccess else { return nil }
        return allowed.boolValue
    })
    static func prepare() { _ = try? shared.perform {} }
    static func perform<T>(allowPrompt: Bool = false, _ operation: () throws -> T) throws -> T {
        try shared.perform(allowPrompt: allowPrompt, operation)
    }
}
