import Foundation
import Security

private final class FakePolicy: @unchecked Sendable {
    var allowed = true
    var changes: [Bool] = []
    var failDisable = false
    func set(_ value: Bool) -> OSStatus {
        changes.append(value)
        if !value && failDisable { return errSecNotAvailable }
        allowed = value; return errSecSuccess
    }
    func get() -> Bool { allowed }
}
@main struct KeychainPolicyTests {
    @MainActor static func main() async throws {
        let fake = FakePolicy()
        let gate = KeychainAccessGate(set: fake.set, get: { fake.get() })
        let value = try gate.perform { precondition(!fake.allowed); return "synthetic" }
        precondition(value == "synthetic" && !fake.allowed)
        print("PASS: automatic legacy reads disable process interaction before the query")
        enum SyntheticError: Error { case failed }
        do { _ = try gate.perform { () -> String in throw SyntheticError.failed }; preconditionFailure() } catch is SyntheticError {}
        precondition(!fake.allowed)
        print("PASS: failed operations still restore the noninteractive process policy")
        let started = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        let worker = Task.detached { try gate.perform(allowPrompt: true) { precondition(fake.allowed); started.signal(); release.wait(); return "manual-synthetic" } }
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !signalled(started) { precondition(ContinuousClock.now < deadline); try await Task.sleep(for: .milliseconds(5)) }
        var queries = 0
        do { _ = try gate.perform { queries += 1; return "must-not-read" }; preconditionFailure() } catch KeychainAccessError.busy {}
        for _ in 0..<64 {
            do { _ = try gate.perform { queries += 1 }; preconditionFailure() } catch KeychainAccessError.busy {}
        }
        precondition(queries == 0)
        print("PASS: an active manual authorization makes automatic access fail immediately without another query")
        release.signal(); let manual = try await worker.value
        precondition(manual == "manual-synthetic" && !fake.allowed)
        print("PASS: explicit background authorization restores the process policy before returning data")
        let failed = FakePolicy(); failed.failDisable = true
        let unsafe = KeychainAccessGate(set: failed.set, get: { failed.get() })
        do { _ = try unsafe.perform { queries += 1 }; preconditionFailure() } catch KeychainAccessError.unsafe {}
        failed.failDisable = false
        do { _ = try unsafe.perform { queries += 1 }; preconditionFailure() } catch KeychainAccessError.unsafe {}
        precondition(queries == 0)
        print("PASS: a failed policy change prevents all queries until the application restarts")
        let unconfirmed = KeychainAccessGate(set: { _ in errSecSuccess }, get: { nil })
        do { _ = try unconfirmed.perform { queries += 1 }; preconditionFailure() } catch KeychainAccessError.unsafe {}
        precondition(queries == 0)
        print("PASS: an unreadable process policy is unavailable rather than silently treated as disabled")
        let restoreFailure = FakePolicy()
        let restoring = KeychainAccessGate(set: restoreFailure.set, get: { restoreFailure.get() })
        let refused = await Task.detached { () -> Bool in
            do { _ = try restoring.perform(allowPrompt: true) { restoreFailure.failDisable = true; return "must-not-publish" }; return false }
            catch KeychainAccessError.unsafe { return true }
            catch { return false }
        }.value
        precondition(refused)
        do { _ = try restoring.perform { queries += 1 }; preconditionFailure() } catch KeychainAccessError.unsafe {}
        precondition(queries == 0)
        print("PASS: failed restoration rejects the returned credential and blocks future access")
        do { _ = try gate.perform(allowPrompt: true) { queries += 1 }; preconditionFailure() } catch KeychainAccessError.mainThreadPrompt {}
        precondition(queries == 0 && !fake.allowed)
        print("PASS: manual authentication cannot start on the main thread")
        print("8 keychain policy contracts passed")
    }
    private static func signalled(_ value: DispatchSemaphore) -> Bool { value.wait(timeout: .now()) == .success }
}
