import Foundation
import AppKit

@main struct OptimizationTests {
    @MainActor static func main() async throws {
        let a = try TranslationProfile.scope(provider: .openAI, baseURL: "https://EXAMPLE.com:443/v1/")
        let b = try TranslationProfile.scope(provider: .openAI, baseURL: "https://example.com/v1/chat/completions")
        precondition(a == b)
        precondition(a != (try! TranslationProfile.scope(provider: .openAI, baseURL: "https://example.com/other")))
        precondition(a != (try! TranslationProfile.scope(provider: .openAI, baseURL: "https://other.example/v1")))
        precondition(try! TranslationProfile.scope(provider: .gemini, baseURL: "") == "gemini-translation-api-key")
        print("PASS: endpoint credentials normalize harmless changes and separate different origins and paths")
        let code = "Translate this:\n```swift\nlet text = \"unchanged\"\n```\nUse `swift test` at /tmp/example with https://example.com/a?x=1 and {{name}}."
        let protected = TranslationStructure.parts(code)
        let echoed = protected.map(\.text).joined()
        precondition(echoed == code && protected.contains { !$0.translatable && $0.text.contains("let text") })
        let translated = try await TextTranslation.runProtected(code) { $0.uppercased() }
        precondition(translated.contains("let text = \"unchanged\"") && translated.contains("`swift test`") && translated.contains("https://example.com/a?x=1") && translated.contains("{{name}}"))
        print("PASS: Markdown code, commands, paths, URLs and placeholders survive real translation partitioning")
        let unclosed = "Text\n```python\nprint('keep')\n"
        precondition(TranslationStructure.parts(unclosed).last?.translatable == false)
        print("PASS: unclosed code remains protected")
        var originals: [String] = []; var chinese: [String] = []; var waiting: CheckedContinuation<String, Error>?
        let pipeline = ReplyPipeline(translate: { text in
            if text.contains("first") { return try await withCheckedThrowingContinuation { waiting = $0 } }
            return "中文:" + text
        })
        pipeline.onOriginal = { _, text, _ in originals.append(text) }
        pipeline.onTranslation = { _, _, text, _ in chinese.append(text) }
        pipeline.observe(conversation: "synthetic", messages: [.init(ordinal: 2, author: .assistant, text: "first phase", segment: 1)], responseComplete: false, now: 0)
        precondition(originals == ["first phase"] && chinese.isEmpty)
        pipeline.tick(now: 3)
        for _ in 0..<20 where waiting == nil { await Task.yield() }
        precondition(waiting != nil)
        pipeline.observe(conversation: "synthetic", messages: [.init(ordinal: 2, author: .assistant, text: "first phase", segment: 1), .init(ordinal: 2, author: .assistant, text: "second phase", segment: 2)], responseComplete: false, now: 3.1)
        precondition(originals.last == "second phase", "Slow translation must not block new original")
        pipeline.tick(now: 3.2); waiting?.resume(returning: "第一阶段中文"); waiting = nil
        for _ in 0..<20 where chinese.isEmpty { await Task.yield() }
        precondition(chinese.first == "第一阶段中文" && pipeline.completedTurns == 0)
        pipeline.tick(now: 12)
        for _ in 0..<20 where chinese.count < 2 { await Task.yield() }
        precondition(chinese.count == 2 && pipeline.completedTurns == 0)
        print("PASS: original is immediate and stage Chinese arrives before the 36-second turn completion")
        let count = chinese.count
        pipeline.observe(conversation: "synthetic", messages: [.init(ordinal: 2, author: .assistant, text: "first phase", segment: 1), .init(ordinal: 2, author: .assistant, text: "second phase", segment: 2)], responseComplete: true, now: 36)
        for _ in 0..<10 { await Task.yield() }
        precondition(chinese.count == count)
        pipeline.clear()
        precondition(pipeline.pendingCharacters == 0)
        print("PASS: final reconciliation does not retranslate stable pieces and clear retires work")
        let model = TranslatorModel(permissionCheck: { true }, remoteKeyRead: { _ in "" })
        defer { model.stopPermissionMonitoring() }
        model.recordReply(id: "a", foreign: "first", chinese: "第一条", language: .english)
        model.recordReply(id: "b", foreign: "second", chinese: "第二条", language: .english)
        let scroll = model.chatRevision
        model.recordReplyOriginal(id: "a", foreign: "first revised", language: .english)
        precondition(model.history.map(\.id) == ["a", "b"] && model.history[0].chinese == "第一条" && model.chatRevision == scroll)
        print("PASS: revisions retain Chinese and record order without forcing scroll")
        try await checkHistoryDisplayOrder()
        print("7 optimization contracts passed")
    }

    @MainActor static func checkHistoryDisplayOrder() async throws {
        let model = TranslatorModel(permissionCheck: { false })
        defer { model.replies.stop(); model.stopPermissionMonitoring() }
        model.replies.testTranslation = { _ in "模拟译文" }
        let conversation = "synthetic history order"
        let old = ReplyWork(candidate: .init(ordinal: 2, text: "Older reply."), conversation: conversation, manual: true)
        let other = ReplyIdentity.id(conversation: "separate conversation", ordinal: 99)
        let latest = ReplyIdentity.id(conversation: conversation, ordinal: 12, segment: 10)
        let earlierSegment = ReplyIdentity.id(conversation: conversation, ordinal: 12, segment: 2)
        model.recordReply(id: other, foreign: "Separate reply.", chinese: "另一会话", language: .english)
        model.history.append(.init(id: "draft", isUser: true, chinese: "草稿", foreign: "Draft."))
        model.recordReply(id: latest, foreign: "Later segment.", chinese: "后段", language: .english)
        model.recordReply(id: earlierSegment, foreign: "Earlier segment.", chinese: "前段", language: .english)
        model.replies.historyChoices = [old]
        model.replies.selectHistoryReply(old)
        let expected = [other, "draft", old.id, earlierSegment, latest]
        precondition(model.displayedHistory.map(\.id) == expected, "Late replies must appear in original message and segment order")
        precondition(model.history.last?.id == old.id, "History retention must still use acquisition order")
        precondition(model.chatScrollTarget == old.id, "An explicit history selection should still scroll to the selected reply")
        for _ in 0..<100 where model.history.last?.chinese.isEmpty == true {
            try await Task.sleep(for: .milliseconds(10))
        }
        precondition(model.history.last?.chinese == "模拟译文" && model.displayedHistory.map(\.id) == expected)
        print("PASS: a late historical reply and out-of-order segments display in conversation order")
    }
}
