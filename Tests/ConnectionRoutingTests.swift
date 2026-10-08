import AppKit
import ApplicationServices

@main struct ConnectionRoutingTests {
    static var count = 0, failures = 0
    @MainActor static func check(_ value: Bool, _ label: String) {
        count += 1; if !value { failures += 1 }
        print((value ? "PASS: " : "FAIL: ") + label)
    }
    @MainActor static func main() async throws {
        setvbuf(stdout, nil, _IONBF, 0); _ = NSApplication.shared
        let model = TranslatorModel(permissionCheck: { true }, remoteKeyRead: { _ in "synthetic-value" })
        defer { model.bridge.stop(); model.cancel(); model.stopPermissionMonitoring() }
        model.input = "保留草稿"; model.history = [.init(id: "retained", isUser: false, chinese: "保留译文", foreign: "Retained.")]
        model.bridge.start()
        let originalPath = model.bridge.connectionPath
        let result = try await Task.detached {
            let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            process.arguments = ["Tests/ConnectionRoutingClient.py", originalPath]
            try process.run(); process.waitUntilExit(); return process.terminationStatus
        }.value
        check(result == 0 && model.bridge.choices.count == 2, "authenticated synthetic reports create two separate CLI choices")
        var quotaBindings: [String] = []
        model.bridge.onUsageConnection = { quotaBindings.append($0 ?? "none") }
        model.bridge.select("cli-routing-one")
        let own = NSRunningApplication.current, element = AXUIElementCreateApplication(own.processIdentifier)
        let captured = TargetBridge.Target(app: own, element: element, window: element, value: "unverified composer", selection: nil, conversation: nil,
                                          identity: .init(role: "AXTextArea", identifier: nil, description: nil, placeholder: nil))
        model.connectCapturedTarget(captured)
        check(model.bridge.enabled && model.bridge.connectionPath == originalPath, "an unverified composer never closes or replaces the read-only server")
        check(Set(model.bridge.choices.map(\.id)) == ["cli-routing-one", "cli-routing-two"], "an unverified composer preserves candidates instead of erasing discovery")
        check(model.bridge.selected.isEmpty && quotaBindings.last == "none", "the previous bridge selection and quota binding are released without guessing a replacement")
        check(!model.hasTarget && !model.replies.watching, "an unverified composer is neither a native sending target nor the current CLI reader")
        check(model.input == "保留草稿" && model.history.first?.id == "retained", "connection routing preserves the draft and acquired translations")
        check(model.status.contains("CLI") && !model.status.contains("读取已停止"), "an unverified composer receives CLI connection guidance instead of a false stopped reader")
        check(model.bridge.selected.isEmpty, "multiple reported CLI sessions are never selected automatically")
        check(TargetBridge.nativeReplySupported(bundle: "com.anthropic.claudefordesktop", conversation: nil), "the official Desktop identity retains its native route")
        check(TargetBridge.nativeReplySupported(bundle: "unlisted.browser", conversation: "https://claude.ai/chat/synthetic"), "a verified Claude web composer is independent of browser brand")
        check(!TargetBridge.nativeReplySupported(bundle: "unlisted.terminal", conversation: nil), "a terminal carrier alone does not prove a Claude native composer")
        check(!TargetBridge.nativeReplySupported(bundle: "unlisted.browser", conversation: "http://claude.ai/chat/synthetic"), "an insecure URL cannot bless a native Claude composer")
        check(!TargetBridge.nativeReplySupported(bundle: "unlisted.browser", conversation: "https://claude.ai.example/chat/synthetic"), "a deceptive host cannot bless a native Claude composer")
        check(!TargetBridge.nativeReplySupported(bundle: "unlisted.browser", conversation: "https://synthetic@claude.ai/chat/synthetic"), "a credential-bearing URL is not a verified Claude composer")
        check(TargetBridge.nativeReplySupported(bundle: "local.achu.fixture", conversation: nil), "the existing local fixture keeps its explicitly separate native route")
        var requests = 0
        model.cliEntryRequest = { _ in requests += 1 }
        model.connectCLI()
        let readyDeadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !model.status.contains("CLI 入口已准备"), ContinuousClock.now < readyDeadline { try await Task.sleep(for: .milliseconds(2)) }
        check(requests == 1 && model.bridge.enabled && model.bridge.connectionPath == originalPath, "explicit CLI connection requests one report without replacing the discovery server")
        check(model.bridge.selected.isEmpty && !model.hasTarget && model.input == "保留草稿", "requesting reports neither guesses a session nor enables terminal sending")
        var pending: CheckedContinuation<Void, Error>?
        model.cliEntryRequest = { _ in try await withCheckedThrowingContinuation { pending = $0 } }
        model.connectCLI()
        let pendingDeadline = ContinuousClock.now.advanced(by: .seconds(2))
        while pending == nil, ContinuousClock.now < pendingDeadline { try await Task.sleep(for: .milliseconds(2)) }
        precondition(pending != nil)
        model.bridge.select("cli-routing-two")
        let selectedStatus = model.status
        check(model.replies.watching && model.replies.sourceName.contains("Claude CLI") && quotaBindings.last == "cli-routing-two", "an explicitly chosen CLI source waits for its body and binds only its own quota")
        pending?.resume(throwing: BridgeError.message("Synthetic late connection failure")); pending = nil
        try await Task.sleep(for: .milliseconds(20))
        check(model.status == selectedStatus && model.replies.watching && model.bridge.selected == "cli-routing-two", "a late connection failure cannot overwrite the selected current source")
        print("\(count) connection routing checks; \(failures) failed")
        if failures > 0 { exit(1) }
    }
}
