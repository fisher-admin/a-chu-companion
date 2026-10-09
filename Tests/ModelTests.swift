import Foundation
import AppKit

@main struct ModelTests {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        let settings = ["targetLanguage", "replyTextSize", "engine", "baseURL", "aiModel"].map { ($0, UserDefaults.standard.object(forKey: $0)) }
        defer { for (key, value) in settings { UserDefaults.standard.set(value, forKey: key) } }
        UserDefaults.standard.set("en", forKey: "targetLanguage")
        UserDefaults.standard.removeObject(forKey: "replyTextSize")
        let model = TranslatorModel(permissionCheck: { true }, applePreparationTimeout: .milliseconds(20))
        defer { model.cancel(); model.stopPermissionMonitoring() }
        precondition(model.replyTextSize == .medium && model.replyTextSize.rawValue == 14)
        model.replyTextSize = .large
        model.engine = "apple"
        model.input = "保留中文草稿"
        model.history = [.init(id: "old", isUser: false, chinese: "中文回复", foreign: "Existing reply.", language: .english)]
        for language in TranslationLanguage.allCases {
            model.language = language
            precondition(UserDefaults.standard.string(forKey: "targetLanguage") == language.rawValue)
            precondition(model.input == "保留中文草稿" && model.history.first?.language == .english)
        }
        print("PASS: language choice persists while preserving the Chinese draft and old message language")
        model.output = "Previous translation"
        model.language = .german
        precondition(model.output.isEmpty && model.configuration == nil && !model.hasTarget)
        print("PASS: changing language clears stale output without capturing or sending")
        model.begin(insert: false)
        precondition(model.busy && model.history.last?.language == .german)
        try await waitUntil { !model.busy }
        precondition(!model.busy && model.isError && model.configuration == nil && model.input == "保留中文草稿")
        print("PASS: a missing system translation callback ends waiting and preserves the draft")
        model.begin(insert: false)
        model.cancel()
        let status = model.status
        try await Task.sleep(for: .milliseconds(70))
        precondition(!model.busy && model.status == status)
        print("PASS: cancellation retires the preparation timer without a late error")
        model.input = String(repeating: "中", count: 10_001)
        let historyCount = model.history.count
        model.begin(insert: false)
        precondition(!model.busy && model.isError && model.history.count == historyCount && model.input.count == 10_001)
        print("PASS: oversized input preserves every character and never starts a translation or send")
        model.input = "缩短后的中文"
        precondition(!model.isError && model.status.contains("符合要求"))
        print("PASS: shortening the draft clears the limit warning")
        model.replies.watching = true
        try model.saveSettings(key: "", replaceKey: false)
        precondition(model.replies.watching)
        print("PASS: saving translation settings preserves continuous reading and retires old translation jobs")
        var observed = 0
        model.replies.onReplyObserved = { observed += 1 }
        let large = ReplyCandidate(ordinal: 2, text: String(repeating: "A", count: 50_001))
        model.replies.reportReplyObserved(large); model.replies.reportReplyObserved(large)
        model.replies.reportReplyObserved(.init(ordinal: 2, text: large.text + "B"))
        precondition(observed == 2)
        model.replies.stop()
        model.replies.reportReplyObserved(large)
        precondition(observed == 3)
        print("PASS: acquired replies refresh usage once per version even when oversized; a new binding refreshes again")
        model.history = []
        let raw = "Run after saving:\n\nprintf 'KEEP_SETTINGS'\n\nComplete ending."
        model.recordReplyOriginal(id: "reply", foreign: raw, language: .english)
        precondition(model.history.count == 1 && model.history[0].foreign == raw && model.history[0].chinese.isEmpty)
        precondition(model.chatScrollTarget == "reply" && model.chatScrollAtTop)
        print("PASS: a complete original reply is visible before Chinese translation starts")
        model.recordReply(id: "reply", foreign: raw, chinese: "保存后运行。", language: .english)
        precondition(model.history.count == 1 && model.history[0].foreign == raw && model.history[0].chinese == "保存后运行。")
        precondition(model.chatScrollTarget == "reply" && model.chatScrollAtTop)
        model.recordReplyOriginal(id: "reply", foreign: raw, language: .english)
        precondition(model.history.count == 1 && model.history[0].chinese == "保存后运行。")
        print("PASS: successful translation updates the same bubble; identical originals do not erase it")
        model.recordReplyOriginal(id: "reply", foreign: raw + "\nNew ending.", language: .english)
        precondition(model.history.count == 1 && model.history[0].chinese.isEmpty && model.history[0].foreign.hasSuffix("New ending."))
        model.replies.cancelTranslation(); model.replies.stop(clear: true)
        precondition(model.history.count == 1 && model.history[0].foreign.hasSuffix("New ending."))
        print("PASS: revised replies retire stale Chinese; cancellation and stopping preserve the complete original")
        model.replies.watching = true
        for _ in 0..<13 { model.replies.handleReadFailure(ReplyReadPending(message: "正文尚未就绪")) }
        precondition(model.replies.watching && model.replies.status.contains("继续检查"))
        print("PASS: repeated pending snapshots keep automatic reply monitoring alive")
        for _ in 0..<5 { model.replies.handleReadFailure(BridgeError.message("检测到切换会话")) }
        precondition(!model.replies.watching && model.replies.status.contains("切换会话"))
        precondition(model.history[0].foreign.hasSuffix("New ending."))
        print("PASS: persistent unsafe reads still stop monitoring and preserve acquired originals")
        model.replies.watching = true
        model.cancel()
        precondition(model.replies.watching, "Cancelling Chinese input must not stop continuous Claude reading")
        model.clearHistory()
        precondition(model.replies.watching && model.chatScrollTarget == "bottom" && !model.chatScrollAtTop)
        print("PASS: cancelling a send and clearing local chat preserve continuous reading")
        for number in 1...12 {
            model.recordReply(id: "saved-\(number)", foreign: "Reply \(number)", chinese: "译文 \(number)", language: .english)
        }
        precondition(model.history.filter { !$0.isUser && !$0.chinese.isEmpty }.count == 10)
        precondition(model.history.first?.id == "saved-3" && model.history.last?.id == "saved-12")
        model.recordReply(id: "saved-3", foreign: "Reply 3", chinese: "再次翻译", language: .english)
        precondition(model.history.count == 10 && model.history.last?.id == "saved-3")
        model.input = "清除记录时保留草稿"
        model.clearHistory()
        precondition(model.history.isEmpty && model.replies.watching && model.input == "清除记录时保留草稿")
        print("PASS: only the latest ten completed reply translations are retained; clear preserves reading and drafts")
        try await streamingTests()
        let fresh = TranslatorModel(permissionCheck: { true })
        precondition(fresh.history.isEmpty && fresh.language == .german && fresh.replyTextSize == .large)
        fresh.stopPermissionMonitoring()
        print("PASS: a new application restores language and font size but has no persisted chat records")
        print("26 multilingual model tests passed")
    }

    @MainActor static func streamingTests() async throws {
        let item = TargetBridge.privateItem("secret draft")
        precondition(item.string(forType: .string) == "secret draft" && item.types.contains(TargetBridge.transientType) && item.types.contains(TargetBridge.concealedType))
        print("PASS: pasted translations carry transient and concealed clipboard markers")

        let model = TranslatorModel(permissionCheck: { true })
        defer { model.stopPermissionMonitoring() }
        let replies = model.replies
        var preferAI = false
        var aiCalls = 0
        replies.translatorFactory = {
            FailoverTranslator(preferAI: preferAI, aiTimeout: { _ in .seconds(2) },
                               ai: { text, _ in
                                   aiCalls += 1
                                   if text.contains("LIMIT") { throw AIError.http(status: 429, retryAfter: nil) }
                                   return String(repeating: "译", count: max(2, text.count / 3))
                               },
                               system: { text, _ in try await Task.sleep(for: .milliseconds(text.hasPrefix("First") ? 40 : 5)); return "〔" + text + "〕" })
        }
        var usageRefreshes = 0
        replies.onReplyObserved = { usageRefreshes += 1 }
        let url = "https://claude.ai/chat/stream-e2e"
        let user = ChatMessage(ordinal: 1, author: .user, text: "Explain")
        func snapshot(_ text: String, complete: Bool, conversation: String = url, composer: Bool = true) -> ReplySnapshot {
            ReplySnapshot(conversation: conversation, messages: [user, .init(ordinal: 2, author: .assistant, text: text)],
                          foundTranscript: true, responseComplete: complete, foundComposer: composer)
        }
        replies.watching = true
        try replies.process(ReplySnapshot(conversation: url, messages: [user], foundTranscript: true, responseComplete: false))
        let full = "First sentence arrives quickly here. Second sentence follows right after. Third one finishes the reply."
        var sawPartial = false, sawStreamingOriginal = false
        for step in stride(from: 8, to: full.count, by: 6) {
            try replies.process(snapshot(String(full.prefix(step)), complete: false))
            for _ in 0..<5 { await Task.yield() }
            try await Task.sleep(for: .milliseconds(15))
            if let bubble = model.history.last, bubble.streaming {
                sawStreamingOriginal = sawStreamingOriginal || bubble.foreign == String(full.prefix(step))
                sawPartial = sawPartial || bubble.chinese.hasPrefix("〔First sentence arrives quickly here.〕")
            }
        }
        precondition(sawStreamingOriginal && sawPartial && replies.translating)
        print("PASS: the original and the first translated sentence appear while Claude is still writing")
        try replies.process(snapshot(full, complete: true))
        try await waitUntil { model.history.last?.streaming == false }
        let expected = "〔First sentence arrives quickly here.〕 〔Second sentence follows right after.〕 〔Third one finishes the reply.〕"
        precondition(model.history.last?.chinese == expected && model.history.last?.foreign == full && !replies.translating)
        precondition(model.history.filter { !$0.isUser }.count == 1 && usageRefreshes == 1)
        print("PASS: the finished reply is assembled in source order in the same bubble, refreshing usage once")

        let url2 = "https://claude.ai/chat/stream-cancel"
        try replies.process(ReplySnapshot(conversation: url2, messages: [user], foundTranscript: true, responseComplete: false))
        try replies.process(snapshot("First sentence arrives quickly here. Second", complete: false, conversation: url2))
        replies.cancelTranslation()
        precondition(!replies.translating && model.history.last?.streaming == false && model.history.last?.chinese.isEmpty == true)
        try replies.process(snapshot("First sentence arrives quickly here. Second sentence is done.", complete: true, conversation: url2))
        try await Task.sleep(for: .milliseconds(80))
        precondition(!replies.translating && model.history.last?.chinese.isEmpty == true && model.history.last?.foreign.hasSuffix("done.") == true && replies.canRetry)
        print("PASS: a cancelled reply stays cancelled while Claude keeps writing, and keeps its latest original")
        replies.retry()
        try await waitUntil { model.history.last?.streaming == false && model.history.last?.chinese.isEmpty == false }
        precondition(model.history.last?.chinese == "〔First sentence arrives quickly here.〕 〔Second sentence is done.〕")
        print("PASS: retry translates the complete current text")

        preferAI = true
        let url3 = "https://claude.ai/chat/stream-fallback"
        try replies.process(ReplySnapshot(conversation: url3, messages: [user], foundTranscript: true, responseComplete: false))
        try replies.process(snapshot("This opening sentence is translated by AI. This LIMIT sentence is rate limited by AI. The closing sentence uses AI again.", complete: true, conversation: url3))
        try await waitUntil { model.history.last?.streaming == false && model.history.last?.chinese.isEmpty == false }
        let mixed = model.history.last?.chinese ?? ""
        precondition(mixed.hasPrefix("译") && mixed.contains("〔This LIMIT sentence is rate limited by AI.〕") && mixed.hasSuffix("译"))
        precondition(replies.fallbackNotice == FallbackReason.rateLimited.message && replies.status.contains("已改用系统翻译") && aiCalls == 3)
        print("PASS: a rate-limited segment falls back to system translation in place and the fallback is shown")

        var clock = Date(timeIntervalSince1970: 0)
        replies.now = { clock }
        replies.structureTimeout = 45
        let structural = ReplyReadPending(message: "未识别到 Claude 消息标记。", structural: true)
        replies.handleReadFailure(structural)
        precondition(replies.readError == nil && replies.status.contains("等待 Claude 界面就绪"))
        clock += 30
        replies.handleReadFailure(ReplyReadPending(message: "正文尚未就绪"))
        replies.handleReadFailure(structural)
        precondition(replies.readError == nil)
        clock += 16
        replies.handleReadFailure(structural)
        precondition(replies.readError == .uiStructureChanged("未识别到 Claude 消息标记。") && replies.status.contains("界面结构已变化") && replies.watching)
        print("PASS: structure failures lasting 45 seconds escalate to a visible interface-change error without stopping")
        try replies.process(snapshot("Recovered reply text is here.", complete: true, conversation: url3))
        precondition(replies.readError == nil && !replies.status.contains("界面结构已变化"))
        print("PASS: a readable snapshot clears the interface-change error")
        try replies.process(snapshot("Recovered reply text is here.", complete: true, conversation: url3, composer: false))
        clock += 46
        try replies.process(snapshot("Recovered reply text is here.", complete: true, conversation: url3, composer: false))
        precondition(replies.readError == .uiStructureChanged("未找到 Claude 输入框"))
        print("PASS: a composer that stays missing escalates the same way")
        replies.stop()
        precondition(replies.readError == nil)
        print("PASS: stopping clears the escalation state")
    }

    @MainActor static func waitUntil(_ condition: () -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(5))
        while !condition() {
            precondition(clock.now < deadline, "Model state did not settle")
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
