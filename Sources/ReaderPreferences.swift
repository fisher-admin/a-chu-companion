import Foundation

enum ReplyTextSize: Int, CaseIterable, Identifiable {
    case small = 12, medium = 14, large = 16
    var id: Int { rawValue }
    var points: CGFloat { CGFloat(rawValue) }
    var label: String {
        switch self { case .small: return "小 12"; case .medium: return "中 14"; case .large: return "大 16" }
    }
}
