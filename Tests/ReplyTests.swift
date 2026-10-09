import Foundation

@main struct ReplyTests {
    static func message(_ n: Int, _ author: String, _ text: String) -> ReplyNode {
        let heading = ReplyNode(role: "AXHeading", label: author + ": summary", children: [.init(role: "AXStaticText", text: "summary")])
        let body = ReplyNode(role: "AXGroup", children: [.init(role: "AXStaticText", text: text)])
        return .init(role: "AXGroup", label: "Message \(n) of 8", children: [
            .init(role: "AXGroup", children: [heading, .init(role: "AXGroup", children: [.init(role: "AXStaticText", text: "Searched the web"), .init(role: "AXButton", label: "Searched the web")]), .init(role: "AXStaticText", text: "Searched the web"), body]),
            .init(role: "AXToolbar", label: "Message actions", children: [.init(role: "AXStaticText", text: "Aug 20"), .init(role: "AXButton", label: "Copy")])
        ])
    }
    static func main() {
        let root = ReplyNode(role: "AXGroup", label: "Chat messages", children: [message(1, "You said", "Hello"), message(2, "Claude responded", "Please restart the app.")])
        let messages = ClaudeDecoder.messages(root)
        guard messages.count == 2, messages.last?.text == "Please restart the app." else {
            fputs("FAIL: decode Claude body without headings, tool activity or toolbar\n", stderr); exit(1)
        }
        print("PASS: decode Claude body without tool or toolbar text")
        let banner = ReplyNode(role: "AXGroup", label: "Sidebar", children: [.init(role: "AXStaticText", text: "unrelated text")])
        precondition(ClaudeDecoder.messages(banner).isEmpty)
        precondition(ClaudeDecoder.messages(message(1, "Unknown", "unrelated text")).isEmpty)
        print("PASS: unmarked UI text never becomes a reply")
        let desktopCode = ReplyNode(role: "AXGroup", label: "Message 2 of 2", children: [
            .init(role: "AXGroup", children: [
                .init(role: "AXHeading", label: "Claude responded: Keep settings."),
                .init(role: "AXStaticText", text: "Run this after saving:"),
                .init(role: "AXGroup", label: "Code", children: [
                    .init(role: "AXGroup", children: [.init(role: "AXButton", label: "Open in Claude Code"), .init(role: "AXButton", label: "Copy to clipboard")]),
                    .init(role: "AXStaticText", text: "printf 'keep settings'\n")
                ]),
                .init(role: "AXStaticText", text: "Then continue.")
            ])
        ])
        guard let codeText = ClaudeDecoder.messages(desktopCode).first?.text,
              codeText.contains("printf 'keep settings'\n"), codeText.contains("Then continue."),
              !codeText.contains("Open in Claude Code"), !codeText.contains("Copy to clipboard") else {
            fputs("FAIL: desktop code block controls must not remove the code body\n", stderr); exit(1)
        }
        print("PASS: desktop code block keeps complete code and excludes its buttons")
        let flatActivity = ReplyNode(role: "AXGroup", label: "Message 2 of 2", children: [
            .init(role: "AXGroup", children: [
                .init(role: "AXHeading", label: "Claude responded: Keep the existing settings."),
                .init(role: "AXStaticText", text: "Listed files on your computer"),
                .init(role: "AXButton", label: "Listed files on your computer"),
                .init(role: "AXStaticText", text: "Listed files on your computer Keep the existing settings."),
                .init(role: "AXStaticText", text: "No changes were made.")
            ])
        ])
        guard ClaudeDecoder.messages(flatActivity).first?.text == "Keep the existing settings.\n\nNo changes were made." else {
            fputs("FAIL: flat desktop tool activity must not contaminate the response body\n", stderr); exit(1)
        }
        print("PASS: flat tool activity is removed without dropping adjacent reply text")
        var wrappedActivity = flatActivity
        let wrappedText = wrappedActivity.children[0].children[3]
        wrappedActivity.children[0].children[3] = .init(role: "AXGroup", children: [wrappedText])
        guard ClaudeDecoder.messages(wrappedActivity).first?.text == "Keep the existing settings.\n\nNo changes were made." else {
            fputs("FAIL: a paragraph wrapper must not keep the duplicated tool prefix\n", stderr); exit(1)
        }
        print("PASS: wrapped paragraph keeps reply text without the adjacent tool prefix")
        var groupedActivity = wrappedActivity
        groupedActivity.children[0].children.replaceSubrange(1...2, with: [
            .init(role: "AXGroup", label: "Listed files on your computer", children: [
                .init(role: "AXStaticText", text: "Listed files on your computer"), .init(role: "AXButton", label: "Listed files on your computer")
            ])
        ])
        guard ClaudeDecoder.messages(groupedActivity).first?.text == "Keep the existing settings.\n\nNo changes were made." else {
            fputs("FAIL: a grouped tool status must not contaminate the formal response\n", stderr); exit(1)
        }
        print("PASS: grouped tool activity is excluded from the formal response")
        let attachment = ReplyNode(role: "AXGroup", label: "Message 3 of 8", children: [
            .init(role: "AXGroup", children: [.init(role: "AXButton", label: "Pasted text.txt"), .init(role: "AXStaticText", text: "TXT")]),
            .init(role: "AXButton", label: "Show message actions")
        ])
        let attachmentHistory = [message(1, "You said", "Old prompt"), message(2, "Claude responded", "Old answer"), attachment,
            message(4, "Claude responded", "Attachment answer"), message(5, "You said", "Earlier prompt"),
            message(6, "Claude responded", "Earlier answer"), message(7, "You said", "Current prompt"),
            message(8, "Claude responded", "Current answer")]
        guard let tail = try? ClaudeDecoder.recentMessages(attachmentHistory), tail.map(\.ordinal) == [4, 5, 6, 7, 8] else {
            fputs("FAIL: an old attachment must not block a later complete conversation tail\n", stderr); exit(1)
        }
        print("PASS: historical attachment bounds the latest verified continuous tail")
        var latestAttachment = attachment
        latestAttachment.label = "Message 8 of 8"
        do { _ = try ClaudeDecoder.recentMessages(Array(attachmentHistory.dropLast()) + [latestAttachment]); fatalError("unmarked latest message must stop") }
        catch { print("PASS: unmarked latest message remains unreadable instead of guessing") }
        let thinking = ReplyNode(role: "AXGroup", label: "Message 4 of 4", children: [
            .init(role: "AXGroup", children: [.init(role: "AXHeading", label: "Claude responded:"), .init(role: "AXStaticText", text: "")])
        ])
        do {
            _ = try ClaudeDecoder.recentMessages([thinking])
            fatalError("thinking without a body must not become a reply")
        } catch {
            guard error is ReplyReadPending else { fputs("FAIL: an empty thinking reply must remain retryable instead of stopping monitoring\n", stderr); exit(1) }
            print("PASS: empty thinking reply is retryable without exposing partial content")
        }
        guard let visibleTail = try? ClaudeDecoder.recentMessages([attachmentHistory[3], attachmentHistory[5], attachmentHistory[6], attachmentHistory[7]]), visibleTail.map(\.ordinal) == [6, 7, 8] else {
            fputs("FAIL: an older virtualized history gap must not block the complete latest tail\n", stderr); exit(1)
        }
        print("PASS: older virtualized history gaps bound the latest continuous tail")
        do { _ = try ClaudeDecoder.recentMessages([attachmentHistory[7], attachmentHistory[6]]); fatalError("reversed order must stop") }
        catch { print("PASS: out-of-order messages never produce a snapshot") }
        let simple = ReplyNode(role: "AXGroup", label: "Message 1 of 1", children: [
            .init(role: "AXGroup", children: [.init(role: "AXHeading", label: "Claude responded: Please"), .init(role: "AXStaticText", text: "Please restart.")])
        ])
        guard ClaudeDecoder.messages(simple).first?.text == "Please restart." else { fputs("FAIL: flattened simple Claude reply\n", stderr); exit(1) }
        print("PASS: flattened simple Claude reply")
        let unnamedHeading = ReplyNode(role: "AXGroup", label: "Message 1 of 1", children: [
            .init(role: "AXGroup", children: [
                .init(role: "AXHeading", children: [.init(role: "AXStaticText", text: "Claude responded: Please restart.")]),
                .init(role: "AXStaticText", text: "Please restart.")
            ])
        ])
        guard ClaudeDecoder.messages(unnamedHeading).first?.text == "Please restart." else {
            fputs("FAIL: authorship text in heading child identifies the reply\n", stderr); exit(1)
        }
        print("PASS: authorship text in heading child identifies the reply")
        print("13 reply tests passed")
    }
}
