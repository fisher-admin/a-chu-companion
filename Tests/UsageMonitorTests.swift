import Foundation

final class UsageState: @unchecked Sendable {
    let lock = NSLock()
    var requests = 0
    var account = "one"
    var error: ClaudeUsageError?
    private var pending: [Int: CheckedContinuation<Void, Never>] = [:]
    private var completed: Set<Int> = []
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
    func waiting(_ request: Int) -> Bool { lock.lock(); defer { lock.unlock() }; return pending[request] != nil }
    func finished(_ request: Int) -> Bool { lock.lock(); defer { lock.unlock() }; return completed.contains(request) }
    func complete(_ request: Int) {
        lock.lock(); let continuation = pending.removeValue(forKey: request); lock.unlock()
        precondition(continuation != nil, "The simulated request must be waiting before completion")
        continuation?.resume()
    }
    func fetch(_ connection: ClaudeSession) async throws -> (ClaudeUsageSnapshot, ClaudePlan) {
        let count = try begin()
        await withCheckedContinuation { continuation in
            lock.lock(); pending[count] = continuation; lock.unlock()
        }
        lock.withLock { _ = completed.insert(count) }
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

private final class UsageLoadRace: @unchecked Sendable {
    private let lock = NSLock()
    private var loads = 0
    private var requests = 0
    private let busyCalls: Set<Int>
    private let alwaysBusy: Bool
    private let unsafe: Bool
    init(busyCalls: Set<Int> = [], alwaysBusy: Bool = false, unsafe: Bool = false) {
        self.busyCalls = busyCalls; self.alwaysBusy = alwaysBusy; self.unsafe = unsafe
    }
    var loadCount: Int { lock.withLock { loads } }
    var requestCount: Int { lock.withLock { requests } }
    func connection() throws -> ClaudeSession {
        precondition(!Thread.isMainThread)
        let call = lock.withLock { loads += 1; return loads }
        if unsafe { throw KeychainAccessError.unsafe }
        if alwaysBusy || busyCalls.contains(call) { throw KeychainAccessError.busy }
        return .init(key: "sk-ant-sid01-fixtureonlyabcdefghijklmnop",
            organization: "12345678-1234-1234-1234-123456789abc", fingerprint: "race-fixture")
    }
    func fetch(_ connection: ClaudeSession) async throws -> (ClaudeUsageSnapshot, ClaudePlan) {
        lock.withLock { requests += 1 }
        return (.init(fiveHour: .init(usedPercentage: 47, resetsAt: nil),
            sevenDay: nil, observedAt: Date()), .pro)
    }
}

@main struct UsageMonitorTests {
    @MainActor static func main() async throws {
        let keys = ["usageConnected", "usageSource"].map { ($0, CompanionPreferences.store.object(forKey: $0)) }
        defer { for (key, value) in keys { CompanionPreferences.store.set(value, forKey: key) } }
        let state = UsageState()
        let monitor = ClaudeUsageMonitor(load: { _, _ in state.connection() }, fetch: { try await state.fetch($0) }, enabled: { true })
        defer { monitor.stop() }
        monitor.refresh()
        try await waitUntil("first request starts") { state.waiting(1) }
        for _ in 0..<8 { monitor.refresh() }
        state.complete(1)
        try await waitUntil("single-flight refresh completes") { !monitor.refreshing }
        precondition(state.count() == 1 && monitor.snapshot?.fiveHour?.usedPercentage == 1)
        monitor.refresh()
        try await waitUntil("cached refresh finishes") { !monitor.refreshing }
        precondition(state.count() == 1)
        print("PASS: overlapping refreshes share one request and success cooldown prevents another fetch")
        monitor.refresh(force: true)
        try await waitUntil("old-account request starts") { state.waiting(2) }
        state.changeAccount(); state.complete(2)
        try await waitUntil("new-account request starts") { state.waiting(3) }
        precondition(monitor.snapshot == nil && monitor.plan == .unknown)
        state.complete(3)
        try await waitUntil("new-account refresh completes") { !monitor.refreshing }
        precondition(monitor.snapshot?.fiveHour?.usedPercentage == 90 && monitor.plan == .max)
        print("PASS: an account switch discards the old in-flight result and fetches the current account")
        state.fail(.network); monitor.refresh(force: true)
        try await waitUntil("network failure is published") { monitor.stale && !monitor.refreshing }
        precondition(monitor.stale && monitor.snapshot?.fiveHour?.usedPercentage == 90)
        monitor.stop()
        print("PASS: a temporary failure marks the preserved reading as stale")
        let expiredState = UsageState(); expiredState.fail(.expired)
        let expired = ClaudeUsageMonitor(load: { _, _ in expiredState.connection() }, fetch: { try await expiredState.fetch($0) }, enabled: { true })
        expired.refresh()
        try await waitUntil("expired credentials are handled") { !expired.refreshing }
        precondition(expired.snapshot == nil && expired.organization.isEmpty && !expired.refreshing)
        expired.stop()
        print("PASS: expired credentials clear account values without pretending usage is zero")
        state.fail(nil)
        let cancelled = ClaudeUsageMonitor(load: { _, _ in state.connection() }, fetch: { try await state.fetch($0) }, enabled: { true })
        let cancelledRequest = state.count() + 1
        cancelled.refresh()
        try await waitUntil("request starts before stopping") { state.waiting(cancelledRequest) }
        cancelled.stop(); state.complete(cancelledRequest)
        try await waitUntil("uncooperative late fetch completes") { state.finished(cancelledRequest) }
        await Task.yield()
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
        for (status, expected) in [(401, ClaudeUsageError.expired),(403,.unavailable),(503,.unavailable),(302,.unavailable)] {
            UsageHTTP.code = status
            do { _ = try await client.data(request); preconditionFailure() }
            catch let error as ClaudeUsageError { precondition(error == expected) }
        }
        UsageHTTP.code = 429
        do { _ = try await client.data(request); preconditionFailure() }
        catch let error as ServiceCooldown { precondition(error.seconds == 60) }
        print("PASS: authentication, denial, throttling, server failure and redirects stay distinct from successful data")

        let initialRace = UsageLoadRace(busyCalls: [1, 2])
        let contended = ClaudeUsageMonitor(load: { _, _ in try initialRace.connection() },
            fetch: { try await initialRace.fetch($0) }, enabled: { true })
        contended.refresh()
        try await waitUntil("transient initial credential contention ends") { !contended.refreshing }
        precondition(initialRace.requestCount == 1 && initialRace.loadCount == 4
            && contended.snapshot?.fiveHour?.usedPercentage == 47 && !contended.stale,
            "A brief competing translation read must not permanently suppress the reply-triggered usage refresh")
        contended.stop()
        print("PASS: a reply-triggered usage refresh recovers from temporary credential contention")

        let postRace = UsageLoadRace(busyCalls: [2, 3])
        let checked = ClaudeUsageMonitor(load: { _, _ in try postRace.connection() },
            fetch: { try await postRace.fetch($0) }, enabled: { true })
        checked.refresh()
        try await waitUntil("post-request identity contention ends") { !checked.refreshing }
        precondition(postRace.requestCount == 1 && postRace.loadCount == 4
            && checked.snapshot?.fiveHour?.usedPercentage == 47,
            "A transient identity-check conflict must not discard valid data or repeat the HTTP request")
        checked.stop()
        print("PASS: post-request identity verification retries only the credential read, not HTTP")

        let blockedRace = UsageLoadRace(alwaysBusy: true)
        let blocked = ClaudeUsageMonitor(load: { _, _ in try blockedRace.connection() },
            fetch: { try await blockedRace.fetch($0) }, enabled: { true })
        blocked.refresh()
        try await waitUntil("persistent contention reaches its bound") { !blocked.refreshing }
        precondition(blockedRace.loadCount == 21 && blockedRace.requestCount == 0 && blocked.snapshot == nil)
        blocked.stop()
        print("PASS: persistent usage credential contention is bounded without a network request")

        let cancelledRace = UsageLoadRace(alwaysBusy: true)
        let cancelledLoad = ClaudeUsageMonitor(load: { _, _ in try cancelledRace.connection() },
            fetch: { try await cancelledRace.fetch($0) }, enabled: { true })
        cancelledLoad.refresh()
        try await waitUntil("credential contention begins before stopping") { cancelledRace.loadCount == 1 }
        var heartbeat = false
        await Task { @MainActor in heartbeat = true }.value
        precondition(heartbeat)
        print("PASS: the main actor stays responsive during usage credential backoff")
        cancelledLoad.stop()
        try await Task.sleep(for: .milliseconds(250))
        precondition(cancelledRace.loadCount == 1 && cancelledRace.requestCount == 0
            && cancelledLoad.snapshot == nil && !cancelledLoad.refreshing)
        print("PASS: stopping usage during contention prevents another read or network request")

        let unsafeRace = UsageLoadRace(unsafe: true)
        let unsafeLoad = ClaudeUsageMonitor(load: { _, _ in try unsafeRace.connection() },
            fetch: { try await unsafeRace.fetch($0) }, enabled: { true })
        unsafeLoad.refresh()
        try await waitUntil("unsafe credential policy is rejected") { !unsafeLoad.refreshing }
        precondition(unsafeRace.loadCount == 1 && unsafeRace.requestCount == 0 && unsafeLoad.snapshot == nil)
        unsafeLoad.stop()
        print("PASS: unsafe usage credential policy is not treated as transient contention")
        print("14 usage integration tests passed")
    }

    @MainActor static func waitUntil(_ event: String, _ condition: () -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(5))
        while !condition() {
            precondition(clock.now < deadline, "Timed out waiting for \(event)")
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
