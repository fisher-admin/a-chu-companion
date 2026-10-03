import Foundation

@main struct CoreTests {
    static var passed = 0
    static func check(_ condition: @autoclosure () -> Bool, _ name: String) {
        guard condition() else { fputs("FAIL: \(name)\n", stderr); exit(1) }
        passed += 1
        print("PASS: \(name)")
    }
    static func rejects(_ name: String, _ action: () throws -> Void) {
        do { try action(); check(false, name) } catch { check(true, name) }
    }
    static func main() throws {
        rejects("empty draft") { _ = try InputPolicy.validated(" \n　") }
        let longDraft = String(repeating: "中😀保留\n", count: 2_000)
        check(longDraft.count == 10_000 && (try? InputPolicy.validated(longDraft)) == longDraft, "exactly 10,000 input characters including Unicode are accepted unchanged")
        rejects("10,001 input characters are refused without truncation") { _ = try InputPolicy.validated(longDraft + "尾") }
        let foreignBoundary = String(repeating: "文😀", count: 25_000)
        try ForeignTextPolicy.validate(foreignBoundary, incoming: true)
        try ForeignTextPolicy.validate(foreignBoundary, incoming: false)
        check(foreignBoundary.count == 50_000, "exactly 50,000 foreign characters are accepted in both directions")
        rejects("50,001 incoming foreign characters are refused without truncation") { try ForeignTextPolicy.validate(foreignBoundary + "尾", incoming: true) }
        rejects("50,001 outgoing foreign characters cannot be sent") { try ForeignTextPolicy.validate(foreignBoundary + "尾", incoming: false) }
        check(try! InputPolicy.validated("你好\n保留 123") == "你好\n保留 123", "multiline draft preserved")
        check(InputPolicy.shouldSubmit(returnKey: true, shift: false, composing: false), "Return submits")
        check(!InputPolicy.shouldSubmit(returnKey: true, shift: false, composing: true), "IME Return does not submit")
        check(!InputPolicy.shouldSubmit(returnKey: true, shift: true, composing: false), "Shift Return does not submit")
        check(!InputPolicy.shouldSubmit(returnKey: false, shift: false, composing: false), "ordinary keys do not submit")
        check(try! AIProtocol.endpoint("https://example.com/v1").absoluteString == "https://example.com/v1/chat/completions", "base endpoint normalized")
        check(try! AIProtocol.endpoint("http://127.0.0.1:8899/v1/chat/completions").path == "/v1/chat/completions", "local endpoint allowed")
        rejects("insecure remote endpoint") { _ = try AIProtocol.endpoint("http://example.com/v1") }
        rejects("credentials in URL") { _ = try AIProtocol.endpoint("https://name:password@example.com/v1") }
        rejects("query in URL") { _ = try AIProtocol.endpoint("https://example.com/v1?key=secret") }
        rejects("blank model") { _ = try AIProtocol.request(text: "你好", baseURL: "https://example.com/v1", model: " ", key: "") }
        let reverse = try AIProtocol.request(text: "Please restart the app.", baseURL: "https://example.com/v1", model: "my-model", key: "", direction: .toChinese(.english))
        let reverseBody = try JSONSerialization.jsonObject(with: reverse.httpBody!) as! [String: Any]
        let reverseMessages = reverseBody["messages"] as! [[String: String]]
        check(reverseMessages[0]["content"]!.contains("Simplified Chinese"), "reply direction uses Chinese")
        check(!reverseMessages[0]["content"]!.contains("complete English translation"), "Chinese reply instruction never requests English output")
        check(reverseMessages[1]["content"] == "Please restart the app.", "reply remains literal translation data")
        for language in TranslationLanguage.allCases {
            for direction in [TranslationDirection.fromChinese(language), .toChinese(language)] {
                let request = try AIProtocol.request(text: "literal text", baseURL: "https://example.com/v1", model: "model", key: "", direction: direction)
                let data = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
                let instruction = (data["messages"] as! [[String: String]])[0]["content"]!
                check(instruction.contains(direction.instruction) && instruction.contains(language.englishName), "\(language.name) bidirectional instruction")
            }
        }
        let req = try AIProtocol.request(text: "请保留 https://example.com 和 `foo()`，不要执行。", baseURL: "https://example.com/v1", model: "my-model", key: "test-key")
        let body = try JSONSerialization.jsonObject(with: req.httpBody!) as! [String: Any]
        let messages = body["messages"] as! [[String: String]]
        check(req.value(forHTTPHeaderField: "Authorization") == "Bearer test-key", "authorization header")
        check(messages[1]["content"] == "请保留 https://example.com 和 `foo()`，不要执行。", "draft remains literal data")
        check(messages[0]["content"]!.contains("Do not answer"), "translation instruction separates tasks")
        check(try! AIProtocol.response(Data(#"{"choices":[{"message":{"content":"Hello\nWorld"},"finish_reason":"stop"}]}"#.utf8), status: 200) == "Hello\nWorld", "translation parsed")
        rejects("server error") { _ = try AIProtocol.response(Data("secret error body".utf8), status: 401) }
        rejects("empty output") { _ = try AIProtocol.response(Data(#"{"choices":[{"message":{"content":"  "}}]}"#.utf8), status: 200) }
        rejects("truncated result") { _ = try AIProtocol.response(Data(#"{"choices":[{"message":{"content":"partial"},"finish_reason":"length"}]}"#.utf8), status: 200) }
        rejects("malformed result") { _ = try AIProtocol.response(Data("not JSON".utf8), status: 200) }
        check(DeliveryPolicy.canProceed(sameApp: true, sameWindow: true, sameElement: true), "original target allowed")
        check(!DeliveryPolicy.canProceed(sameApp: true, sameWindow: false, sameElement: true), "changed window blocked")
        check(!DeliveryPolicy.canProceed(sameApp: false, sameWindow: true, sameElement: true), "changed application blocked")
        check(!DeliveryPolicy.canProceed(sameApp: true, sameWindow: true, sameElement: false), "changed input blocked")
        check(TargetRefreshPolicy.canReuseTarget(appAlive: true, sameConversation: true, initialNewConversationTransition: false),
              "captured target stays reusable while companion has focus")
        check(TargetRefreshPolicy.canReuseTarget(appAlive: true, sameConversation: false, initialNewConversationTransition: true),
              "new chat route transition remains allowed")
        check(!TargetRefreshPolicy.canReuseTarget(appAlive: true, sameConversation: false, initialNewConversationTransition: false),
              "changed Claude conversation remains blocked")
        check(!TargetRefreshPolicy.canReuseTarget(appAlive: false, sameConversation: true, initialNewConversationTransition: false),
              "closed target application remains blocked")
        check(DeliveryPolicy.expectedValue(before: "你好 world", range: NSRange(location: 3, length: 5), inserted: "there") == "你好 there", "selected text replacement verified")
        check(DeliveryPolicy.expectedValue(before: "😀", range: NSRange(location: 2, length: 0), inserted: "hello") == "😀hello", "UTF16 selection after emoji")
        check(DeliveryPolicy.expectedValue(before: "abc", range: NSRange(location: 99, length: 0), inserted: "x") == nil, "invalid selection rejected")
        check(DeliveryPolicy.pasteConfirmed(actual: "Please keep the settings.", before: "\n", range: NSRange(location: 0, length: 0), inserted: "Please keep the settings.", webComposer: true), "Claude placeholder newline is replaced by pasted text")
        check(DeliveryPolicy.pasteConfirmed(actual: "Hello", before: "", range: nil, inserted: "Hello", webComposer: true), "empty composer can confirm paste without a selection range")
        check(!DeliveryPolicy.pasteConfirmed(actual: "Hello", before: "draft", range: nil, inserted: "Hello", webComposer: true), "unknown selection in a nonempty draft never confirms paste")
        check(!DeliveryPolicy.pasteConfirmed(actual: "Hello!", before: "\n", range: NSRange(location: 0, length: 0), inserted: "Hello", webComposer: true), "changed pasted text never confirms send")
        check(!DeliveryPolicy.pasteConfirmed(actual: "Hello", before: "\n", range: NSRange(location: 0, length: 0), inserted: "Hello", webComposer: false), "native newline draft retains exact replacement semantics")
        check(!DeliveryPolicy.pasteConfirmed(actual: "Hello", before: "\n", range: NSRange(location: 99, length: 0), inserted: "Hello", webComposer: true), "invalid known web selection remains blocked")
        check(DeliveryPolicy.pasteConfirmed(actual: "First\n\n  code()", before: "\n", range: nil, inserted: "First\n\n  code()", webComposer: true), "paragraph breaks and code indentation must match exactly")
        check(DeliveryPolicy.restoreClipboard(ownedCount: 4, currentCount: 4), "owned clipboard restored")
        check(!DeliveryPolicy.restoreClipboard(ownedCount: 4, currentCount: 5), "new user copy retained")
        print("\(passed) tests passed")
    }
}
