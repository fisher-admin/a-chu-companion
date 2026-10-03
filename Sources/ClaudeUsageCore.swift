import Foundation

enum ClaudeUsageError: LocalizedError {
    case connection, desktopMissing, keychain, expired, unavailable, malformed, rateLimited, network
    var errorDescription: String? {
        switch self {
        case .connection: return "需要连接 Claude 登录会话。"
        case .desktopMissing: return "未找到 Claude 桌面端的有效登录，请先在 Claude 登录。"
        case .keychain: return "需要允许读取 Claude 的登录会话，请点击「连接额度」。"
        case .expired: return "Claude 登录会话已失效，请重新登录或更换 session。"
        case .unavailable: return "Claude 暂时未提供账户额度。"
        case .malformed: return "Claude 的额度数据格式已变化，暂时无法读取。"
        case .rateLimited: return "额度查询过于频繁，稍后自动重试。"
        case .network: return "暂时无法连接 Claude，显示的是上次读取结果。"
        }
    }
}

struct ClaudeUsageWindow: Equatable, Sendable {
    let usedPercentage: Double
    let resetsAt: Date?
}

enum ClaudeUsageDisplay {
    static func resetTime(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "MM/dd HH:mm"
        let minute = Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 60).rounded() * 60)
        return formatter.string(from: minute)
    }
}

struct ClaudeUsageSnapshot: Equatable, Sendable {
    let fiveHour: ClaudeUsageWindow?
    let sevenDay: ClaudeUsageWindow?
    let observedAt: Date
    func isStale(at date: Date) -> Bool { date.timeIntervalSince(observedAt) > 600 }
    static func decode(_ data: Data, at date: Date = Date()) throws -> Self {
        struct Window: Decodable { let utilization: Double?; let resets_at: String? }
        struct Limit: Decodable { let kind: String; let group: String; let percent: Double; let resets_at: String? }
        struct Payload: Decodable { let five_hour: Window?; let seven_day: Window?; let limits: [Limit]? }
        do {
            let payload = try JSONDecoder().decode(Payload.self, from: data)
            func window(_ percent: Double?, _ reset: String?) throws -> ClaudeUsageWindow? {
                guard let percent else { return nil }
                guard percent.isFinite, (0...100).contains(percent) else { throw ClaudeUsageError.malformed }
                var resetDate: Date?
                if let reset {
                    let format = ISO8601DateFormatter()
                    format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    resetDate = format.date(from: reset)
                    if resetDate == nil { format.formatOptions = [.withInternetDateTime]; resetDate = format.date(from: reset) }
                    guard resetDate != nil else { throw ClaudeUsageError.malformed }
                }
                return .init(usedPercentage: percent, resetsAt: resetDate)
            }
            var five: ClaudeUsageWindow?; var seven: ClaudeUsageWindow?
            if let limits = payload.limits {
                let sessions = limits.filter { $0.kind == "session" }; let weeks = limits.filter { $0.kind == "weekly_all" }
                guard sessions.count <= 1, weeks.count <= 1 else { throw ClaudeUsageError.malformed }
                if let item = sessions.first { five = try window(item.percent, item.resets_at) }
                if let item = weeks.first { seven = try window(item.percent, item.resets_at) }
            } else {
                five = try window(payload.five_hour?.utilization, payload.five_hour?.resets_at)
                seven = try window(payload.seven_day?.utilization, payload.seven_day?.resets_at)
            }
            guard five != nil || seven != nil else { throw ClaudeUsageError.unavailable }
            return .init(fiveHour: five, sevenDay: seven, observedAt: date)
        } catch let error as ClaudeUsageError { throw error }
        catch { throw ClaudeUsageError.malformed }
    }
}

enum ClaudeUsageRequest {
    static func validateSession(_ value: String) throws {
        guard value.hasPrefix("sk-ant-sid"), (20...512).contains(value.utf8.count),
              value.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 }) else { throw ClaudeUsageError.connection }
    }
    static func make(sessionKey: String, organization: String) throws -> URLRequest {
        try validateSession(sessionKey)
        guard UUID(uuidString: organization) != nil else { throw ClaudeUsageError.connection }
        var request = URLRequest(url: URL(string: "https://claude.ai/api/organizations/\(organization.lowercased())/usage?skip_spend=1")!,
                                 cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpMethod = "GET"
        request.setValue("sessionKey=\(sessionKey); lastActiveOrg=\(organization.lowercased())", forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
}
