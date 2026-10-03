import Foundation
import SwiftUI

enum ClaudePlan: String, Sendable {
    case pro = "Pro", max = "Max", team = "Team", enterprise = "Enterprise", free = "Free", unknown = "套餐未识别"
    static func decode(_ data: Data) throws -> Self {
        struct Organization: Decodable { let capabilities: [String] }
        guard let value = try? JSONDecoder().decode(Organization.self, from: data) else { throw ClaudeUsageError.malformed }
        let caps = Set(value.capabilities)
        if caps.contains("raven_enterprise") || caps.contains("claude_enterprise") { return .enterprise }
        if caps.contains("raven") || caps.contains("claude_team") { return .team }
        if caps.contains("claude_max") { return .max }
        if caps.contains("claude_pro") { return .pro }
        if caps.contains("chat") { return .free }
        return .unknown
    }
}

final class ClaudeUsageClient: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private var session: URLSession!
    init(protocolClasses: [AnyClass]? = nil) {
        super.init()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil; configuration.httpShouldSetCookies = false
        configuration.urlCache = nil; configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 15; configuration.timeoutIntervalForResource = 20
        if let protocolClasses { configuration.protocolClasses = protocolClasses }
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    func data(_ request: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else { throw ClaudeUsageError.network }
            switch response.statusCode {
            case 200: guard data.count <= 1_000_000 else { throw ClaudeUsageError.malformed }; return data
            case 401: throw ClaudeUsageError.expired
            case 429: throw ClaudeUsageError.rateLimited
            default: throw ClaudeUsageError.unavailable
            }
        } catch let error as ClaudeUsageError { throw error }
        catch is CancellationError { throw CancellationError() }
        catch { throw ClaudeUsageError.network }
    }
    func fetch(_ connection: ClaudeSession) async throws -> (ClaudeUsageSnapshot, ClaudePlan) {
        let request = try ClaudeUsageRequest.make(sessionKey: connection.key, organization: connection.organization)
        var profile = request
        profile.url = URL(string: "https://claude.ai/api/organizations/\(connection.organization)")!
        let profileRequest = profile
        async let usage = data(request)
        async let organization = data(profileRequest)
        let values = try await (usage, organization)
        return (try .decode(values.0), try ClaudePlan.decode(values.1))
    }
    func cancel() { session.invalidateAndCancel() }
}

@MainActor final class ClaudeUsageMonitor: ObservableObject {
    enum Source: String, CaseIterable { case desktop, session
        var name: String { self == .desktop ? "Claude 桌面端" : "指定 session" }
    }
    @Published private(set) var snapshot: ClaudeUsageSnapshot?
    @Published private(set) var plan: ClaudePlan = .unknown
    @Published private(set) var refreshing = false
    @Published private(set) var stale = false
    @Published private(set) var status = "连接额度后自动更新"
    @Published var showConnection = false
    @Published private(set) var source: Source
    @Published private(set) var organization = ""
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var fingerprint: String?
    private var requested = false
    private var retryAfter = Date.distantPast
    private let load: @Sendable (Source, Bool) throws -> ClaudeSession
    private let fetch: @Sendable (ClaudeSession) async throws -> (ClaudeUsageSnapshot, ClaudePlan)
    private let enabled: () -> Bool
    private var automaticRetry: Task<Void, Never>?

    init(load: @escaping @Sendable (Source, Bool) throws -> ClaudeSession = { source, prompt in
        try source == .desktop ? ClaudeDesktopSession.read(allowPrompt: prompt) : ClaudeSessionStore.read()
    }, fetch: @escaping @Sendable (ClaudeSession) async throws -> (ClaudeUsageSnapshot, ClaudePlan) = { connection in
        let client = ClaudeUsageClient(); defer { client.cancel() }; return try await client.fetch(connection)
    }, enabled: @escaping () -> Bool = { UserDefaults.standard.bool(forKey: "usageConnected") }) {
        source = Source(rawValue: UserDefaults.standard.string(forKey: "usageSource") ?? "desktop") ?? .desktop
        self.load = load; self.fetch = fetch; self.enabled = enabled
    }
    func connectDesktop() { configure(.desktop); refresh(allowPrompt: true) }
    func connectSession(key: String, organization: String) throws {
        try ClaudeSessionStore.save(key: key.trimmingCharacters(in: .whitespacesAndNewlines), organization: organization.trimmingCharacters(in: .whitespacesAndNewlines))
        configure(.session); refresh()
    }
    private func configure(_ source: Source) {
        stop(); self.source = source; fingerprint = nil; snapshot = nil; plan = .unknown; organization = ""; stale = false
        retryAfter = .distantPast
        UserDefaults.standard.set(source.rawValue, forKey: "usageSource"); UserDefaults.standard.set(true, forKey: "usageConnected")
    }
    func disconnect() {
        stop(); ClaudeSessionStore.remove(); UserDefaults.standard.set(false, forKey: "usageConnected")
        snapshot = nil; plan = .unknown; fingerprint = nil; organization = ""; stale = false; status = "连接额度后自动更新"
    }
    func stop() { generation = UUID(); task?.cancel(); task = nil; automaticRetry?.cancel(); automaticRetry = nil; requested = false; refreshing = false }
    func refresh(allowPrompt: Bool = false) {
        guard enabled() else { return }
        requested = true
        if task != nil { return }
        if retryAfter > Date() {
            status = "查询稍后重试"; stale = snapshot != nil
            if automaticRetry == nil {
                let seconds = max(0, retryAfter.timeIntervalSinceNow)
                automaticRetry = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(seconds))
                    guard !Task.isCancelled, let self else { return }
                    self.automaticRetry = nil; self.refresh()
                }
            }
            return
        }
        refreshing = true; status = "正在读取 Claude 额度…"
        let token = generation; let source = self.source; let load = self.load; let fetch = self.fetch
        task = Task { [weak self] in
            guard let self else { return }
            var prompt = allowPrompt
            repeat {
                requested = false
                do {
                    let shouldPrompt = prompt; prompt = false
                    let connection = try await Task.detached(priority: .utility) { try load(source, shouldPrompt) }.value
                    guard generation == token, !Task.isCancelled else { return }
                    if fingerprint != connection.fingerprint { snapshot = nil; plan = .unknown; stale = false }
                    fingerprint = connection.fingerprint; organization = connection.organization
                    let (value, plan) = try await fetch(connection)
                    guard generation == token, !Task.isCancelled else { return }
                    // Re-read the identity after the request so an account switch cannot publish old data.
                    let current = try await Task.detached(priority: .utility) { try load(source, false) }.value
                    guard generation == token, !Task.isCancelled else { return }
                    if current.fingerprint != connection.fingerprint {
                        snapshot = nil; self.plan = .unknown; fingerprint = nil; requested = true; continue
                    }
                    snapshot = value; self.plan = plan; stale = false; status = "已更新 · " + source.name
                } catch {
                    guard generation == token, !Task.isCancelled else { return }
                    stale = snapshot != nil; status = error.localizedDescription
                    if let error = error as? ClaudeUsageError, error == .expired || error == .desktopMissing || error == .keychain || error == .connection {
                        snapshot = nil; plan = .unknown; fingerprint = nil; organization = ""; stale = false
                    }
                    retryAfter = Date().addingTimeInterval((error as? ClaudeUsageError) == .rateLimited ? 60 : 15)
                    requested = (error as? ClaudeUsageError) == .rateLimited || (error as? ClaudeUsageError) == .network
                    break
                }
            } while requested && !Task.isCancelled
            guard generation == token else { return }
            task = nil; refreshing = false
            if requested { refresh() }
        }
    }
}
