import Foundation
import CoreGraphics

struct ReplyWork: Equatable, Sendable, Identifiable {
    let candidate: ReplyCandidate
    let conversation: String
    var manual = false
    var id: String { ReplyIdentity.id(conversation: conversation, ordinal: candidate.ordinal) }
}

struct ReplyWorkQueue {
    private var items: [ReplyWork] = []
    mutating func add(_ work: ReplyWork) {
        if let index = items.firstIndex(where: { $0.id == work.id }) { items[index] = work }
        else if work.manual { items.insert(work, at: 0) }
        else { items.append(work) }
    }
    mutating func pop() -> ReplyWork? { items.isEmpty ? nil : items.removeFirst() }
    mutating func removeAutomatic() { items.removeAll { !$0.manual } }
    mutating func clear() { items = [] }
}

enum VisibleReplyGeometry {
    static func intersects(_ frame: CGRect, viewport: CGRect) -> Bool {
        let visible = frame.intersection(viewport)
        return !visible.isNull && visible.width >= 16 && visible.height >= 16
    }
}
