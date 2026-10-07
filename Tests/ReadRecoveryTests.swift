import Foundation
import AppKit

@main struct ReadRecoveryTests {
    @MainActor static func settle(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !condition() {
            precondition(ContinuousClock.now < deadline)
            try await Task.sleep(for: .milliseconds(5))
        }
    }
    @MainActor static func main() async throws {
        let monitor = ReplyMonitor()
        var translations = 0
        monitor.testTranslation = { _ in translations += 1; return "已保存的中文。" }
        monitor.watching = true
        let snapshot = ReplySnapshot(conversation: "https://claude.ai/chat/synthetic-recovery",
                                     messages: [.init(ordinal: 2, author: .assistant, text: "A complete synthetic answer.")],
                                     foundTranscript: true, responseComplete: true)
        monitor.ingest(snapshot, now: 0)
        try await settle { monitor.chinese == "已保存的中文。" && !monitor.translating }
        let completed = monitor.status
        for _ in 0..<7 { monitor.handleReadFailure(ReplyReadPending(message: "正在等待当前窗口的 Claude 对话页面。")) }
        monitor.ingest(snapshot, now: 10)
        precondition(monitor.watching && monitor.status == completed && translations == 1,
                     "returning to an unchanged cached reply must clear the stale waiting display without retranslating")
        print("PASS: successful unchanged capture restores the prior translation status without another request")

        monitor.status = "翻译失败：本机合成失败；已有中文保留，可重试。"
        let failed = monitor.status
        monitor.handleReadFailure(ReplyReadPending(message: "临时不可读取。"))
        monitor.ingest(snapshot, now: 11)
        precondition(monitor.status == failed && translations == 1)
        print("PASS: recovery preserves an existing translation failure instead of falsely claiming success")

        monitor.handleReadFailure(ReplyReadPending(message: "临时不可读取。"))
        monitor.status = "部分片段翻译失败：新的本机合成状态。"
        monitor.ingest(snapshot, now: 12)
        precondition(monitor.status == "部分片段翻译失败：新的本机合成状态。" && translations == 1)
        monitor.stop(clear: true)
        print("PASS: a newer translation state survives capture recovery; teardown retires the transient state")
        _ = NSApplication.shared
        let model = TranslatorModel(permissionCheck: { true }, remoteKeyRead: { _ in "" })
        defer { model.replies.stop(); model.stopPermissionMonitoring() }
        var failedCalls = 0
        model.replies.testTranslation = { _ in
            failedCalls += 1
            throw BridgeError.message("synthetic offline failure")
        }
        model.replies.watching = true
        model.replies.ingest(snapshot, now: 20)
        try await settle { model.replies.canRetry }
        precondition(model.history.count == 1 && model.history[0].foreign == snapshot.messages[0].text && model.history[0].chinese.isEmpty)
        print("PASS: a failed reverse translation leaves the acquired original visible")
        model.clearHistory()
        model.replies.stop()
        model.replies.watching = true
        model.replies.ingest(snapshot, now: 21)
        for _ in 0..<20 { await Task.yield() }
        precondition(failedCalls == 1 && model.history.isEmpty && !model.replies.translating,
                     "cleared replies must remain retired after restarting the pipeline; invisible translations must not run")
        print("PASS: restarting reading does not translate cleared records behind an empty page")
        let next = ReplySnapshot(conversation: snapshot.conversation,
                                 messages: snapshot.messages + [.init(ordinal: 4, author: .assistant, text: "A new complete synthetic reply.")],
                                 foundTranscript: true, responseComplete: true)
        model.replies.ingest(next, now: 22)
        try await settle { failedCalls == 2 && model.replies.canRetry }
        precondition(model.history.count == 1 && model.history[0].foreign == next.messages[1].text)
        let work = ReplyWork(candidate: .init(ordinal: 2, text: snapshot.messages[0].text), conversation: snapshot.conversation, manual: true)
        model.replies.historyChoices = [work]
        model.replies.selectHistoryReply(work)
        try await settle { failedCalls == 3 && !model.replies.translating }
        precondition(model.history.count == 2 && model.history.last?.foreign == snapshot.messages[0].text)
        print("PASS: new originals remain visible and explicitly selected cleared history can be restored")
        print("6 read recovery contracts passed")
    }
}
