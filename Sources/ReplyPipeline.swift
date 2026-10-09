import Foundation

/// Source publication and bounded translation scheduling share identities, not
/// lifetimes. Every result is checked against its own slice revision and epoch.
@MainActor final class ReplyPipeline {
    private struct Slice {
        var part: TranslationPart
        var changedAt: TimeInterval
        var revision = UUID()
        var chinese: String?
        var failed = false
        var retryAt: TimeInterval?
        var attempts = 0
    }
    private struct Record {
        var original: String
        var slices: [Slice]
        var complete: Bool
        var manual: Bool
    }
    var onOriginal: (String, String, String) -> Void = { _, _, _ in }
    var onTranslation: (String, String, String, Bool) -> Void = { _, _, _, _ in }
    var onCompletion: (String, Bool) -> Void = { _, _ in }
    var onStatus: (String, Bool) -> Void = { _, _ in }
    /// Called when the last running slice finishes and nothing else is ready.
    var onIdle: () -> Void = {}
    /// Local translation used when the primary service fails for one slice.
    var fallback: (@MainActor (String) async throws -> String)?
    private let incremental: Bool
    private let translate: @MainActor (String) async throws -> String
    private var records: [String: Record] = [:]
    private var order: [String] = []
    private var retired = RetiredIDs()
    private var conversation = ""
    private var suspended = false
    private var cooldownUntil = -Double.infinity
    private var minimumOrdinal = 1
    private var now: TimeInterval = 0
    private var epoch = UUID()
    private struct SliceKey: Hashable { let id: String; let index: Int }
    private struct Running { let token: UUID; let revision: UUID; let task: Task<Void, Never> }
    /// Slices translate concurrently up to this bound; publish() still renders only the
    /// contiguous translated prefix, so output order always follows the source.
    private let concurrency: Int
    private var running: [SliceKey: Running] = [:]
    private(set) var completedTurns = 0
    var busy: Bool { !running.isEmpty }
    /// Live records, including finished ones still shown in history; for memory checks.
    var recordCount: Int { records.count }
    var hasFailures: Bool { suspended || records.values.contains { $0.slices.contains { $0.failed || $0.retryAt != nil } } }
    var pendingCharacters: Int { records.values.reduce(0) { $0 + $1.slices.filter { $0.chinese == nil }.reduce(0) { $0 + $1.part.text.count } } }
    var queuedCharacters: Int { ready().reduce(0) { $0 + (records[$1.0]?.slices[$1.1].part.text.count ?? 0) } }
    var queuedCount: Int { ready().count }
    init(incremental: Bool = true, concurrency: Int = 1, translate: @escaping @MainActor (String) async throws -> String) {
        self.incremental = incremental; self.concurrency = max(1, concurrency); self.translate = translate
    }
    func observe(conversation value: String, messages: [ChatMessage], responseComplete: Bool, now: TimeInterval) {
        self.now = now
        if value != conversation {
            cancel(); records = records.filter { $0.value.manual }; order.removeAll { records[$0] == nil }
            conversation = value
            minimumOrdinal = messages.last.map { $0.ordinal + ($0.author == .assistant ? 0 : 1) } ?? 1
        }
        let observedOrdinals = Set(messages.map(\.ordinal))
        let present = Set(messages.filter { $0.author == .assistant }.map { ReplyIdentity.id(conversation: value, ordinal: $0.ordinal, segment: $0.segment) })
        for id in order where records[id]?.manual == false {
            // Only remove missing siblings in an ordinal actually observed now.
            if !present.contains(id), messages.contains(where: { observedOrdinals.contains($0.ordinal) && id.hasPrefix(ReplyIdentity.id(conversation: value, ordinal: $0.ordinal) + ":part:") }) {
                records[id] = nil
            }
        }
        order.removeAll { records[$0] == nil }
        for (key, entry) in running where records[key.id] == nil { entry.task.cancel(); running[key] = nil }
        let newest = messages.last?.ordinal ?? 0
        for message in messages where message.author == .assistant && message.ordinal >= minimumOrdinal {
            let id = ReplyIdentity.id(conversation: value, ordinal: message.ordinal, segment: message.segment)
            let complete = message.completed ?? (message.ordinal < newest || responseComplete)
            update(id: id, text: message.text, complete: complete, manual: false)
        }
        minimumOrdinal = max(minimumOrdinal, newest - 128)
        if responseComplete { completedTurns = max(completedTurns, newest) }
        pump()
    }
    func submit(_ work: ReplyWork, now: TimeInterval = Date().timeIntervalSinceReferenceDate) {
        self.now = now; suspended = false; retired.remove(work.id)
        update(id: work.id, text: work.candidate.text, complete: true, manual: true)
        if let record = records[work.id], !record.slices.isEmpty, record.slices.allSatisfy({ $0.chinese != nil }) {
            publish(work.id)
            onStatus("所选历史回复中文已就绪。", busy)
        }
        pump()
    }
    private func update(id: String, text: String, complete: Bool, manual: Bool) {
        guard !retired.contains(id) else { return }
        let old = records[id]
        if old?.original != text { onOriginal(id, text, "原文已读取，稳定片段将自动翻译") }
        guard !retired.contains(id) else { return }
        guard text.count <= ForeignTextPolicy.limit else { onStatus("原文已完整保留，但超过 50,000 字符，未自动翻译。", false); return }
        var prefix = ""; var reusable: [Slice] = []
        if let old {
            for (index, slice) in old.slices.enumerated() {
                guard slice.chinese != nil else { break }
                if index == old.slices.count - 1 && !slice.part.translatable { break }
                let extended = prefix + slice.part.text
                guard text.hasPrefix(extended) else { break }
                let tail = text.dropFirst(extended.count)
                guard tail.isEmpty || extended.last?.isWhitespace == true || extended.last?.isPunctuation == true || tail.first?.isWhitespace == true else { break }
                prefix = extended; reusable.append(slice)
            }
        }
        // Parse the whole source before removing translated text. A prefix can
        // end inside a table; parsing only its tail would lose the header,
        // nearby context, numeric protection and cell escaping rules.
        var consumed = prefix.count
        let parts = TranslationStructure.chunks(text, separateParagraphs: !complete).compactMap { part -> TranslationPart? in
            guard consumed < part.text.count else { consumed -= part.text.count; return nil }
            let remaining = TranslationPart(text: String(part.text.dropFirst(consumed)), translatable: part.translatable,
                                            tableCell: part.tableCell, context: part.context)
            consumed = 0
            return remaining
        }
        var slices: [Slice] = reusable
        for (i, part) in parts.enumerated() {
            let position = i + reusable.count
            if let previous = old?.slices, position < previous.count, previous[position].part == part { slices.append(previous[position]) }
            else { slices.append(.init(part: part, changedAt: now)) }
        }
        records[id] = .init(original: text, slices: slices, complete: complete, manual: manual)
        if old == nil { order.append(id) }
        for (key, entry) in running where key.id == id && (key.index >= slices.count || slices[key.index].revision != entry.revision) {
            entry.task.cancel(); running[key] = nil
        }
        if old?.original != text, old != nil { publish(id) }
        onCompletion(id, complete && slices.allSatisfy { $0.chinese != nil })
    }
    func tick(now: TimeInterval) { self.now = now; pump() }
    private func ready() -> [(String, Int)] {
        guard !suspended else { return [] }
        var result: [(String, Int)] = []; var characters = 0
        for id in order {
            guard let record = records[id] else { continue }
            for (index, slice) in record.slices.enumerated() where slice.chinese == nil && !slice.failed {
                guard slice.retryAt.map({ now >= $0 }) ?? true else { continue }
                if slice.part.translatable, now < cooldownUntil, fallback == nil { continue }
                // A slice followed by more text after its line break is a finished paragraph,
                // table or block: translate it now. The growing tail still waits until stable.
                let closed = index < record.slices.count - 1 && slice.part.text.last?.isNewline == true
                guard record.complete || (incremental && (closed || now - slice.changedAt >= 3)) else { continue }
                if running[SliceKey(id: id, index: index)] != nil { continue }
                // A protected block may be larger; it needs no cloud request.
                let size = slice.part.text.count
                guard result.count < 64, characters + size <= 150_000 else { return result }
                characters += size; result.append((id, index))
                break // One slice per record gives other stable stages a turn.
            }
        }
        return result
    }
    private func pump() {
        while running.count < concurrency, let (id, index) = ready().first, let record = records[id] {
            start(id: id, index: index, slice: record.slices[index])
        }
    }
    private func start(id: String, index: Int, slice: Slice) {
        let token = epoch, mine = UUID(), key = SliceKey(id: id, index: index)
        onStatus("正在翻译稳定片段…", true)
        let task = Task { [weak self] in
            guard let self else { return }
            defer { self.release(key, mine) }
            var primaryFailure: Error?
            do {
                var fallbackReason: Error?
                let translated = slice.part.translatable ? try await TranslationContext.$source.withValue(slice.part.context) {
                    if self.now < self.cooldownUntil, let fallback = self.fallback {
                        primaryFailure = ServiceCooldown(seconds: self.cooldownUntil - self.now)
                        let value = try await TextTranslation.run(slice.part.text, translate: fallback)
                        fallbackReason = primaryFailure
                        return value
                    }
                    do { return try await TextTranslation.run(slice.part.text, translate: self.translate) }
                    catch let error where !(error is CancellationError) && !Task.isCancelled {
                        guard self.epoch == token else { throw CancellationError() }
                        primaryFailure = error
                        if let wait = error as? ServiceRetryDelay { self.cooldownUntil = max(self.cooldownUntil, self.now + wait.seconds) }
                        guard self.fallback != nil else { throw error }
                        let value = try await TextTranslation.run(slice.part.text, translate: self.fallback!)
                        fallbackReason = error
                        return value
                    }
                } : slice.part.text
                let value = slice.part.tableCell && slice.part.translatable ? MarkdownTable.escapeCell(translated) : translated
                guard epoch == token, running[key]?.token == mine, !Task.isCancelled, let current = records[id], index < current.slices.count, current.slices[index].revision == slice.revision else { return }
                records[id]?.slices[index].chinese = value
                records[id]?.slices[index].retryAt = nil
                records[id]?.slices[index].attempts = 0
                publish(id)
                if let fallbackReason {
                    onStatus("翻译服务未能提供可用译文（" + fallbackReason.localizedDescription + "），本段已改用系统翻译。", running.count > 1)
                } else {
                    onStatus(hasFailures ? "部分片段翻译失败，原文和已有中文已保留；可重试未完成片段。" : "阶段性中文已更新，继续读取后续回复。", running.count > 1)
                }
            } catch {
                guard epoch == token, running[key]?.token == mine, let current = records[id], index < current.slices.count, current.slices[index].revision == slice.revision else { return }
                let failure = primaryFailure ?? error
                let wait = (failure as? ServiceRetryDelay)?.seconds
                records[id]?.slices[index].attempts += 1
                if let wait, !(error is CancellationError), slice.attempts < 2 {
                    cooldownUntil = max(cooldownUntil, now + wait)
                    records[id]?.slices[index].retryAt = cooldownUntil
                } else { records[id]?.slices[index].failed = true; records[id]?.slices[index].retryAt = nil }
                let primary = primaryFailure.map { $0.localizedDescription + "；" } ?? ""
                onStatus(error is CancellationError ? "翻译已取消，可重试。" : "翻译失败：" + primary + error.localizedDescription + (records[id]?.slices[index].retryAt != nil ? "；保留原文和已有中文，等待后自动重试。" : "；已有中文保留，可重试。"), running.count > 1)
            }
        }
        running[key] = Running(token: mine, revision: slice.revision, task: task)
    }
    /// Every exit path frees its slot exactly once; a cancelled or superseded slice
    /// no longer owns the key, so its late exit changes nothing.
    private func release(_ key: SliceKey, _ mine: UUID) {
        guard running[key]?.token == mine else { return }
        running[key] = nil
        order.removeAll { $0 == key.id }; if records[key.id] != nil { order.append(key.id) }
        pump()
        if running.isEmpty { onIdle() }
    }
    private func publish(_ id: String) {
        guard let record = records[id] else { return }
        var chinese = ""
        for slice in record.slices { guard let value = slice.chinese else { break }; chinese += value }
        if !chinese.isEmpty { onTranslation(id, record.original, chinese, record.complete && record.slices.allSatisfy { $0.chinese != nil }) }
    }
    func retry() {
        suspended = false
        for id in order { for index in records[id]?.slices.indices ?? 0..<0 { records[id]?.slices[index].failed = false; records[id]?.slices[index].attempts = 0 } }
        pump()
    }
    func retire(_ ids: Set<String>) {
        retired.formUnion(ids)
        for id in ids { records[id] = nil }
        order.removeAll { ids.contains($0) }
        for (key, entry) in running where ids.contains(key.id) { entry.task.cancel(); running[key] = nil }
        pump()
    }
    func cancel() { epoch = UUID(); running.values.forEach { $0.task.cancel() }; running = [:] }
    func suspend() { suspended = true; cancel() }
    func clear() { retired.formUnion(records.keys); cancel(); records = [:]; order = [] }
}
