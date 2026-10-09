import Foundation
import SwiftUI
import Translation

struct SystemTranslationUnavailable: LocalizedError {
    let direction: TranslationDirection
    var errorDescription: String? {
        "系统翻译尚未准备好 \(direction.sourceName) → \(direction.targetName) 语言包，请保持伴侣窗口打开并按提示下载。"
    }
}

/// System translation for code that has no view of its own. On macOS 26 an installed
/// language pair gets a direct session; otherwise `sessionProvider` (normally a
/// `SystemSessionBroker`) lends a view-provided session. Calls run one at a time.
@MainActor final class SystemTranslator {
    var sessionProvider: ((TranslationDirection) async throws -> TranslationSession)?
    private var sessions: [TranslationDirection: TranslationSession] = [:]
    private var tail: Task<Void, Never>?

    func translate(_ text: String, direction: TranslationDirection) async throws -> String {
        try await serialized { [weak self] in
            guard let self else { throw CancellationError() }
            return try await self.session(for: direction).translate(text).targetText
        }
    }

    static func status(_ direction: TranslationDirection) async -> LanguageAvailability.Status {
        await LanguageAvailability().status(from: Locale.Language(identifier: direction.sourceIdentifier),
                                            to: Locale.Language(identifier: direction.targetIdentifier))
    }

    func reset() {
        if #available(macOS 26.0, *) { sessions.values.forEach { $0.cancel() } }
        sessions = [:]
    }

    private func session(for direction: TranslationDirection) async throws -> TranslationSession {
        if let session = sessions[direction] { return session }
        if #available(macOS 26.0, *), await Self.status(direction) == .installed {
            let session = TranslationSession(installedSource: Locale.Language(identifier: direction.sourceIdentifier),
                                             target: Locale.Language(identifier: direction.targetIdentifier))
            sessions[direction] = session
            return session
        }
        guard let sessionProvider else { throw SystemTranslationUnavailable(direction: direction) }
        return try await sessionProvider(direction)
    }

    private func serialized(_ operation: @escaping @MainActor () async throws -> String) async throws -> String {
        let previous = tail
        let work = Task { @MainActor () async throws -> String in
            await previous?.value
            try Task.checkCancellation()
            return try await operation()
        }
        tail = Task { _ = try? await work.value }
        return try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
    }
}

/// Bridges SwiftUI's `.translationTask` to code that needs a session on demand. Requesting a
/// session publishes a configuration; the view runs the task, which prepares the language
/// pair (showing the download prompt if needed) and then stays suspended so the session
/// remains valid until another direction is requested or the view goes away.
@MainActor final class SystemSessionBroker: ObservableObject {
    @Published private(set) var configuration: TranslationSession.Configuration?
    var onNeedsPresentation: () -> Void = {}
    private var direction: TranslationDirection?
    private var session: TranslationSession?
    private var generation = 0
    private var waiters: [UUID: CheckedContinuation<TranslationSession, Error>] = [:]
    private var hold: CheckedContinuation<Void, Never>?
    private var startTimer: Task<Void, Never>?
    private let startTimeout: Duration
    private let prepareTimeout: Duration

    init(startTimeout: Duration = .seconds(20), prepareTimeout: Duration = .seconds(120)) {
        self.startTimeout = startTimeout; self.prepareTimeout = prepareTimeout
    }

    func session(for direction: TranslationDirection) async throws -> TranslationSession {
        if let session, self.direction == direction { return session }
        if self.direction != direction || configuration == nil { request(direction) }
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { waiters[id] = $0 }
        } onCancel: {
            Task { @MainActor in self.waiters.removeValue(forKey: id)?.resume(throwing: CancellationError()) }
        }
    }

    /// Called from the view's `.translationTask` action.
    func run(_ session: TranslationSession) async {
        let current = generation
        startTimer?.cancel(); startTimer = nil
        do {
            _ = try await TextTranslation.withDeadline(timeout: prepareTimeout) { try await session.prepareTranslation(); return "" }
        } catch {
            guard current == generation else { return }
            fail(Task.isCancelled ? CancellationError() : error)
            return
        }
        guard current == generation, !Task.isCancelled else { return }
        self.session = session
        let ready = waiters; waiters = [:]
        ready.values.forEach { $0.resume(returning: session) }
        await withTaskCancellationHandler {
            await withCheckedContinuation { hold = $0 }
        } onCancel: {
            Task { @MainActor in self.releaseHold() }
        }
        if current == generation { self.session = nil; configuration = nil; direction = nil }
    }

    func reset() {
        generation += 1
        startTimer?.cancel(); startTimer = nil
        releaseHold()
        session = nil; direction = nil; configuration = nil
        let pending = waiters; waiters = [:]
        pending.values.forEach { $0.resume(throwing: CancellationError()) }
    }

    private func request(_ direction: TranslationDirection) {
        let previous = self.direction
        generation += 1
        releaseHold(); session = nil
        if let previous, previous != direction {
            let stale = waiters; waiters = [:]
            stale.values.forEach { $0.resume(throwing: SystemTranslationUnavailable(direction: previous)) }
        }
        self.direction = direction
        configuration = .init(source: Locale.Language(identifier: direction.sourceIdentifier),
                              target: Locale.Language(identifier: direction.targetIdentifier))
        onNeedsPresentation()
        let current = generation
        startTimer?.cancel()
        startTimer = Task { [weak self, startTimeout] in
            do { try await Task.sleep(for: startTimeout) } catch { return }
            guard let self, self.generation == current, self.session == nil else { return }
            self.fail(SystemTranslationUnavailable(direction: direction))
        }
    }

    private func fail(_ error: Error) {
        generation += 1
        startTimer?.cancel(); startTimer = nil
        session = nil; direction = nil; configuration = nil
        let pending = waiters; waiters = [:]
        pending.values.forEach { $0.resume(throwing: error) }
    }

    private func releaseHold() { hold?.resume(); hold = nil }
}
