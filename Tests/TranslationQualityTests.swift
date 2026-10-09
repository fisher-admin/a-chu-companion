import Foundation
import AppKit

// Provider output is no longer subject to a second semantic quality gate.
@main struct TranslationQualityTests {
    static var count = 0, failures = 0
    @MainActor static func check(_ value: Bool, _ name: String) {
        count += 1
        if value { print("PASS: " + name) } else { failures += 1; print("FAIL: " + name) }
    }
    @MainActor static func settle(_ model: TranslatorModel) async throws {
        let end = ContinuousClock.now.advanced(by: .seconds(3))
        while model.busy, ContinuousClock.now < end { try await Task.sleep(for: .milliseconds(2)) }
        check(!model.busy, "synthetic translation reaches its bounded completion")
    }
    @MainActor static func main() async throws {
        setvbuf(stdout, nil, _IONBF, 0); _ = NSApplication.shared
        let savedLanguage = CompanionPreferences.store.object(forKey: "targetLanguage")
        defer { CompanionPreferences.store.set(savedLanguage, forKey: "targetLanguage") }
        let candidates = [
            ("结果可靠吗？", "The result is reliable."),
            ("不要删除文件。", "Delete the files."),
            ("请运行20次。", "Please run 30 times."),
            ("请保留原有设置。", "请保留原有设置。"),
            ("训练折内。", "Within the training discount."),
            ("请解释。", String(repeating: "A longer provider translation. ", count: 20).trimmingCharacters(in: .whitespaces)),
            ("请保留。", "Please retain it. This is another sentence.")
        ]
        for (source, candidate) in candidates {
            do {
                let result = try await TextTranslation.run(source) { _ in candidate }
                check(result == candidate, "provider output passes without a semantic quality gate")
            } catch { check(false, "provider output passes without a semantic quality gate") }
        }
        do {
            let candidate = String(repeating: "Expanded cell text. ", count: 10).trimmingCharacters(in: .whitespaces)
            let result = try await TranslationContext.$source.withValue("Neighbouring table text") {
                try await TextTranslation.run("Label") { _ in candidate }
            }
            check(result == candidate, "table cell length does not trigger a translation quality rejection")
        } catch { check(false, "table cell length does not trigger a translation quality rejection") }

        let model = TranslatorModel(permissionCheck: { true }, remoteKeyRead: { _ in "synthetic-key" })
        defer { model.cancel(); model.replies.stop(); model.stopPermissionMonitoring() }
        model.engine = "gemini"; model.language = .english
        var fallbackCalls = 0
        model.testFallback = { _ in fallbackCalls += 1; return "Fallback." }
        for (source, candidate) in candidates {
            model.testTranslation = { _ in candidate }; model.input = source
            model.begin(insert: false); try await settle(model)
            check(model.output == candidate && !model.isError && !model.status.contains("核对"), "completed provider output has no review notice")
        }
        check(fallbackCalls == 0, "quality differences never request a second translation")
        model.testTranslation = { _ in throw BridgeError.message("Gemini 翻译服务返回 503。") }
        model.testFallback = { _ in "Please run 30 times." }; model.input = "请运行20次。"
        model.begin(insert: false); try await settle(model)
        check(model.output == "Please run 30 times." && !model.isError && model.status.contains("系统翻译"), "a real service failure still uses system translation without quality review")
        model.testTranslation = { _ in "  " }; model.testFallback = { _ in "  " }; model.input = "保留草稿"
        model.begin(insert: false); try await settle(model)
        check(model.isError && model.input == "保留草稿" && model.output.isEmpty, "empty service results preserve the draft")

        let pipeline = ReplyPipeline(incremental: false) { _ in "这个值是稳定的。它已经通过验证。" }
        var incoming = "", status = "", replyFallbackCalls = 0
        pipeline.fallback = { _ in replyFallbackCalls += 1; return "备用译文。" }
        pipeline.onTranslation = { _, _, text, _ in incoming = text }
        pipeline.onStatus = { text, _ in status = text }
        pipeline.observe(conversation: "quality", messages: [.init(ordinal: 2, author: .assistant, text: "The value is stable.")], responseComplete: true, now: 0)
        let end = ContinuousClock.now.advanced(by: .seconds(3))
        while pipeline.busy, ContinuousClock.now < end { try await Task.sleep(for: .milliseconds(2)) }
        check(incoming == "这个值是稳定的。它已经通过验证。" && !status.contains("核对") && replyFallbackCalls == 0, "incoming translations are displayed without a semantic review notice")
        pipeline.cancel()

        var recoveryCalls = 0
        do {
            let result = try await SystemTranslationProtection.translate("Ask Gemini now.", toChinese: true) { _ in
                recoveryCalls += 1; return "现在问问双子座。"
            }
            check(result == "现在问问双子座。" && recoveryCalls == 2, "plain system recovery is not rejected by a literal quality gate")
        } catch { check(false, "plain system recovery is not rejected by a literal quality gate") }
        print("\(count) translation quality removal checks; \(failures) failed")
        if failures > 0 { exit(1) }
    }
}
