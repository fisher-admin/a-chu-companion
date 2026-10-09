import Foundation

/// Translates a growing reply segment by segment. Segments are translated concurrently
/// (bounded), but only the contiguous prefix of finished segments is ever rendered, so
/// output order always matches source order. Code and whitespace pass through unchanged.
@MainActor final class StreamTranslationPipeline {
    struct State: Equatable, Sendable {
        var translated = ""
        var renderedSegments = 0
        var totalSegments = 0
        /// Rendered in their original language because both engines failed.
        var failedSegments: [Int] = []
        var lastFailure: String?
        var finished = false
        var complete = false
    }
    typealias Translate = @MainActor (String) async throws -> String

    private enum Outcome { case text(String), failed(String) }

    private(set) var state = State()
    var onUpdate: (State) -> Void = { _ in }
    private var segmenter: StreamSegmenter
    private var segments: [StreamSegment] = []
    private var epochs: [Int] = []
    private var outcomes: [Int: Outcome] = [:]
    private var running: [Int: Task<Void, Never>] = [:]
    private var queue: [Int] = []
    private var nextEpoch = 0
    private var cancelled = false
    private var sourceFinished = false
    private let maxConcurrent: Int
    private let translate: Translate

    init(maxConcurrent: Int = 3, segmenter: StreamSegmenter = StreamSegmenter(), translate: @escaping Translate) {
        precondition(maxConcurrent > 0)
        self.maxConcurrent = maxConcurrent; self.segmenter = segmenter; self.translate = translate
    }

    convenience init(translator: FailoverTranslator, direction: TranslationDirection, maxConcurrent: Int = 3) {
        self.init(maxConcurrent: maxConcurrent) { text in
            try await TextTranslation.run(text) { chunk in try await translator.translate(chunk, direction: direction) }
        }
    }

    var sourceText: String { segmenter.text }

    func ingest(snapshot: String) { guard !cancelled else { return }; apply(segmenter.update(snapshot: snapshot)) }
    func append(_ delta: String) { guard !cancelled else { return }; apply(SegmenterUpdate(segments: segmenter.append(delta))) }
    func finish(snapshot: String? = nil) {
        guard !cancelled, !sourceFinished else { return }
        sourceFinished = true
        apply(segmenter.finish(snapshot: snapshot))
    }

    func retryFailed() {
        guard !cancelled else { return }
        let failed = outcomes.compactMap { index, outcome -> Int? in if case .failed = outcome { return index }; return nil }
        for index in failed {
            outcomes[index] = nil
            epochs[index] = nextEpoch; nextEpoch += 1
            queue.append(index)
        }
        queue.sort()
        pump(); render()
    }

    func cancel() {
        cancelled = true
        running.values.forEach { $0.cancel() }
        running = [:]; queue = []
    }

    private func apply(_ update: SegmenterUpdate) {
        if let from = update.invalidatedFrom, from < segments.count {
            for index in from..<segments.count { running.removeValue(forKey: index)?.cancel(); outcomes[index] = nil }
            segments.removeSubrange(from...); epochs.removeSubrange(from...)
            queue.removeAll { $0 >= from }
        }
        for segment in update.segments {
            precondition(segment.index == segments.count, "segments must arrive in order")
            segments.append(segment); epochs.append(nextEpoch); nextEpoch += 1
            if segment.translatable { queue.append(segment.index) } else { outcomes[segment.index] = .text(segment.text) }
        }
        pump(); render()
    }

    private func pump() {
        while running.count < maxConcurrent, !queue.isEmpty {
            let index = queue.removeFirst()
            let epoch = epochs[index], text = segments[index].text, work = translate
            running[index] = Task { [weak self] in
                let outcome: Outcome
                do { outcome = .text(try await work(text)) }
                catch {
                    // Our own cancellation already removed this task; anything else is a failure.
                    if Task.isCancelled { return }
                    outcome = .failed(error.localizedDescription)
                }
                self?.settle(index, epoch: epoch, outcome)
            }
        }
    }

    private func settle(_ index: Int, epoch: Int, _ outcome: Outcome) {
        guard !cancelled, index < epochs.count, epochs[index] == epoch else { return }
        running[index] = nil
        outcomes[index] = outcome
        pump(); render()
    }

    private func render() {
        var next = State(finished: sourceFinished)
        while next.renderedSegments < segments.count, let outcome = outcomes[next.renderedSegments] {
            switch outcome {
            case let .text(value): next.translated += value
            case let .failed(message):
                next.translated += segments[next.renderedSegments].text
                next.failedSegments.append(next.renderedSegments)
                next.lastFailure = message
            }
            next.renderedSegments += 1
        }
        next.totalSegments = segments.count
        next.complete = next.finished && next.renderedSegments == segments.count && running.isEmpty && queue.isEmpty
        guard next != state else { return }
        state = next
        onUpdate(next)
    }
}
