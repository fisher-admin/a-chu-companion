import AppKit
import Darwin

@main struct SoakTests {
    @MainActor static func main() async throws {
        precondition(CompanionPreferences.simulated, "Soak tests require --simulation")
        _ = NSApplication.shared
        let duration = Double(CommandLine.arguments.last ?? "") ?? 1800
        precondition(duration >= 2)
        let model = TranslatorModel(permissionCheck: { true }, remoteKeyRead: { _ in "" })
        defer { model.replies.stop(); model.stopPermissionMonitoring() }
        model.replies.configure(engine: "ai", baseURL: "https://simulation.invalid", model: "synthetic", language: .english)
        var requests = 0
        model.replies.testTranslation = { text in
            requests += 1
            try await Task.sleep(for: .milliseconds(2))
            return "合成译文：" + text
        }
        model.replies.watching = true
        let start = Date(); var cycles = 0; var nextReport = 0.0
        var maxHistory = 0; var latencies: [Double] = []
        while Date().timeIntervalSince(start) < duration {
            let began = Date()
            cycles += 1
            if cycles.isMultiple(of: 45) { model.clearHistory() }
            if cycles.isMultiple(of: 60) { model.replies.stop(); model.replies.watching = true }
            let conversation = "synthetic-soak-\(cycles / 90)"
            let ordinal = cycles * 2
            let text = "Synthetic stable reply \(cycles). " + String(repeating: "A local paragraph. ", count: 240) + " literal_file.py\n\n```text\nKEEP-UNCHANGED\n```\nEnding."
            model.replies.ingest(.init(conversation: conversation, messages: [.init(ordinal: ordinal, author: .assistant, text: text, completed: true)], foundTranscript: true, responseComplete: true), now: Date().timeIntervalSinceReferenceDate)
            let id = ReplyIdentity.id(conversation: conversation, ordinal: ordinal)
            let deadline = Date().addingTimeInterval(5)
            while !model.history.contains(where: { $0.id == id && !$0.updating && !$0.chinese.isEmpty }) {
                precondition(Date() < deadline, "Synthetic reply did not complete within five seconds")
                try await Task.sleep(for: .milliseconds(5))
            }
            latencies.append(Date().timeIntervalSince(began))
            maxHistory = max(maxHistory, model.history.filter { !$0.isUser && !$0.chinese.isEmpty }.count)
            precondition(maxHistory <= 10 && model.replies.watching, "History or continuous reading contract failed")
            precondition(model.history.last?.chinese.contains("literal_file.py") == true)
            let elapsed = Date().timeIntervalSince(start)
            if elapsed >= nextReport {
                var usage = rusage(); _ = getrusage(RUSAGE_SELF, &usage)
                print("SAMPLE elapsed=\(Int(elapsed)) cycles=\(cycles) fakeRequests=\(requests) maxHistory=\(maxHistory) maxRSSBytes=\(usage.ru_maxrss)")
                fflush(stdout); nextReport += 60
            }
            try await Task.sleep(for: .milliseconds(950))
        }
        let ordered = latencies.sorted(); let p95 = ordered[min(ordered.count - 1, Int(Double(ordered.count) * 0.95))]
        print("PASS: synthetic model soak seconds=\(Int(Date().timeIntervalSince(start))) cycles=\(cycles) fakeRequests=\(requests) maxHistory=\(maxHistory) syntheticTranslationP95=\(p95)")
    }
}
