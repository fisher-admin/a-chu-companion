import Foundation

@main struct HealthManifestTests {
    @MainActor static func settle(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !condition() { precondition(ContinuousClock.now < deadline); try await Task.sleep(for: .milliseconds(5)) }
    }
    @MainActor static func main() async throws {
        let google = TranslationPolicy.item(engine:"gemini",baseURL:"")
        let custom = TranslationPolicy.item(engine:"ai",baseURL:"https://unknown.example/v1")
        precondition(google.officialURL?.host == "ai.google.dev" && google.detail.contains("2026-10-05") && google.state == .unknown)
        precondition(custom.officialURL == nil && custom.detail.contains("未知"))
        precondition(TranslationPolicy.item(engine:"ai",baseURL:"https://api.openai.com/v1").officialURL?.host == "developers.openai.com")
        precondition(TranslationPolicy.item(engine:"ai",baseURL:"https://api.x.ai/v1").officialURL?.host == "docs.x.ai")
        print("PASS: built-in policy facts have official links and dates without claiming account free balance")
        let name = "achu-health-" + UUID().uuidString; let prefs = UserDefaults(suiteName:name)!
        defer { prefs.removePersistentDomain(forName:name) }
        let original = try TranslationProfile.scope(provider:.openAI,baseURL:"https://original.example/v1")
        prefs.set(original,forKey:"legacyTranslationCredentialScope")
        var accounts: [String] = []
        let lookup: (String) -> CredentialPresence = { account in accounts.append(account); return account == RemoteTranslationProvider.openAI.credentialAccount ? .present : .missing }
        let other = Credentials.presence(provider:.openAI,baseURL:"https://other.example/v1",settings:prefs,lookup:lookup)
        precondition(other == .missing && !accounts.contains(RemoteTranslationProvider.openAI.credentialAccount))
        precondition(Credentials.presence(provider:.openAI,baseURL:"https://original.example/v1",settings:prefs,lookup:lookup) == .present)
        precondition(Credentials.presence(provider:.gemini,baseURL:"",settings:prefs,lookup:{_ in .unknown}) == .unknown)
        print("PASS: passive credential presence follows endpoint bindings and never reads or migrates key data")
        let center = HealthCenter(); var calls = 0; var gate: CheckedContinuation<[HealthItem],Never>?
        let first = Task { await center.check(key:"same",now:0) { calls += 1; return await withCheckedContinuation {gate=$0} } }
        try await settle { gate != nil }
        await center.check(key:"same",now:0.1) { calls += 1; return [] }
        precondition(calls == 1)
        gate?.resume(returning:[.init(name:"initial",state:.ready,detail:"synthetic")]); gate = nil; await first.value
        print("PASS: repeated opens coalesce into one pending passive check")
        let old = Task { await center.check(key:"old",now:61) { await withCheckedContinuation {gate=$0} } }
        try await settle { gate != nil }
        precondition(center.items.isEmpty)
        await center.check(key:"new",now:62) { [.init(name:"current",state:.unconfigured,detail:"synthetic")] }
        gate?.resume(returning:[.init(name:"late",state:.ready,detail:"synthetic")]); gate = nil; await old.value
        precondition(center.items.map(\.name) == ["current"])
        print("PASS: changing the check configuration removes stale cards and rejects late results")
        var probes = 0
        let model = TranslatorModel(permissionCheck:{true},remoteKeyRead:{_ in preconditionFailure("health must not read secret key data")},credentialPresence:{_,_ in probes += 1; return .missing})
        defer {model.stopPermissionMonitoring()}
        model.engine = "ai"; model.baseURL = "https://synthetic.example/v1"; model.aiModel = "synthetic"
        model.refreshHealth(); try await settle { !model.health.items.isEmpty && !model.health.checking }
        precondition(probes == 1 && model.health.items.contains { $0.name == "API 密钥" && $0.state == .unconfigured })
        precondition(model.health.items.contains { $0.name == "CLI / Chrome" && $0.state == .unconfigured })
        precondition(model.health.items.contains { $0.name == "云翻译" && $0.state == .unknown })
        print("PASS: passive health separates missing credentials and optional bridges without inferring remote model capability")
        print("5 health manifest contracts passed")
    }
}
