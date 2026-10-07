import Foundation
import AppKit
import Network

final class FetchCounter: @unchecked Sendable {
    let lock = NSLock(); var loads = 0; var fetches = 0
    func load() -> ClaudeSession {
        lock.withLock { loads += 1 }
        return .init(key: "sk-ant-sid01-fixtureonlyabcdefghijklmnop", organization: "12345678-1234-1234-1234-123456789abc", fingerprint: "one")
    }
    func fetch() -> (ClaudeUsageSnapshot, ClaudePlan) {
        lock.withLock { fetches += 1 }
        return (.init(fiveHour: .init(usedPercentage: 12, resetsAt: nil), sevenDay: .init(usedPercentage: 34, resetsAt: nil), observedAt: Date()), .pro)
    }
    var counts: (Int, Int) { lock.withLock { (loads, fetches) } }
}

@main struct FidelityFallbackTests {
    nonisolated(unsafe) static var count = 0
    static func check(_ value: Bool, _ name: String) {
        precondition(value, name); count += 1; print("PASS: \(name)")
    }
    @MainActor static func rejected(_ source: String, _ output: String, _ target: TranslationTarget?) async -> Bool {
        do {
            _ = try await TranslationFidelity.$target.withValue(target) { try await TextTranslation.run(source) { _ in output } }
            return false
        } catch { return error is TranslationFidelityError }
    }
    @MainActor static func accepted(_ source: String, _ output: String, _ target: TranslationTarget?) async -> Bool {
        (try? await TranslationFidelity.$target.withValue(target) { try await TextTranslation.run(source) { _ in output } }) != nil
    }

    // Reconstructed from the build58 live failure (the sent text itself was
    // not retained): a faithful request followed by an unsolicited answer.
    static let question = "请研究全样本特征筛选与嵌套交叉验证的评估偏差。用合成的纯噪声二分类数据比较：先用全样本选特征再交叉验证；以及每个训练折内部选特征再评估。分阶段说明设计、计算结果和解释，用小表格比较，保留数值与代码。先说明设计，再计算，最后给出局限；不要访问个人文件，不要联网。"
    static let english = "Please investigate the evaluation bias of full-sample feature selection versus nested cross-validation. Using synthetic pure-noise binary classification data, compare: first selecting features on the full sample and then cross-validating; and selecting features inside each training fold before evaluating. Explain the design, computed results and interpretation in stages, compare them in a small table, and keep the numbers and code. First explain the design, then compute, and finally state the limitations; do not access personal files and do not go online."
    static let german = "Bitte untersuchen Sie die Bewertungsverzerrung durch Merkmalsauswahl auf der gesamten Stichprobe im Vergleich zur verschachtelten Kreuzvalidierung. Vergleichen Sie mit synthetischen, rein zufälligen binären Klassifikationsdaten: zuerst Merkmale auf der gesamten Stichprobe auswählen und dann kreuzvalidieren; sowie Merkmale innerhalb jeder Trainingsfalte auswählen und anschließend bewerten. Erläutern Sie Design, Rechenergebnisse und Interpretation schrittweise, vergleichen Sie diese in einer kleinen Tabelle und behalten Sie Zahlen und Code bei. Erläutern Sie zuerst das Design, rechnen Sie dann und nennen Sie zuletzt die Grenzen; greifen Sie nicht auf persönliche Dateien zu und gehen Sie nicht online."
    static let japanese = "全サンプルでの特徴量選択とネスト化交差検証の評価バイアスを研究してください。合成した純粋なノイズの二値分類データを用いて、全サンプルで特徴量を選択してから交差検証する方法と、各訓練フォールド内で特徴量を選択してから評価する方法を比較してください。設計、計算結果、解釈を段階的に説明し、小さな表で比較し、数値とコードを残してください。まず設計を説明し、次に計算し、最後に限界を述べてください。個人ファイルにはアクセスせず、インターネットにも接続しないでください。"
    static let korean = "전체 표본 특성 선택과 중첩 교차 검증의 평가 편향을 연구해 주세요. 합성된 순수 잡음 이진 분류 데이터를 사용하여 다음을 비교하세요: 먼저 전체 표본으로 특성을 선택한 후 교차 검증하는 방법, 그리고 각 훈련 폴드 내부에서 특성을 선택한 후 평가하는 방법. 설계, 계산 결과 및 해석을 단계별로 설명하고, 작은 표로 비교하며, 수치와 코드를 유지하세요. 먼저 설계를 설명하고, 그다음 계산하고, 마지막으로 한계를 제시하세요. 개인 파일에 접근하지 말고 인터넷에 연결하지 마세요."
    static let answer = "If the underlying data is pure noise, global selection will pick features that happen to correlate with the noise in the test set, creating an illusion of predictive power that does not exist. Nested cross-validation avoids this because selection is repeated inside each training fold, so its estimate stays near chance."

    @MainActor static func main() async throws {
        setvbuf(stdout, nil, _IONBF, 0)
        _ = NSApplication.shared
        let en = TranslationTarget.foreign(.english), de = TranslationTarget.foreign(.german)

        // Observed failure shapes are refused before any insertion or display.
        check(await rejected(question, english + "\n\n" + answer, en), "an answer paragraph appended to a translated research request is refused")
        check(await rejected(question, english + " " + answer, en), "an answer appended in the same paragraph is refused rather than flattened into the request")
        check(await rejected(question, german + "\n\n" + answer, de), "German output with an appended answer is refused despite the larger German allowance")
        check(await rejected("请用表格比较两种流程。", "Please compare the two processes using a table.\n\n| Process | Bias |\n| --- | --- |\n| Global | High |", en), "a requested table is not invented by the translator")
        check(await rejected("请说明结论。", "Please state the conclusion.\n\n## Conclusion\nLeakage inflates accuracy.", en), "an added heading is refused")
        check(await rejected("请列出风险。", "Please list the risks.\n- Leakage\n- Overfitting", en), "an added list is refused")
        check(await rejected("这个设计有效吗？", "Is this design valid? No. It leaks test information into feature selection.", en), "an English answer to a source question is refused")
        check(await rejected("这个设计有效吗？", "Ist dieses Design gültig? Nein, es ist ungültig.", de), "a German answer to a source question is refused")
        check(await rejected("请解释实验设计。", "Please explain the experimental design. The design compares two pipelines on pure-noise data and shows that global selection leaks.", en), "a short request followed by its answer is refused")
        check(await rejected("The estimate is optimistic.", "这个估计是乐观的。\n\n解释：因为测试数据参与了特征筛选，所以准确率被高估，这种偏差在纯噪声数据上尤为明显，需要嵌套交叉验证才能避免。", .chinese), "a reply translation that adds its own explanation is refused")

        // Faithful translations and ordinary length differences remain accepted.
        check(await accepted(question, english, en), "a faithful long English request is accepted")
        check(await accepted(question, german, de), "a faithful long German request is accepted")
        check(await accepted(question, japanese, .foreign(.japanese)), "a faithful Japanese request is accepted")
        check(await accepted(question, korean, .foreign(.korean)), "a faithful Korean request is accepted")
        check(await accepted("请检查。", "Bitte überprüfen Sie das.", de), "short German expansion is accepted")
        check(await accepted("请保留原有设置。", "Bitte behalten Sie die bestehenden Einstellungen bei.", de), "a normal German sentence expansion is accepted")
        check(await accepted("画蛇添足。", "That is gilding the lily; the extra detail spoils it.", en), "an idiom rendered by meaning is accepted")
        check(await accepted("这个设计有效吗？", "Is this design valid?", en), "a question translated as a question is accepted")
        check(await accepted("这个设计有效吗？", "この設計は有効ですか。", .foreign(.japanese)), "a Japanese question without a question mark is not refused")
        check(await accepted("这个结果不是无偏估计，我们还没有做实验。", "This result is not an unbiased estimate; we have not run the experiment yet.", en), "negation and a not-yet-conducted statement pass unchanged")
        check(await accepted("步骤：\n1、生成数据\n2、选择特征", "Steps:\n1. Generate data\n2. Select features", en), "a source list may become a Markdown list")
        check(await accepted("The design is invalid. In pure-noise data the true accuracy is chance (about 50%).", "这个设计是无效的。在纯噪声数据中，真实准确率只是随机水平（约50%）。", .chinese), "a faithful reply translation is accepted")
        check(await accepted("Keep this sentence.", "KEEP THIS SENTENCE.", nil), "unknown-direction identity output is accepted")
        check(TranslationFidelity.weightedLength("中文") == 6 && TranslationFidelity.weightedLength("a  b") == 3, "script weighting counts Han characters and whitespace runs as calibrated")

        // Reply reading: a failed or suspicious slice uses the local fallback.
        var status = ""; var chinese = ""; var fallbackCalls = 0
        let pipeline = ReplyPipeline(incremental: false) { _ in throw BridgeError.message("Gemini 翻译服务返回 503。服务暂时不可用，请稍后重试。") }
        pipeline.fallback = { _ in fallbackCalls += 1; return "系统中文。" }
        pipeline.onStatus = { message, _ in status = message }
        pipeline.onTranslation = { _, _, value, _ in chinese = value }
        pipeline.observe(conversation: "fallback", messages: [.init(ordinal: 2, author: .assistant, text: "A stable reply.")], responseComplete: true, now: 0)
        while pipeline.busy { try await Task.sleep(for: .milliseconds(5)) }
        check(chinese == "系统中文。" && fallbackCalls == 1 && status.contains("系统翻译") && status.contains("503") && !pipeline.hasFailures,
              "a 503 reply slice is translated by the system fallback and the reason stays visible")
        let suspicious = ReplyPipeline(incremental: false) { _ in "这个估计是乐观的。\n\n解释：" + String(repeating: "因为测试数据参与了特征筛选所以被高估。", count: 6) }
        var suspiciousChinese = ""
        suspicious.fallback = { _ in "这个估计是乐观的。" }
        suspicious.onTranslation = { _, _, value, _ in suspiciousChinese = value }
        suspicious.observe(conversation: "suspicious", messages: [.init(ordinal: 2, author: .assistant, text: "The estimate is optimistic.")], responseComplete: true, now: 0)
        while suspicious.busy { try await Task.sleep(for: .milliseconds(5)) }
        check(suspiciousChinese == "这个估计是乐观的。", "a reply translation with an added explanation is replaced by the fallback")
        var noFallbackChinese = ""
        let plain = ReplyPipeline(incremental: false) { _ in throw BridgeError.message("服务暂时不可用") }
        plain.onTranslation = { _, _, value, _ in noFallbackChinese = value }
        plain.observe(conversation: "plain", messages: [.init(ordinal: 2, author: .assistant, text: "Reply.")], responseComplete: true, now: 0)
        while plain.busy { try await Task.sleep(for: .milliseconds(5)) }
        check(noFallbackChinese.isEmpty && plain.hasFailures, "without a fallback the failed slice remains retryable and no Chinese is invented")

        // Sending: a remote failure falls back to system translation for review only.
        let saved = ["engine", "targetLanguage", "autoSend"].map { ($0, CompanionPreferences.store.object(forKey: $0)) }
        defer { for (key, value) in saved { CompanionPreferences.store.set(value, forKey: key) } }
        CompanionPreferences.store.set("en", forKey: "targetLanguage")
        let model = TranslatorModel(permissionCheck: { true }, remoteKeyRead: { _ in "dummy-gemini-key" })
        defer { model.cancel(); model.stopPermissionMonitoring() }
        model.engine = "gemini"; model.autoSend = true
        model.testTranslation = { _ in english + "\n\n" + answer }
        var systemCalls = 0
        model.testFallback = { _ in systemCalls += 1; return english }
        model.input = question
        model.begin(insert: false)
        while model.busy { try await Task.sleep(for: .milliseconds(5)) }
        check(model.output == english && systemCalls == 1 && model.input == question && model.history.last?.foreign == english,
              "an appended Gemini answer is replaced by the system translation while the Chinese draft stays")
        check(model.status.contains("系统翻译") && model.status.contains("没有自动填入或发送") && model.status.contains("Gemini"),
              "the fallback result is shown for review and explicitly not inserted or sent")
        model.testTranslation = { _ in throw BridgeError.message("Gemini 翻译服务返回 503。服务暂时不可用，请稍后重试。") }
        model.testFallback = { _ in throw BridgeError.message("系统翻译语言尚未准备好。") }
        model.input = "请保留原有设置。"
        model.begin(insert: false)
        while model.busy { try await Task.sleep(for: .milliseconds(5)) }
        check(model.isError && model.output.isEmpty && model.input == "请保留原有设置。", "when both services fail the draft remains and nothing is produced")

        // Quota follows only a verified chat entrance.
        let suite = "achu-entrance-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "usageConnected"); defaults.set("desktop", forKey: "usageSource")
        let counter = FetchCounter()
        let usage = ClaudeUsageMonitor(settings: defaults, load: { _, _ in counter.load() }, fetch: { _ in counter.fetch() }, enabled: { defaults.bool(forKey: "usageConnected") })
        usage.awaitChatEntrance()
        usage.refresh(force: true)
        try await Task.sleep(for: .milliseconds(50))
        check(counter.counts == (0, 0) && usage.snapshot == nil && usage.awaitingEntrance, "before any chat connection no configured account is read or shown")
        usage.follow(channel: .desktop)
        for _ in 0..<200 where usage.snapshot == nil { try await Task.sleep(for: .milliseconds(5)) }
        check(usage.snapshot?.fiveHour?.usedPercentage == 12 && !usage.awaitingEntrance && usage.channel == .desktop, "connecting Claude Desktop reads the desktop entrance quota")
        usage.awaitChatEntrance("当前连接的「ChatGPT」不是 Claude 桌面版或 claude.ai，未显示额度")
        let before = counter.counts
        usage.refresh(force: true)
        try await Task.sleep(for: .milliseconds(50))
        check(usage.snapshot == nil && counter.counts == before && usage.status.contains("ChatGPT"), "a non-Claude composer hides the previous entrance quota and does not query it")
        usage.follow(channel: .cli, binding: "cli-fixture")
        check(usage.snapshot == nil && usage.channel == .cli && counter.counts == before, "a CLI entrance never borrows the desktop login")

        // Usage refreshes after every completed reply and periodically for Desktop.
        let replyCounter = FetchCounter()
        let replyUsage = ClaudeUsageMonitor(settings: defaults, load: { _, _ in replyCounter.load() }, fetch: { _ in replyCounter.fetch() }, enabled: { true })
        replyUsage.replyRefreshDelay = .milliseconds(10)
        replyUsage.follow(channel: .desktop)
        for _ in 0..<200 where replyCounter.counts.1 < 1 { try await Task.sleep(for: .milliseconds(5)) }
        replyUsage.refreshAfterReply()
        for _ in 0..<200 where replyCounter.counts.1 < 2 { try await Task.sleep(for: .milliseconds(5)) }
        replyUsage.refreshAfterReply()
        for _ in 0..<200 where replyCounter.counts.1 < 3 { try await Task.sleep(for: .milliseconds(5)) }
        check(replyCounter.counts.1 == 3, "each completed reply queries usage again even within the 60-second reuse window")
        replyUsage.follow(channel: .cli, binding: "cli-fixture")
        let cliBefore = replyCounter.counts
        replyUsage.refreshAfterReply()
        try await Task.sleep(for: .milliseconds(60))
        check(replyCounter.counts == cliBefore, "a CLI reply relies on the CLI's own report and never queries the desktop login")
        replyUsage.awaitChatEntrance()
        replyUsage.refreshAfterReply()
        try await Task.sleep(for: .milliseconds(60))
        check(replyCounter.counts == cliBefore, "no reply-triggered query happens without a connected Claude entrance")
        let periodicCounter = FetchCounter()
        let periodic = ClaudeUsageMonitor(settings: defaults, load: { _, _ in periodicCounter.load() }, fetch: { _ in periodicCounter.fetch() }, enabled: { true })
        periodic.follow(channel: .desktop)
        periodic.startPeriodicRefresh(every: .milliseconds(30))
        for _ in 0..<400 where periodicCounter.counts.1 < 3 { try await Task.sleep(for: .milliseconds(5)) }
        check(periodicCounter.counts.1 >= 3, "a connected Desktop entrance refreshes on the periodic interval")
        periodic.awaitChatEntrance()
        let stopped = periodicCounter.counts.1
        try await Task.sleep(for: .milliseconds(120))
        check(periodicCounter.counts.1 == stopped, "periodic refresh pauses while no Claude entrance is connected")

        // Completion, not streaming, triggers the reply refresh.
        let monitor = ReplyMonitor()
        var completions = 0
        monitor.onReplyCompleted = { completions += 1 }
        let conversation = "https://claude.ai/chat/synthetic-usage"
        func snapshot(_ text: String, _ complete: Bool) -> ReplySnapshot {
            .init(conversation: conversation, messages: [.init(ordinal: 1, author: .user, text: "Q"), .init(ordinal: 2, author: .assistant, text: text)], foundTranscript: true, responseComplete: complete)
        }
        monitor.testTranslation = { $0 }
        monitor.ingest(snapshot("Partial", false)); monitor.ingest(snapshot("Partial reply", false))
        monitor.ingest(snapshot("Partial reply.", true)); monitor.ingest(snapshot("Partial reply.", true))
        check(completions == 1, "streaming updates do not refresh usage; one completed reply refreshes once")
        monitor.stop()

        // System translation: names and literals are shielded and restored.
        let masked = SystemTranslationProtection.mask("Ask Gemini to run `python3 leakage_sim.py 20` in output/real-tests/cli with Claude Code.", toChinese: true)
        check(!masked.text.contains("Gemini") && !masked.text.contains("leakage_sim") && masked.text.contains("Claude Code") && masked.replacements.count == 3,
              "Gemini, inline code and relative paths are shielded; Claude Code is left to the translator")
        check(SystemTranslationProtection.restore(masked.text, masked) == "Ask Gemini to run `python3 leakage_sim.py 20` in output/real-tests/cli with Claude Code.", "placeholders restore the exact original literals")
        let outbound = SystemTranslationProtection.mask("请运行 python3 leakage_sim.py 20，引擎是 Gemini。", toChinese: false)
        check(outbound.text.contains("Gemini") && !outbound.text.contains("python3") && !outbound.text.contains("leakage_sim.py"), "outbound Chinese shields commands and files but leaves names to the translator")
        check(!SystemTranslationProtection.mask("中文/英文 对照", toChinese: false).text.contains("⟦"), "Chinese slashes are not mistaken for paths")
        var attempts: [String] = []
        let recovered = try await SystemTranslationProtection.translate("Ask Gemini now.", toChinese: true) { text in
            attempts.append(text); return text.contains("⟦") ? "现在问问双子座。" : "现在问问 Gemini。"
        }
        check(recovered == "现在问问 Gemini。" && attempts.count == 2, "a lost placeholder falls back to the unprotected translation instead of returning a broken result")
        check(SystemTranslationProtection.corrected("它不是一个不偏不倚的估计器，使用功能选择。", source: "It is not an unbiased estimator after feature selection.") == "它不是一个无偏估计量，使用特征选择。", "observed term mistranslations are corrected when the source names the term")
        check(SystemTranslationProtection.corrected("功能选择很重要。", source: "Function selection matters.") == "功能选择很重要。", "corrections never apply when the source does not contain the term")
        check(SystemTranslationProtection.corrected("不偏不倚：比较并不表明估计是不偏不倚的。", source: "Not unbiased: the comparison does not show the estimate is unbiased.") == "无偏：比较并不表明估计是无偏的。",
              "the bare statistical adjective unbiased is corrected after the longer phrases")

        // Flattened Code replies keep inline runs inside their sentence.
        let marker = ReplyNode(role: "AXGroup", label: "Message 9", children: [
            .init(role: "AXGroup", children: [.init(role: "AXHeading", label: "Claude responded: Fix")])
        ])
        let flat = ReplyNode(role: "AXGroup", label: "Message 9", children: [marker,
            .init(role: "AXStaticText", text: "The fix will make the reader "),
            .init(role: "AXStaticText", text: "skip images by default"),
            .init(role: "AXStaticText", text: " — images can't be translated anyway."),
            .init(role: "AXStaticText", text: "Protection held, and "),
            .init(role: "AXStaticText", text: "python3 leakage_sim.py 20"),
            .init(role: "AXStaticText", text: ", now intact."),
            .init(role: "AXStaticText", text: "A new paragraph starts here."),
            .init(role: "AXStaticText", text: "I'll switch it on with"),
            .init(role: "AXStaticText", text: "启用只读桥接"),
            .init(role: "AXStaticText", text: " (enable read-only bridge)."),
            .init(role: "AXStaticText", text: "Usage:"),
            .init(role: "AXStaticText", text: "the header reads 54%."),
            .init(role: "AXStaticText", text: "Two clues:"),
            .init(role: "AXStaticText", text: "First clue is here."),
            .init(role: "AXStaticText", text: "the dropped"),
            .init(role: "AXStaticText", text: "space returns."),
            .init(role: "AXStaticText", text: "How is Claude doing this session?")
        ])
        let decoded = ClaudeDecoder.codeSegments(flat, responseComplete: true).map(\.text).joined(separator: "|")
        check(decoded.contains("The fix will make the reader skip images by default — images can't be translated anyway."),
              "a bold run inside a sentence stays in that sentence instead of becoming its own paragraph")
        check(decoded.contains("Protection held, and python3 leakage_sim.py 20, now intact."), "an inline command followed by a comma stays in its sentence")
        check(decoded.contains("anyway.\nProtection held") && decoded.contains("intact.\nA new paragraph starts here."), "genuine paragraph boundaries without seam whitespace are preserved")
        check(!decoded.contains("How is Claude doing"), "the Claude app's session feedback prompt is not read as reply text")
        check(decoded.contains("I'll switch it on with 启用只读桥接 (enable read-only bridge)."), "a bold run after a dropped seam space stays in its sentence")
        check(decoded.contains("Usage: the header reads 54%."), "a bold label followed by lowercase text stays one sentence")
        check(decoded.contains("Two clues:\nFirst clue is here."), "a colon before a capitalised run keeps its line boundary")
        check(decoded.contains("the dropped space returns."), "a dropped space between two words is restored instead of gluing them")

        // A long Code turn may scroll the user anchor out of the transcript.
        typealias Piece = CodeTranscriptPiece<String>
        let streamingOnly = [Piece(element: "body", ordinal: nil, author: nil, isStreamingAssistant: true)]
        check((try? ClaudeDecoder.codeStreamingPieces(streamingOnly, continuing: 24))?.first?.ordinal == 24,
              "a sole unanchored streaming reply keeps the ordinal validated earlier in this conversation")
        check((try? ClaudeDecoder.codeStreamingPieces(streamingOnly)) == nil, "without an earlier validated ordinal it still waits")
        let anchoredAbove = [Piece(element: "assistant", ordinal: 22, author: .assistant, isStreamingAssistant: false)] + streamingOnly
        check((try? ClaudeDecoder.codeStreamingPieces(anchoredAbove, continuing: 24)) == nil, "a numbered non-user message above the streaming reply is never bridged")
        let somethingAfter = streamingOnly + [Piece(element: "next", ordinal: 25, author: .user, isStreamingAssistant: false)]
        check((try? ClaudeDecoder.codeStreamingPieces(somethingAfter, continuing: 24)) == nil, "content numbered after the streaming reply is never bridged")
        let normal = [Piece(element: "user", ordinal: 23, author: .user, isStreamingAssistant: false)] + streamingOnly
        check((try? ClaudeDecoder.codeStreamingPieces(normal, continuing: 99))?.last?.ordinal == 24, "a visible user anchor still determines the ordinal")

        let streamingReply = ReplyNode(role: "AXGroup", label: "Message 9", children: [marker,
            .init(role: "AXGroup", label: "Currently streaming message", children: [
                .init(role: "AXStaticText", text: "Taking a screenshot now."),
                .init(role: "AXGroup", children: [.init(role: "AXStaticText", text: "Capturing window"), .init(role: "AXStaticText", text: "running")]),
                .init(role: "AXStaticText", text: "The screenshot shows the panel.")
            ], isStreamingAssistant: true)
        ], isStreamingAssistant: true)
        let streamingText = ClaudeDecoder.codeSegments(streamingReply, responseComplete: false).map(\.text)
        check(!streamingText.joined().contains("Capturing window") && !streamingText.joined().contains("running") && streamingText.count == 2,
              "an in-progress tool label and its running status are excluded and split the reply into stages")

        // Simplified Chinese is guaranteed for replies.
        var scriptCalls = 0
        let retried = try await SystemTranslationProtection.translate("The keychain fetch is failing.", toChinese: true) { _ in
            scriptCalls += 1; return scriptCalls == 1 ? "鑰匙串獲取失敗。" : "钥匙串获取失败。"
        }
        check(retried == "钥匙串获取失败。" && scriptCalls == 2, "a Traditional system result is retried once and the Simplified retry is used")
        let converted = try await SystemTranslationProtection.translate("The keychain fetch is failing.", toChinese: true) { _ in "鑰匙串獲取失敗。" }
        check(converted == "钥匙串获取失败。", "a repeated Traditional result is converted to Simplified script")
        check(SystemTranslationProtection.simplified("使用 python3，Gemini 保持不变。") == "使用 python3，Gemini 保持不变。", "the script guarantee leaves Simplified text, names and commands unchanged")

        // A usage error stays visible while the monitor waits to retry.
        let errorUsage = ClaudeUsageMonitor(settings: defaults, load: { _, _ in throw ClaudeUsageError.keychain }, fetch: { _ in throw ClaudeUsageError.unavailable }, enabled: { true })
        errorUsage.follow(channel: .desktop)
        for _ in 0..<200 where !errorUsage.status.contains(ClaudeUsageError.keychain.localizedDescription) { try await Task.sleep(for: .milliseconds(5)) }
        errorUsage.refresh(force: true)
        check(errorUsage.status.contains(ClaudeUsageError.keychain.localizedDescription) && errorUsage.status.contains("稍后自动重试"),
              "an actionable keychain error remains visible during the retry wait instead of a generic message")

        // A slow service is reported as a timeout, not a local network fault.
        let listener = try NWListener(using: .tcp, on: .any)
        listener.newConnectionHandler = { $0.start(queue: .main) } // accept and never answer
        listener.start(queue: .main)
        for _ in 0..<400 where (listener.port?.rawValue ?? 0) == 0 { try await Task.sleep(for: .milliseconds(5)) }
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(listener.port!.rawValue)/v1beta/models/x:generateContent")!, timeoutInterval: 1)
        request.httpMethod = "POST"; request.httpBody = Data("{}".utf8)
        var message = ""
        do { _ = try await AITranslator.translate(request, provider: .gemini) } catch { message = error.localizedDescription }
        listener.cancel()
        check(message.contains("超时") && !message.contains("检查网络"), "a Gemini timeout is not reported as a local network failure")

        print("\(count) fidelity and fallback contracts passed")
    }
}
