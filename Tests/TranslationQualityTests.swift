import Foundation
import AppKit

@main struct TranslationQualityTests {
    static var count = 0, failures = 0
    @MainActor static func check(_ value: Bool, _ name: String) {
        count += 1
        if value { print("PASS: " + name) } else { failures += 1; print("FAIL: " + name) }
    }
    @MainActor static func rejected(_ source: String, _ candidate: String, target: TranslationTarget, context: String? = nil) async -> Bool {
        do {
            _ = try await TranslationFidelity.$target.withValue(target) {
                try await TranslationContext.$source.withValue(context) {
                    try await TextTranslation.run(source) { _ in candidate }
                }
            }
            return false
        } catch { return error is TranslationFidelityError }
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
        check(await rejected("不要删除文件。", "Delete the files.", target: .foreign(.english)), "clear negative commands cannot become positive commands")
        check(await rejected("是否可行？", "Yes, it is feasible.", target: .foreign(.english), context: "Neighbouring table data"), "table context does not permit answering a source question")
        check(await rejected("Is the design valid?", "是的，这个设计有效。", target: .chinese), "a reverse question translation cannot become a Chinese answer")
        for (language, candidate) in [(TranslationLanguage.english, "Do not delete the files."), (.german, "Löschen Sie die Dateien nicht."), (.japanese, "ファイルを削除しないでください。"), (.korean, "파일을 삭제하지 마세요.")] {
            check(!(await rejected("不要删除文件。", candidate, target: .foreign(language))), "a faithful negative command remains valid in " + language.rawValue)
        }
        check(await rejected("Do not open the notebook.", "打开笔记本。", target: .chinese), "word-internal not in notebook cannot satisfy a negation contract")
        check(!(await rejected("The estimate is about 50%.", "估计值约50%。", target: .chinese)), "numbers attached to Chinese prose remain valid")
        check(!(await rejected("负零点三", "-0.3", target: .foreign(.english))), "spelled Chinese numbers may use numeric notation")
        let mixed = "你能解释 `config.json` 吗？"
        let assembled = try await TranslationFidelity.$target.withValue(.foreign(.english)) {
            try await TextTranslation.runProtected(mixed) { source in source.contains("解释") ? "Can you explain" : "?" }
        }
        check(assembled.contains("`config.json`") && assembled.hasSuffix("?"), "a question split by protected code is checked as one assembled request")

        let model = TranslatorModel(permissionCheck: { true }, remoteKeyRead: { _ in "synthetic-gemini-key" })
        defer { model.cancel(); model.replies.stop(); model.stopPermissionMonitoring() }
        model.engine = "gemini"; model.language = .english
        var fallbackCalls = 0
        model.testFallback = { _ in fallbackCalls += 1; return "Please retain the existing settings." }
        let unsolicited = "Please retain the existing settings. They are already optimal."
        model.testTranslation = { _ in unsolicited }; model.input = "请保留原有设置。"
        model.begin(insert: false); try await settle(model)
        check(model.output == unsolicited && model.status.contains("核对") && model.status.contains("未自动"), "a short added assertion remains visible for review and cannot trigger automatic delivery")
        check(fallbackCalls == 0, "an uncertain result does not force another translation request")
        model.testTranslation = { _ in "Delete the files." }; model.testFallback = { _ in "Delete the files." }
        model.input = "不要删除文件。"; model.begin(insert: false); try await settle(model)
        check(model.isError && model.output.isEmpty && model.input == "不要删除文件。", "two semantically conflicting routes preserve the draft without publishing a usable result")
        model.testTranslation = { _ in "Please run 30 times." }; model.testFallback = { _ in "Please run 30 times." }
        model.input = "请运行20次。"; model.begin(insert: false); try await settle(model)
        check(model.isError && model.output.isEmpty, "changed source numbers prevent use of the assembled translation")
        model.testTranslation = { _ in "Explain config.json" }; model.testFallback = { _ in "Explain config.json" }
        model.input = "请解释 `config.json`。"; model.begin(insert: false); try await settle(model)
        check(model.isError && model.output.isEmpty, "invented duplicate filenames cannot pass reassembly")

        let pipeline = ReplyPipeline(incremental: false) { _ in "这个值是稳定的。它已经通过验证。" }
        var incoming = "", status = ""
        pipeline.onTranslation = { _, _, text, _ in incoming = text }
        pipeline.onStatus = { text, _ in status = text }
        pipeline.observe(conversation: "quality", messages: [.init(ordinal: 2, author: .assistant, text: "The value is stable.")], responseComplete: true, now: 0)
        let end = ContinuousClock.now.advanced(by: .seconds(3))
        while pipeline.busy, ContinuousClock.now < end { try await Task.sleep(for: .milliseconds(2)) }
        check(!incoming.isEmpty && status.contains("核对"), "uncertain incoming Chinese is visible with a review notice instead of stopping source acquisition")
        pipeline.cancel()

        let recovery = ReplyMonitor(); recovery.watching = true
        recovery.testTranslation = { _ in "已有中文。" }
        for _ in 0..<40 { recovery.handleReadFailure(BridgeError.message("Synthetic temporary AX error")) }
        check(recovery.watching, "temporary capture failures keep monitoring recoverable beyond five attempts")
        recovery.ingest(.init(conversation: "https://claude.ai/chat/recovery", messages: [.init(ordinal: 2, author: .assistant, text: "Recovered reply.")], foundTranscript: true, responseComplete: true))
        check(recovery.watching, "a successful snapshot resumes normal reading")
        recovery.stop(); recovery.handleReadFailure(BridgeError.message("Synthetic late error"))
        check(!recovery.watching, "late capture errors never restart explicitly stopped reading")
        print("\(count) translation quality checks; \(failures) failed")
        if failures > 0 { exit(1) }
    }
}
