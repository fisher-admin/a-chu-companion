import SwiftUI

struct ClaudeUsageView: View {
    @ObservedObject var usage: ClaudeUsageMonitor
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let stale = usage.stale || usage.snapshot?.isStale(at: context.date) == true
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text("Claude · " + usage.plan.rawValue + " · 已用").font(.system(size: 10, weight: .medium))
                    if stale { Text("旧数据").font(.system(size: 9)).foregroundStyle(.orange) }
                    Spacer(minLength: 0)
                    Button { usage.refresh() } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.plain).disabled(usage.refreshing || usage.organization.isEmpty).accessibilityLabel("刷新 Claude 额度")
                    Button { usage.showConnection = true } label: { Image(systemName: "ellipsis.circle") }
                        .buttonStyle(.plain).accessibilityLabel("连接 Claude 额度")
                }
                if usage.snapshot != nil {
                    row("5小时", window: usage.snapshot?.fiveHour, now: context.date)
                    row("每周", window: usage.snapshot?.sevenDay, now: context.date)
                } else {
                    Button(usage.refreshing ? "正在读取额度…" : "连接额度") { usage.showConnection = true }
                        .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
                    Text(usage.status).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                }
            }.frame(width: 235, alignment: .leading).help(details(stale: stale))
        }
    }
    private func row(_ label: String, window: ClaudeUsageWindow?, now: Date) -> some View {
        HStack(spacing: 5) {
            Text(label).frame(width: 34, alignment: .leading).foregroundStyle(.secondary)
            if let window {
                Text(window.usedPercentage.formatted(.number.precision(.fractionLength(0...1))) + "%")
                    .monospacedDigit().frame(width: 42, alignment: .trailing)
                    .foregroundStyle(window.usedPercentage >= 90 ? .orange : .primary)
                Text(reset(window, now: now)).foregroundStyle(.secondary).lineLimit(1)
            } else { Text("未提供").foregroundStyle(.secondary) }
        }.font(.system(size: 10)).accessibilityElement(children: .combine)
    }
    private func reset(_ window: ClaudeUsageWindow, now: Date) -> String {
        guard let date = window.resetsAt else { return "暂无重置时间" }
        if date <= now { return "已到重置时间，待刷新" }
        return date.formatted(.dateTime.month(.twoDigits).day(.twoDigits).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)) + " 重置"
    }
    private func details(stale: Bool) -> String {
        var text = "\(usage.status)\n百分比为已使用比例。时间按本机时区显示。\n额度来源：\(usage.source.name)"
        if !usage.organization.isEmpty { text += "\n组织：\(usage.organization)" }
        if let value = usage.snapshot { text += "\n读取时间：" + value.observedAt.formatted(date: .numeric, time: .standard) }
        if stale { text += "\n数据尚未更新，请手动刷新或等待下一条回复。" }
        return text
    }
}

struct ClaudeUsageConnectionView: View {
    @ObservedObject var usage: ClaudeUsageMonitor
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var organization = ""
    @State private var error = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("连接 Claude 额度").font(.title2.bold())
            Text("优先使用 Claude 桌面端当前登录的账户。读取五小时和每周额度、重置时间及套餐，不打开网页，也不发送聊天消息。")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            Button("读取 Claude 桌面登录") { usage.connectDesktop() }
                .buttonStyle(.borderedProminent).disabled(usage.refreshing)
            Text("首次连接可能出现 macOS 钥匙串提示，用于读取 Claude 已保存的登录会话。自动刷新不会反复弹出授权。请确认桌面端和你聊天使用的是同一个账户。")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            Divider()
            Text("或使用已有 session").font(.headline)
            SecureField("sessionKey（不是 API 密钥）", text: $key).textFieldStyle(.roundedBorder)
            TextField("Claude 组织 UUID", text: $organization).textFieldStyle(.roundedBorder)
            Text("使用你原额度监控工具中的同一 session 和组织。session 只存入本程序的钥匙串，只发送给 Claude 官方额度接口。")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            Button("保存 session 并连接") {
                do { try usage.connectSession(key: key, organization: organization); key = ""; error = "" }
                catch { self.error = error.localizedDescription }
            }.disabled(usage.refreshing || key.isEmpty || organization.isEmpty)
            Text(error.isEmpty ? usage.status : error).font(.system(size: 11)).foregroundStyle(.secondary)
            HStack {
                Button("断开额度连接") { usage.disconnect(); key = "" }
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 450).background(GlassBackground()).onDisappear { key = "" }
    }
}
