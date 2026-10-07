import SwiftUI

struct ClaudeUsageView: View {
    @ObservedObject var usage: ClaudeUsageMonitor
    let settingsDisabled: Bool
    let openSettings: () -> Void
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let stale = usage.stale || usage.snapshot?.isStale(at: context.date) == true
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("Claude · " + usage.channel.name + " · " + usage.plan.rawValue + " · 已用")
                        .font(.system(size: 10, weight: .medium)).lineLimit(1)
                    if stale { Text("旧数据").font(.system(size: 9)).foregroundStyle(.orange) }
                    Spacer(minLength: 0)
                    Button { usage.refresh(force: true) } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.plain).disabled(usage.refreshing || usage.snapshot == nil).accessibilityLabel("刷新 Claude 额度")
                    Button { usage.showConnection = true } label: { Image(systemName: "ellipsis.circle") }
                        .buttonStyle(.plain).accessibilityLabel("连接 Claude 额度")
                    Button(action: openSettings) { Image(systemName: "gearshape") }
                        .buttonStyle(.plain).disabled(settingsDisabled).accessibilityLabel("翻译设置")
                }
                .foregroundStyle(.secondary)
                if usage.snapshot != nil {
                    row("5小时", window: usage.snapshot?.fiveHour, now: context.date)
                    row("每周", window: usage.snapshot?.sevenDay, now: context.date)
                } else {
                    Button(usage.refreshing ? "正在读取额度…" : "连接额度") { usage.showConnection = true }
                        .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
                    Text(usage.status).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                }
            }.frame(minWidth: 275, maxWidth: .infinity, alignment: .leading).help(details(stale: stale))
        }
    }
    private func row(_ label: String, window: ClaudeUsageWindow?, now: Date) -> some View {
        HStack(spacing: 5) {
            Text(label).frame(width: 30, alignment: .leading).foregroundStyle(.secondary)
            if let window {
                ProgressView(value: window.usedPercentage, total: 100)
                    .progressViewStyle(.linear)
                    .tint(window.usedPercentage >= 90 ? .orange : .accentColor)
                    .frame(minWidth: 36, maxWidth: .infinity)
                    .accessibilityHidden(true)
                Text(window.usedPercentage.formatted(.number.precision(.fractionLength(0...1))) + "%")
                    .monospacedDigit().frame(width: 33, alignment: .trailing)
                    .foregroundStyle(window.usedPercentage >= 90 ? .orange : .primary)
                Text(reset(window, now: now)).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1).fixedSize(horizontal: true, vertical: false)
            } else { Text("未提供").foregroundStyle(.secondary) }
        }.font(.system(size: 10)).accessibilityElement(children: .combine)
    }
    private func reset(_ window: ClaudeUsageWindow, now: Date) -> String {
        guard let date = window.resetsAt else { return window.resetDescription ?? "暂无重置时间" }
        if date <= now { return "已到重置时间，待刷新" }
        return ClaudeUsageDisplay.resetTime(date) + " 重置"
    }
    private func details(stale: Bool) -> String {
        var text = "\(usage.status)\n百分比为已使用比例。时间按本机时区显示。\n额度来源：\(usage.source.name)"
        text += "\n当前账户：" + usage.accountDisplayName
        if !usage.accountLabel.isEmpty { text += "\n账户备注：" + usage.accountLabel }
        if let value = usage.snapshot { text += "\n读取时间：" + value.observedAt.formatted(date: .numeric, time: .standard) }
        if stale { text += "\n数据尚未更新，请手动刷新或等待下一条回复。" }
        return text
    }
}

struct ClaudeUsageConnectionView: View {
    @ObservedObject var usage: ClaudeUsageMonitor
    @Environment(\.dismiss) private var dismiss
    @State private var channel: ClaudeUsageChannel = .desktop
    @State private var selectedBinding = ""
    @State private var savingSession = false
    @State private var key = ""
    @State private var organization = ""
    @State private var error = ""
    @State private var account = ""
    @State private var confirm = false
    @State private var installingCLI = false
    @State private var extensionID = ""
    @State private var nativeBrowser = "Chrome"
    var prepareBridge: () -> String = { "" }
    private var choices: [UsageEvidence] { usage.candidates(for: channel) }
    private var selected: UsageEvidence? {
        choices.first(where: { $0.binding == selectedBinding }) ?? choices.first
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("连接 Claude 额度").font(.title2.bold())
            Picker("连接方式", selection: $channel) {
                ForEach(ClaudeUsageChannel.allCases) { Text($0.name).tag($0) }
            }.pickerStyle(.segmented)
            Text("当前连接：" + usage.source.name + " · " + usage.accountDisplayName)
                .font(.system(size: 11)).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if channel == .desktop {
                        Text("读取 Claude 桌面端当前登录。换账户后重新核对身份，旧额度不会归入新账户。")
                        Button("读取 Claude 桌面登录") { usage.connectDesktop() }
                            .buttonStyle(.borderedProminent).disabled(usage.refreshing || savingSession || CompanionPreferences.simulated)
                        Text("首次连接可能需要钥匙串授权；自动读取不会弹出授权。")
                        Button("读取已打开的桌面 Usage（待验收）") { Task { await usage.captureVisibleUsage() } }
                            .disabled(CompanionPreferences.simulated)
                    } else if channel == .web {
                        Text("连接 Claude 网页聊天时自动获取当前账户额度。首次需要启用网页入口；设置中的按钮用于补充获取和排查。接口只核对唯一组织，多组织不猜测。")
                        HStack {
                            Button("获取网页额度") { error = ""; usage.acquire(.web) }.buttonStyle(.borderedProminent).disabled(usage.acquiring || CompanionPreferences.simulated)
                            Button("打开官方 Usage") { UsageAcquisition.openWebUsage() }
                        }
                        DisclosureGroup("配置网页入口与手动测试") {
                            VStack(alignment: .leading, spacing: 8) {
                                Button("打开网页入口文件夹") { UsageAcquisition.revealWebAdapter() }
                                Picker("安装载体", selection: $nativeBrowser) { Text("Chrome").tag("Chrome"); Text("Edge").tag("Edge") }
                                TextField("入口扩展 ID（32 位）", text: $extensionID).textFieldStyle(.roundedBorder)
                                Button("连接网页入口到伴侣") {
                                    let path = prepareBridge()
                                    Task { do { try await UsageAcquisition.installWeb(extensionID: extensionID, browser: nativeBrowser, connection: path); error = "本机入口已连接；请在 claude.ai 点击扩展图标启用。" } catch { self.error = error.localizedDescription } }
                                }.disabled(CompanionPreferences.simulated)
                                Text("Chrome / Edge：安装随附入口并连接本机 native host，在 claude.ai 标签点击入口图标启用。Safari 尚未提供入口，不能显示为已支持。完整步骤见随附 Bridge/README.md。")
                                Text("启用后连接聊天，核对遮蔽账户、5小时及每周百分比与重置时间；切换账户时旧值应隐藏。获取失败时不以桌面登录代替。")
                            }.padding(.top, 8)
                        }
                    } else {
                        Text("依据 Claude Code 官方会话和状态栏读取，与终端品牌无关。新会话核对当前登录；换账户后，旧会话额度失效，需启动新会话。")
                        Text("只读取订阅额度，不计 API 费用。未安装会话身份入口的旧会话，可以读取正文，但额度身份待核对。")
                        HStack {
                            Button("获取 CLI 当前报告") { error = ""; usage.acquire(.cli) }.buttonStyle(.borderedProminent).disabled(usage.acquiring || installingCLI || CompanionPreferences.simulated)
                            Button("配置 CLI 入口") {
                                let path = prepareBridge(); installingCLI = true
                                Task {
                                    defer { installingCLI = false }
                                    do { try await UsageAcquisition.run("install-cli", connection: path); error = "入口已配置。请在任意终端启动新的 claude 会话，连接只读来源后自动获取额度。" }
                                    catch { self.error = error.localizedDescription }
                                }
                            }.disabled(installingCLI || CompanionPreferences.simulated)
                        }
                        DisclosureGroup("CLI 手动测试与恢复") {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("配置目录：" + UsageAcquisition.cliDirectory.path)
                                Text("在任意终端启动 claude，新会话完成一次正常回复后，在状态检查的只读入口中选择该 CLI 来源；额度随聊天自动连接。也可点击获取按钮主动请求新报告。报告不保证服务器刚刚刷新；缺字段显示未提供。")
                                Button("移除 CLI 入口，恢复原状态栏") { Task { do { try await UsageAcquisition.run("uninstall-cli"); error = "已移除入口，保留其他设置。" } catch { self.error = error.localizedDescription } } }.disabled(installingCLI || CompanionPreferences.simulated)
                            }.padding(.top, 8)
                        }
                    }
                    if let selected {
                        Divider()
                        if choices.count > 1 {
                            Picker("选择已核对的来源", selection: $selectedBinding) {
                                ForEach(choices, id: \.binding) { Text(($0.identity?.displayName ?? "待核对") + " · " + String($0.binding.suffix(6))).tag($0.binding) }
                            }
                        }
                        Text("当前账户：" + (selected.identity?.displayName ?? "待核对"))
                        TextField("账户备注（可选）", text: $account).textFieldStyle(.roundedBorder)
                        Toggle("连接此账户及来源", isOn: $confirm)
                        Button("确认连接") {
                            do { try usage.migrateVisible(account: account.isEmpty ? selected.identity!.displayName : account, evidence: selected); error = "" }
                            catch { self.error = error.localizedDescription }
                        }.disabled(!confirm || CompanionPreferences.simulated)
                    } else if channel != .desktop {
                        Text("等待此来源发送已核对账户的额度报告。不会使用另一端的登录或旧额度代替。")
                    }
                    if channel == .web {
                        Divider()
                        DisclosureGroup("高级：手动 session（不自动跟随浏览器账户）") {
                            VStack(alignment: .leading, spacing: 10) {
                                SecureField("sessionKey（不是 API 密钥）", text: $key).textFieldStyle(.roundedBorder)
                                TextField("Claude 组织 UUID", text: $organization).textFieldStyle(.roundedBorder)
                                Text("只连接所填写的独立账户；切换浏览器登录不会改变这条手动连接。session 仅保存在钥匙串，并发送至 Claude 官方接口。")
                                Button("保存 session 并连接") {
                                    guard !savingSession else { return }
                                    let submittedKey = key, submittedOrganization = organization
                                    savingSession = true
                                    Task {
                                        defer { savingSession = false }
                                        do { try await usage.connectSessionAsync(key: submittedKey, organization: submittedOrganization); if key == submittedKey { key = "" }; error = "" }
                                        catch { self.error = error.localizedDescription }
                                    }
                                }.disabled(CompanionPreferences.simulated || usage.refreshing || savingSession || key.isEmpty || organization.isEmpty)
                            }.padding(.top, 8)
                        }
                    }
                }.font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: 380)
            Text(error.isEmpty ? (usage.acquisitionStatus.isEmpty ? usage.status : usage.acquisitionStatus) : error).font(.system(size: 11)).foregroundStyle(.secondary)
            HStack {
                Button("断开额度连接") { Task { await usage.disconnectAsync(); key = "" } }.disabled(CompanionPreferences.simulated)
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 450).background(GlassBackground())
        .onAppear { channel = usage.channel }
        .onDisappear { key = "" }
        .onChange(of: channel) { confirm = false; selectedBinding = ""; account = ""; error = "" }
        .onChange(of: selected.map { $0.binding + ":" + ($0.identity?.fingerprint ?? "") }) { confirm = false; account = ""; error = "" }
    }
}
