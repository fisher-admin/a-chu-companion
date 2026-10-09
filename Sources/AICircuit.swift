import Foundation

/// Circuit breaker for the AI engine. Closed: every request may use AI. Open: AI is
/// skipped until the cooldown ends. Half-open: exactly one probe request tries AI;
/// its outcome closes the circuit or reopens it with a doubled cooldown.
@MainActor final class AICircuit {
    enum State: Equatable { case closed, open(until: Date), halfOpen }
    struct Permit: Equatable { fileprivate let probe: Bool; fileprivate let epoch: Int }

    private(set) var state: State = .closed
    private var failures: [Date] = []
    private var cooldown: TimeInterval
    private var probeInFlight = false
    private var epoch = 0
    private let threshold: Int, window: TimeInterval, baseCooldown: TimeInterval, maxCooldown: TimeInterval
    private let now: () -> Date

    init(threshold: Int = 3, window: TimeInterval = 60, baseCooldown: TimeInterval = 60, maxCooldown: TimeInterval = 600,
         now: @escaping () -> Date = Date.init) {
        self.threshold = threshold; self.window = window; self.baseCooldown = baseCooldown; self.maxCooldown = maxCooldown
        self.cooldown = baseCooldown; self.now = now
    }

    /// Returns nil while AI must be skipped.
    func acquire() -> Permit? {
        switch state {
        case .closed: return Permit(probe: false, epoch: epoch)
        case let .open(until):
            guard now() >= until else { return nil }
            state = .halfOpen
            fallthrough
        case .halfOpen:
            guard !probeInFlight else { return nil }
            probeInFlight = true
            return Permit(probe: true, epoch: epoch)
        }
    }

    func succeeded(_ permit: Permit) {
        guard permit.epoch == epoch else { return }
        if permit.probe { close() }
        // Concurrent requests keep their permits valid; only the failure history resets.
        else if state == .closed { failures = [] }
    }

    /// `severe` failures (rejected credentials) open the circuit for the longest cooldown at once.
    func failed(_ permit: Permit, retryAfter: TimeInterval? = nil, severe: Bool = false) {
        guard permit.epoch == epoch else { return }
        let date = now()
        if permit.probe {
            cooldown = min(cooldown * 2, maxCooldown)
            open(at: date, for: retryAfter.map { min(max($0, cooldown), maxCooldown) } ?? (severe ? maxCooldown : cooldown))
            return
        }
        guard state == .closed else { return }
        failures = failures.filter { date.timeIntervalSince($0) < window } + [date]
        if let retryAfter { open(at: date, for: min(max(retryAfter, 1), maxCooldown)) }
        else if severe { open(at: date, for: maxCooldown) }
        else if failures.count >= threshold { open(at: date, for: cooldown) }
    }

    /// Cancellation or an oversized chunk says nothing about service health.
    func released(_ permit: Permit) {
        guard permit.epoch == epoch, permit.probe else { return }
        probeInFlight = false
    }

    func reset() { close() }

    private func open(at date: Date, for duration: TimeInterval) {
        epoch += 1; probeInFlight = false; failures = []
        state = .open(until: date.addingTimeInterval(duration))
    }
    private func close() {
        epoch += 1; probeInFlight = false; failures = []; cooldown = baseCooldown
        state = .closed
    }
}
