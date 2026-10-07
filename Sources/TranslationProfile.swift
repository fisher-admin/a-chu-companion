import Foundation
import CryptoKit

enum TranslationProfile {
    static func scope(provider: RemoteTranslationProvider, baseURL: String) throws -> String {
        if provider == .gemini { return provider.credentialAccount }
        let url = try AIProtocol.endpoint(baseURL)
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { throw BridgeError.message("接口地址无效。") }
        parts.scheme = parts.scheme?.lowercased(); parts.host = parts.host?.lowercased()
        if (parts.scheme == "https" && parts.port == 443) || (parts.scheme == "http" && parts.port == 80) { parts.port = nil }
        let canonical = parts.string ?? url.absoluteString
        return "translation-profile-" + SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

enum TranslationPreset: String, CaseIterable, Identifiable {
    case custom, openAI, grok
    var id: String { rawValue }
    var name: String { switch self { case .custom: return "自定义"; case .openAI: return "OpenAI"; case .grok: return "Grok" } }
    var baseURL: String { switch self { case .custom: return ""; case .openAI: return "https://api.openai.com/v1"; case .grok: return "https://api.x.ai/v1" } }
}

struct TranslationProfileMetadata {
    static func save(baseURL: String, model: String, settings: UserDefaults = CompanionPreferences.store) throws {
        let scope = try TranslationProfile.scope(provider: .openAI, baseURL: baseURL)
        var values = settings.dictionary(forKey: "translationProfileModels") as? [String: String] ?? [:]
        values[scope] = model; settings.set(values, forKey: "translationProfileModels")
    }
    static func model(baseURL: String, settings: UserDefaults = CompanionPreferences.store) -> String {
        guard let scope = try? TranslationProfile.scope(provider: .openAI, baseURL: baseURL) else { return "" }
        return (settings.dictionary(forKey: "translationProfileModels") as? [String: String])?[scope] ?? ""
    }
}
