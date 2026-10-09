import Foundation
import CoreGraphics

struct ReplyWork: Equatable, Sendable, Identifiable {
    let candidate: ReplyCandidate
    let conversation: String
    var manual = false
    var id: String { ReplyIdentity.id(conversation: conversation, ordinal: candidate.ordinal) }
}

enum VisibleReplyGeometry {
    static func intersects(_ frame: CGRect, viewport: CGRect) -> Bool {
        let visible = frame.intersection(viewport)
        return !visible.isNull && visible.width >= 16 && visible.height >= 16
    }
}
