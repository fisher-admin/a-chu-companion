import Foundation

@MainActor
final class AccessibilityPermissionMonitor {
    var onChange: (Bool) -> Void = { _ in }
    private let check: @MainActor () -> Bool
    private let interval: UInt64
    private var lastValue: Bool?
    private var polling: Task<Void, Never>?

    init(check: @escaping @MainActor () -> Bool, interval: UInt64 = 1_000_000_000) {
        precondition(interval > 0)
        self.check = check
        self.interval = interval
    }

    func refresh() {
        let value = check()
        guard value != lastValue else { return }
        lastValue = value
        onChange(value)
    }

    func start() {
        refresh()
        guard polling == nil else { return }
        let interval = interval
        // Keep checking while System Settings is active; a nonactivating panel
        // does not reliably receive application activation notifications.
        polling = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: interval) }
                catch { return }
                guard !Task.isCancelled, let self else { return }
                self.refresh()
            }
        }
    }
    func stop() { polling?.cancel(); polling = nil }
    deinit { polling?.cancel() }
}
