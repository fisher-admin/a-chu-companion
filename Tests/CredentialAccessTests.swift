import Foundation
import Security
import LocalAuthentication

private final class ReadGate: @unchecked Sendable {
    private let lock = NSLock()
    private var started = false
    private let release = DispatchSemaphore(value: 0)
    var hasStarted: Bool { lock.lock(); defer { lock.unlock() }; return started }
    func wait() { lock.lock(); started = true; lock.unlock(); release.wait() }
    func resume() { release.signal() }
}

private final class BusyRead: @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    private let busyCount: Int
    init(_ busyCount: Int) { self.busyCount = busyCount }
    var count: Int { lock.lock(); defer { lock.unlock() }; return calls }
    func read() throws -> String {
        precondition(!Thread.isMainThread)
        lock.lock(); calls += 1; let busy = calls <= busyCount; lock.unlock()
        if busy { throw KeychainAccessError.busy }
        return "synthetic-value"
    }
}

@main struct CredentialAccessTests {
    @MainActor static func main() async throws {
        let background = Credentials.readRequest(account: "synthetic-api-key", allowPrompt: false)
        precondition((background[kSecUseAuthenticationContext as String] as? LAContext)?.interactionNotAllowed == true)
        precondition(background[kSecAttrService as String] as? String == "local.achu.companion" && background[kSecAttrAccount as String] as? String == "synthetic-api-key")
        print("PASS: automatic credential reads forbid UI and retain their exact service and account")
        let manual = Credentials.readRequest(account: "synthetic-api-key", allowPrompt: true)
        precondition((manual[kSecUseAuthenticationContext as String] as? LAContext)?.interactionNotAllowed == false)
        print("PASS: explicit manual credential confirmation is separate from automatic reading")
        let gate = ReadGate()
        let pending = Task { try await Credentials.offMainRead { gate.wait(); precondition(!Thread.isMainThread); return "synthetic-value" } }
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !gate.hasStarted {
            precondition(ContinuousClock.now < deadline)
            try await Task.sleep(for: .milliseconds(5))
        }
        var heartbeat = false
        let ui = Task { @MainActor in heartbeat = true }
        await ui.value
        precondition(heartbeat)
        gate.resume()
        let value = try await pending.value
        precondition(value == "synthetic-value")
        print("PASS: a waiting credential read does not block the main actor")
        let cancelGate = ReadGate()
        let cancelled = Task { try await Credentials.offMainRead { cancelGate.wait(); return "synthetic-late-value" } }
        let cancellationDeadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !cancelGate.hasStarted {
            precondition(ContinuousClock.now < cancellationDeadline)
            try await Task.sleep(for: .milliseconds(5))
        }
        cancelled.cancel(); cancelGate.resume()
        do { _ = try await cancelled.value; preconditionFailure("late credential must not reach a retired request") }
        catch is CancellationError {}
        print("PASS: cancelled reads reject late credentials before a translation request can use them")
        let temporary = BusyRead(2)
        let recovered = try await Credentials.offMainRead { try temporary.read() }
        precondition(recovered == "synthetic-value" && temporary.count == 3)
        print("PASS: a transient competing quota read does not fail an automatic translation credential read")
        let occupied = BusyRead(Int.max)
        do {
            _ = try await Credentials.offMainRead(busyRetryLimit: 2, retryDelay: .milliseconds(1)) { try occupied.read() }
            preconditionFailure("persistent contention must not spin forever")
        } catch KeychainAccessError.busy {}
        precondition(occupied.count == 3)
        print("PASS: persistent credential contention stops at the explicit retry bound")
        let unsafe = BusyRead(0)
        do {
            _ = try await Credentials.offMainRead { _ = try unsafe.read(); throw KeychainAccessError.unsafe }
            preconditionFailure("unsafe policy must fail immediately")
        } catch KeychainAccessError.unsafe {}
        precondition(unsafe.count == 1)
        print("PASS: authentication policy failures are not retried as transient contention")
        let waiting = BusyRead(Int.max)
        let cancelledRetry = Task { try await Credentials.offMainRead(retryDelay: .seconds(2)) { try waiting.read() } }
        let retryDeadline = ContinuousClock.now.advanced(by: .seconds(3))
        while waiting.count == 0 { precondition(ContinuousClock.now < retryDeadline); try await Task.sleep(for: .milliseconds(5)) }
        cancelledRetry.cancel()
        do { _ = try await cancelledRetry.value; preconditionFailure("cancelled backoff must not read again") }
        catch is CancellationError {}
        precondition(waiting.count == 1)
        print("PASS: cancelling credential backoff stops before another read or translation request")
        let mutation = BusyRead(1)
        do {
            _ = try await Credentials.offMainRead(busyRetryLimit: 0) { try mutation.read() }
            preconditionFailure("mutations must retain immediate busy refusal")
        } catch KeychainAccessError.busy {}
        precondition(mutation.count == 1)
        print("PASS: credential mutations do not opt into automatic read retry")
        print("9 credential access contracts passed")
    }
}
