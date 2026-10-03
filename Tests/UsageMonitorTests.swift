import Foundation

final class UsageState: @unchecked Sendable {
    let lock = NSLock()
    var requests = 0
    var account = "one"
    var error: ClaudeUsageError?
    func connection() -> ClaudeSession {
        lock.lock(); defer { lock.unlock() }
        return .init(key: "sk-ant-sid01-fixtureonlyabcdefghijklmnop", organization: "12345678-1234-1234-1234-123456789abc", fingerprint: account)
    }
    func changeAccount() { lock.lock(); account = "two"; lock.unlock() }
    func fail(_ value: ClaudeUsageError?) { lock.lock(); error = value; lock.unlock() }
    func begin() throws -> Int {
        lock.lock(); defer { lock.unlock() }; requests += 1
        if let error { throw error }; return requests
    }
    func count() -> Int { lock.lock(); defer { lock.unlock() }; return requests }
    func fetch(_ connection: ClaudeSession) async throws -> (ClaudeUsageSnapshot, ClaudePlan) {
        let count = try begin()
        try await Task.sleep(for: .milliseconds(35))
        return (.init(fiveHour: .init(usedPercentage: connection.fingerprint == "one" ? Double(count) : 90, resetsAt: nil), sevenDay: nil, observedAt: Date()), .max)
    }
}

final class UsageHTTP: URLProtocol, @unchecked Sendable {
    static var code = 200
    static var seen: URLRequest?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.seen = request
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.code, httpVersion: "HTTP/1.1", headerFields: ["Content-Type":"application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{\"five_hour\":{\"utilization\":0,\"resets_at\":null}}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct UsageMonitorTests {
    @MainActor static func main() async throws {
        let keys = ["usageConnected", "usageSource"].map { ($0, UserDefaults.standard.object(forKey: $0)) }
        defer { for (key, value) in keys { UserDefaults.standard.set(value, forKey: key) } }
        let state = UsageState()
        let monitor = ClaudeUsageMonitor(load: { _, _ in state.connection() }, fetch: { try await state.fetch($0) }, enabled: { true })
        defer { monitor.stop() }
        monitor.refresh()
        try await Task.sleep(for: .milliseconds(10))
        for _ in 0..<8 { monitor.refresh() }
        try await Task.sleep(for: .milliseconds(110))
        precondition(state.count() == 2 && !monitor.refreshing && monitor.snapshot?.fiveHour?.usedPercentage == 2)
        print("PASS: overlapping reply refreshes coalesce into one latest follow-up")
        monitor.refresh(); try await Task.sleep(for: .milliseconds(10)); state.changeAccount()
        try await Task.sleep(for: .milliseconds(110))
        precondition(monitor.snapshot?.fiveHour?.usedPercentage == 90 && monitor.plan == .max)
        print("PASS: an account switch discards the old in-flight result and fetches the current account")
        state.fail(.network); monitor.refresh(); try await Task.sleep(for: .milliseconds(40))
        precondition(monitor.stale && monitor.snapshot?.fiveHour?.usedPercentage == 90)
        monitor.stop()
        print("PASS: a temporary failure marks the preserved reading as stale")
        let expiredState = UsageState(); expiredState.fail(.expired)
        let expired = ClaudeUsageMonitor(load: { _, _ in expiredState.connection() }, fetch: { try await expiredState.fetch($0) }, enabled: { true })
        expired.refresh(); try await Task.sleep(for: .milliseconds(40))
        precondition(expired.snapshot == nil && expired.organization.isEmpty && !expired.refreshing)
        expired.stop()
        print("PASS: expired credentials clear account values without pretending usage is zero")
        state.fail(nil)
        let cancelled = ClaudeUsageMonitor(load: { _, _ in state.connection() }, fetch: { try await state.fetch($0) }, enabled: { true })
        cancelled.refresh(); try await Task.sleep(for: .milliseconds(10)); cancelled.stop()
        try await Task.sleep(for: .milliseconds(50))
        precondition(cancelled.snapshot == nil && !cancelled.refreshing)
        print("PASS: stopping a connection prevents late results from appearing")
        for (capability, plan) in [("claude_pro", ClaudePlan.pro),("claude_max", .max),("raven", .team),("raven_enterprise", .enterprise),("chat", .free)] {
            let actual = try ClaudePlan.decode(Data("{\"capabilities\":[\"\(capability)\"]}".utf8))
            precondition(actual == plan)
        }
        print("PASS: subscription types come from account capabilities")
        let hex = "76313056837fd51699a9075a915e33758445399f40383a7da627757792d3063e075db3aa5d8528bff2238ac6230bc424d00b129443e25fcab2f25d966030c4b0c7b9b72c03b24693e3bf3e3dd81143930a789d"
        let bytes = stride(from: 0, to: hex.count, by: 2).map { offset -> UInt8 in
            let start = hex.index(hex.startIndex, offsetBy: offset); return UInt8(hex[start..<hex.index(start, offsetBy: 2)], radix: 16)!
        }
        let cookie = try ClaudeDesktopSession.decodeCookie(Data(bytes), password: Data("fixture-only-password".utf8), host: ".claude.ai", version: 24)
        precondition(cookie == "sk-ant-sid01-fixtureonlyabcdefghijklmnop")
        do { _ = try ClaudeDesktopSession.decodeCookie(Data(bytes), password: Data("fixture-only-password".utf8), host: ".evil.example", version: 24); preconditionFailure() } catch {}
        print("PASS: Chromium cookie decryption matches an independent OpenSSL fixture and verifies its domain")
        let client = ClaudeUsageClient(protocolClasses: [UsageHTTP.self]); defer { client.cancel() }
        let request = try ClaudeUsageRequest.make(sessionKey: cookie, organization: "12345678-1234-1234-1234-123456789abc")
        _ = try await client.data(request)
        precondition(UsageHTTP.seen?.httpMethod == "GET" && UsageHTTP.seen?.httpBody == nil)
        for (status, expected) in [(401, ClaudeUsageError.expired),(403,.unavailable),(429,.rateLimited),(503,.unavailable),(302,.unavailable)] {
            UsageHTTP.code = status
            do { _ = try await client.data(request); preconditionFailure() }
            catch let error as ClaudeUsageError { precondition(error == expected) }
        }
        print("PASS: authentication, denial, throttling, server failure and redirects stay distinct from successful data")
        print("8 usage integration tests passed")
    }
}
