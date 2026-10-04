import Foundation
import CryptoKit

enum ReplyIdentity {
    static func id(conversation: String, ordinal: Int, segment: Int = 0) -> String {
        SHA256.hash(data: Data(conversation.utf8)).map { String(format: "%02x", $0) }.joined() + ":" + String(ordinal) + (segment > 0 ? ":part:" + String(segment) : "")
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
    private var states: [ReplyAddress: State] = [:]
    init(baseline: [ChatMessage], conversation: String) {
        self.conversation = conversation
        let last = baseline.last
        minimumOrdinal = last.map { $0.ordinal + ($0.author == .assistant ? 0 : 1) } ?? 1
    }
    mutating func observe(conversation current: String, messages: [ChatMessage], responseComplete: Bool, now: TimeInterval) throws -> [ReplyCandidate] {
        guard current == conversation else { throw BridgeError.message("Claude 会话已切换，旧会话回复未采用。") }
        let addresses = messages.map(\.address)
        guard addresses.allSatisfy({ $0.ordinal > 0 && $0.segment >= 0 }), addresses == addresses.sorted(), Set(addresses).count == addresses.count else {
            throw ReplyReadPending(message: "Claude 消息序号尚未完整，未采用部分内容。")
        }
        let newest = messages.last?.ordinal ?? 0
        let present = Set(addresses)
        let observedOrdinals = Set(messages.map(\.ordinal))
        // A revised Code turn or an oversized whole-reply fallback can remove
        // segments. They must not remain eligible for a queued translation.
        states = states.filter { !observedOrdinals.contains($0.key.ordinal) || present.contains($0.key) }
        for message in messages where message.author == .assistant && message.ordinal >= minimumOrdinal {
            let candidate = ReplyCandidate(ordinal: message.ordinal, text: message.text, segment: message.segment)
            // Code's formal segment can be translated after a quiet interval
            // even before a tool boundary or the overall task finishes. The
            // decoder's completed flag still governs manual history choices.
            let complete = message.segment > 0 || (message.completed ?? (message.ordinal < newest || responseComplete))
            let address = message.address
            if var state = states[address], state.candidate == candidate {
                if state.complete != complete { state.changedAt = now }
                state.complete = complete
                states[address] = state
            } else {
                states[address] = State(candidate: candidate, changedAt: now, complete: complete, emitted: states[address]?.emitted)
            }
        }
        // Bound memory in long-lived sessions; older hidden replies are never
        // replayed when the user scrolls back through history.
        minimumOrdinal = max(minimumOrdinal, newest - 128)
        states = states.filter { $0.key.ordinal >= minimumOrdinal }
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
        guard let state = states[candidate.address] else { return false }
        return state.complete && state.candidate == candidate
    }
}
