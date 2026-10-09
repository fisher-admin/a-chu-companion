import Foundation
import SwiftUI

enum HealthState: String, Sendable { case ready = "可用", unknown = "待验证", unconfigured = "未配置", waiting = "准备中", unavailable = "不可用", stale = "旧数据" }
struct HealthItem: Identifiable, Equatable, Sendable {
    let name: String
    let state: HealthState
    let detail: String
    var officialURL: URL? = nil
    var id: String { name }
}
@MainActor final class HealthCenter: ObservableObject {
    @Published private(set) var items: [HealthItem] = []
    @Published private(set) var checking = false
    private var cachedKey = ""
    private var checkedAt = -Double.infinity
    private var generation = UUID()
    func invalidate() { checkedAt = -Double.infinity; generation = UUID(); checking = false }
    func check(key: String, now: TimeInterval = Date().timeIntervalSinceReferenceDate,
               inspect: @MainActor () async -> [HealthItem]) async {
        if cachedKey == key && (checking || now - checkedAt < 60) { return }
        if cachedKey != key { items = [] }
        let token = UUID(); generation = token; cachedKey = key; checking = true
        let result = await inspect()
        guard token == generation else { return }
        items = result; checkedAt = now; checking = false
    }
}

enum TranslationPolicy {
    static let verifiedDate = "2026-10-05"
    static func item(engine: String, baseURL: String) -> HealthItem {
        var detail = "自定义服务的免费条件未知，请核对供应商政策。"
        var link: URL?
        if engine == "apple" { detail = "使用系统语言包，不查询云端免费余额。" }
        else if engine == "gemini" {
            detail = "Gemini 有条件免费层；实际以所选模型和 Google 项目为准。"
            link = URL(string:"https://ai.google.dev/gemini-api/docs/pricing")
        } else if let endpoint = try? AIProtocol.endpoint(baseURL) {
            if endpoint.host?.lowercased() == "api.openai.com" {
                detail = "OpenAI 按服务和项目政策计费，不假定账户免费。"
                link = URL(string:"https://developers.openai.com/api/docs/pricing")
            } else if endpoint.host?.lowercased() == "api.x.ai" {
                detail = "Grok 按服务和账户政策计费，不假定账户免费。"
                link = URL(string:"https://docs.x.ai/developers/models")
            }
        }
        return .init(name:"免费政策",state:.unknown,detail:detail + " 资料日期 " + verifiedDate + "，不代表剩余额度。",officialURL:link)
    }
}
