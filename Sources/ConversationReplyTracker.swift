import Foundation
import CryptoKit

enum ReplyIdentity {
    static func id(conversation: String, ordinal: Int) -> String {
        SHA256.hash(data: Data(conversation.utf8)).map { String(format: "%02x", $0) }.joined() + ":" + String(ordinal)
    }
}

struct ConversationReplyTracker {
    private struct State {
        var candidate: ReplyCandidate
        var changedAt: TimeInterval
        var complete: Bool
        var emitted: ReplyCandidate?
    }
    let conversation: String
    private var minimumOrdinal: Int
    private var states: [Int: State] = [:]
    init(baseline: [ChatMessage], conversation: String) {
        self.conversation = conversation
        let last = baseline.last
        minimumOrdinal = last.map { $0.ordinal + ($0.author == .assistant ? 0 : 1) } ?? 1
    }
    mutating func observe(conversation current: String, messages: [ChatMessage], responseComplete: Bool, now: TimeInterval) throws -> [ReplyCandidate] {
        guard current == conversation else { throw BridgeError.message("Claude 会话已切换，旧会话回复未采用。") }
        let ordinals = messages.map(\.ordinal)
        guard ordinals.allSatisfy({ $0 > 0 }), ordinals == ordinals.sorted(), Set(ordinals).count == ordinals.count else {
            throw ReplyReadPending(message: "Claude 消息序号尚未完整，未采用部分内容。")
        }
        let newest = messages.last?.ordinal ?? 0
        for message in messages where message.author == .assistant && message.ordinal >= minimumOrdinal {
            let candidate = ReplyCandidate(ordinal: message.ordinal, text: message.text)
            let complete = message.ordinal < newest || responseComplete
            if var state = states[message.ordinal], state.candidate == candidate {
                if state.complete != complete { state.changedAt = now }
                state.complete = complete
                states[message.ordinal] = state
            } else {
                states[message.ordinal] = State(candidate: candidate, changedAt: now, complete: complete, emitted: states[message.ordinal]?.emitted)
            }
        }
        // Bound memory in long-lived sessions; older hidden replies are never
        // replayed when the user scrolls back through history.
        minimumOrdinal = max(minimumOrdinal, newest - 128)
        states = states.filter { $0.key >= minimumOrdinal }
        var result: [ReplyCandidate] = []
        for ordinal in states.keys.sorted() {
            guard var state = states[ordinal], state.complete, now - state.changedAt >= 3, state.emitted != state.candidate else { continue }
            state.emitted = state.candidate
            states[ordinal] = state
            result.append(state.candidate)
        }
        return result
    }
    func isCurrent(_ candidate: ReplyCandidate) -> Bool {
        guard let state = states[candidate.ordinal] else { return false }
        return state.complete && state.candidate == candidate
    }
}
