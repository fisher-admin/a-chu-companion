import Foundation
import CryptoKit

enum ReplyIdentity {
    static func id(conversation: String, ordinal: Int) -> String {
        SHA256.hash(data: Data(conversation.utf8)).map { String(format: "%02x", $0) }.joined() + ":" + String(ordinal)
    }
}

struct ReplyProgress: Equatable, Sendable {
    let candidate: ReplyCandidate
    let complete: Bool
}

/// Follows assistant replies in one conversation as they stream. Every change in a reply's
/// text or completion is reported immediately; there is no stability delay, because the
/// segmenter only translates text whose sentence boundaries are already proven.
struct StreamingReplyTracker {
    private struct State: Equatable { var text: String; var complete: Bool }
    let conversation: String
    private var minimumOrdinal: Int
    private var states: [Int: State] = [:]

    /// The reply that is current at connection time is followed too; older ones are history.
    init(baseline: [ChatMessage], conversation: String) {
        self.conversation = conversation
        let last = baseline.last
        minimumOrdinal = last.map { $0.ordinal + ($0.author == .assistant ? 0 : 1) } ?? 1
    }

    mutating func observe(conversation current: String, messages: [ChatMessage], responseComplete: Bool) throws -> [ReplyProgress] {
        guard current == conversation else { throw BridgeError.message("Claude 会话已切换，旧会话回复未采用。") }
        let ordinals = messages.map(\.ordinal)
        guard ordinals.allSatisfy({ $0 > 0 }), ordinals == ordinals.sorted(), Set(ordinals).count == ordinals.count else {
            throw ReplyReadPending(message: "Claude 消息序号尚未完整，未采用部分内容。")
        }
        let newest = messages.last?.ordinal ?? 0
        var result: [ReplyProgress] = []
        for message in messages where message.author == .assistant && message.ordinal >= minimumOrdinal {
            let state = State(text: message.text, complete: message.ordinal < newest || responseComplete)
            guard states[message.ordinal] != state else { continue }
            states[message.ordinal] = state
            result.append(ReplyProgress(candidate: ReplyCandidate(ordinal: message.ordinal, text: message.text), complete: state.complete))
        }
        // Bound memory in long-lived sessions; older hidden replies are never replayed.
        minimumOrdinal = max(minimumOrdinal, newest - 128)
        states = states.filter { $0.key >= minimumOrdinal }
        return result
    }

    func isCurrent(_ candidate: ReplyCandidate) -> Bool { states[candidate.ordinal]?.text == candidate.text }
}
