import SwiftUI
import Translation

struct MainView: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ObservedObject var model: TranslatorModel
    @ObservedObject var replies: ReplyMonitor
    @ObservedObject var usage: ClaudeUsageMonitor
    init(model: TranslatorModel, usage: ClaudeUsageMonitor) { self.model = model; self.replies = model.replies; self.usage = usage }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(nsImage: CompanionIcon.image(size: 40)).frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text("A畜伴侣").font(.system(size: 19, weight: .semibold))
                    Text("中文对话助手").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                ClaudeUsageView(usage: usage, settingsDisabled: model.busy) { model.showSettings = true }
            }.padding(.horizontal, 20).padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background { Rectangle().fill(.regularMaterial).ignoresSafeArea(edges: .top) }
            HStack(spacing: 8) {
                Text("中文").font(.system(size: 12, weight: .medium))
                Image(systemName: "arrow.left.arrow.right").font(.system(size: 10)).foregroundStyle(.secondary)
                Picker("对方语言", selection: $model.language) {
                    ForEach(TranslationLanguage.allCases) { language in Text(language.name).tag(language) }
                }.labelsHidden().frame(width: 100).disabled(model.busy || replies.translating)
                Spacer(minLength: 8)
                Circle().fill(model.hasTarget || replies.watching ? .green : .orange).frame(width: 7, height: 7)
                Text(model.hasTarget ? model.targetName + (replies.watching ? " · 正在读取" : " · 读取已停止") : (replies.watching ? replies.sourceName + " · 正在读取（只读）" : "未连接 Claude"))
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).help(model.hasTarget ? model.targetName : replies.sourceName)
                if !model.hasTarget || model.isCLIConnection {
                    Button("连接 CLI") { model.connectCLI(releaseSelection: false) }
                        .controlSize(.mini).fixedSize().disabled(model.busy)
                }
                if model.hasTarget || replies.watching {
                    Button(replies.watching ? "停止读取" : "开始读取") {
                        if replies.watching { model.bridge.stop(); replies.stop() } else { model.startReplyReading() }
                    }.controlSize(.mini).disabled(model.busy && !replies.watching)
                }
                Text(model.engine == "apple" ? "系统翻译" : model.engine == "gemini" ? "Gemini" : "AI 翻译").font(.system(size: 10)).foregroundStyle(.secondary)
                    .padding(.horizontal, 7).padding(.vertical, 4)
                    .background(Color.primary.opacity(0.05), in: Capsule())
            }.padding(.horizontal, 20).padding(.vertical, 8)
            if !model.cliConnectionHint.isEmpty && !model.hasTarget {
                Label(model.cliConnectionHint, systemImage: "link")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20).padding(.bottom, 6)
            }
            HealthSummaryView(health: model.health, bridge: model.bridge, refresh:model.refreshHealth)
            Divider()
            if !model.permission {
                HStack {
                    Image(systemName: "hand.raised")
                    Text("连接 Claude 需要辅助功能权限").font(.system(size: 12))
                    Spacer()
                    Button("前往开启") { model.requestPermission() }.controlSize(.small)
                }.padding(12).background(Color.orange.opacity(0.09))
            }
            HStack {
                Text("最近 10 条译文 · 退出后清空").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Picker("译文字号", selection: $model.replyTextSize) {
                    ForEach(ReplyTextSize.allCases) { size in Text(size.label).tag(size) }
                }.pickerStyle(.segmented).labelsHidden().frame(width: 145).controlSize(.mini)
                if model.hasNewContent { Button("有新内容") { model.resumeFollowing() }.controlSize(.mini) }
                Button("清除记录", systemImage: "trash") { model.clearHistory() }
                    .controlSize(.mini).disabled(model.history.isEmpty)
                    .help("只清除伴侣中的记录，保留中文草稿并继续读取 Claude")
            }.padding(.horizontal, 18).padding(.top, 8)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if model.history.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Image(systemName: "bubble.left.and.bubble.right")
                                    .font(.system(size: 22, weight: .medium)).foregroundStyle(Color.accentColor)
                                    .frame(width: 48, height: 48)
                                    .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                                Text("用中文，和 Claude 聊。").font(.system(size: 22, weight: .semibold))
                                Text("消息译成所选语言，回复自动译回中文。\n在这里写消息、看回复，继续同一个对话。")
                                    .font(.system(size: 13)).foregroundStyle(.secondary).lineSpacing(5)
                                if model.isCLIConnection {
                                    Label(model.hasTarget ? "译文自动填入原终端；多行或折叠长文需在终端确认发送" : "在终端输入区按 ⌃⌥E 绑定自动填入；也可复制译文", systemImage: "terminal")
                                        .font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 4)
                                } else if !model.hasTarget {
                                    Label("点击 Claude 输入框，再按 ⌃⌥E 连接", systemImage: "link")
                                        .font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 4)
                                }
                            }.padding(.vertical, 30).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        ForEach(model.history) { item in
                            ChatBubble(item: item, fontSize: model.replyTextSize.points) { model.copyTranslation(id: item.id) }.id(item.id)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }.padding(.leading, 18).padding(.trailing, 8).padding(.vertical, 12)
                }.frame(minHeight: 180).scrollIndicators(.visible)
                    .onScrollPhaseChange { _, phase in
                        if phase == .interacting || phase == .tracking { model.readingHistory = true }
                    }
                    .onScrollGeometryChange(for: Bool.self) { geometry in
                        geometry.contentOffset.y + geometry.containerSize.height >= geometry.contentSize.height - 24
                    } action: { _, atBottom in if atBottom { model.readingHistory = false } }
                    .task(id: model.chatRevision) {
                        await Task.yield()
                        guard !Task.isCancelled else { return }
                        proxy.scrollTo(model.chatScrollTarget, anchor: model.chatScrollAtTop ? .top : .bottom)
                    }
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                if !replies.status.isEmpty && (model.hasTarget || replies.watching || !model.history.isEmpty) {
                    HStack(alignment: .top, spacing: 7) {
                        if replies.translating { ProgressView().controlSize(.small) }
                        else { Image(systemName: "text.bubble").foregroundStyle(.secondary) }
                        Text(replies.status).font(.system(size: 11)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        if replies.translating {
                            Button("取消翻译") { replies.cancelTranslation() }.controlSize(.mini)
                        } else if replies.canRetry {
                            Button("重试") { replies.retry() }.controlSize(.mini)
                        }
                    }
                }
                if model.showsOutgoingStatus {
                    HStack(alignment: .top, spacing: 7) {
                        if model.busy { ProgressView().controlSize(.small) }
                        else { Image(systemName: model.isError ? "exclamationmark.circle" : "info.circle") }
                        Text(model.status).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
                    }.foregroundStyle(model.isError ? .orange : .secondary).frame(minHeight: 18, alignment: .top)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("中文消息").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(model.input.count.formatted()) / 10,000 字").font(.system(size: 10)).monospacedDigit()
                            .foregroundStyle(model.input.count > InputPolicy.limit ? .orange : .secondary)
                    }
                    ZStack(alignment: .topLeading) {
                        DraftEditor(text: $model.input, enabled: !model.busy) { model.begin(insert: model.hasTarget) }
                        if model.input.isEmpty {
                            Text("写下你想说的话…").font(.system(size: 15)).foregroundStyle(.tertiary)
                                .padding(.horizontal, 12).padding(.vertical, 12).allowsHitTesting(false)
                        }
                    }.frame(height: min(160, max(76, CGFloat(model.input.split(separator: "\n", omittingEmptySubsequences: false).count) * 20 + 24)))
                    Text(model.isCLIConnection && !model.hasTarget ? "只读连接 · 在终端输入区按 ⌃⌥E 可绑定自动填入" : "回车提交 · Shift + 回车换行")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }.padding(12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.10)))
                HStack(spacing: 6) {
                    if !model.isCLIConnection || model.hasTarget {
                        Toggle("填入后发送", isOn: $model.autoSend).toggleStyle(.checkbox).disabled(model.busy)
                            .font(.system(size: 11)).fixedSize()
                    }
                    if model.autoSend && !model.isCLIConnection {
                        Picker("发送键", selection: $model.commandReturn) { Text("回车").tag(false); Text("⌘回车").tag(true) }
                            .labelsHidden().frame(width: 76).disabled(model.busy)
                    }
                    if model.busy {
                        Button("取消") { model.cancel() }
                        Spacer()
                        Text("正在处理…").font(.system(size: 12)).foregroundStyle(.secondary)
                    } else {
                        Button("读取历史回复") { model.readVisibleReply() }.disabled(!model.hasTarget && model.bridge.selected.isEmpty)
                        Button("仅翻译") { model.begin(insert: false) }.disabled(model.input.count > InputPolicy.limit || model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if !model.output.isEmpty && model.hasTarget { Button("填入译文") { model.insertResult() } }
                        Spacer(minLength: 0)
                        if !model.output.isEmpty {
                            Button("复制译文", systemImage: "doc.on.doc") { model.copyOutput() }
                                .help(model.isCLIConnection && !model.hasTarget ? "复制完整译文，回到 Claude Code 按 ⌘V 粘贴，再确认发送" : "复制完整译文作为备用")
                        }
                        Button { model.begin(insert: true) } label: {
                                Label(model.autoSend ? "发送给 Claude" : "翻译并填入", systemImage: "paperplane.fill")
                            }
                                .buttonStyle(.borderedProminent)
                                .disabled(!model.hasTarget || model.input.count > InputPolicy.limit || model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                .help(model.hasTarget ? "翻译后填入已核对的输入区" : "先在 CLI 或 Claude 输入区按 ⌃⌥E 连接，输入绑定成功后可用")
                    }
                }.controlSize(.small)
            }.padding(.horizontal, 18).padding(.vertical, 12)
        }.frame(minWidth: 610, minHeight: 670)
            .background {
                if reduceTransparency { Color(nsColor: .windowBackgroundColor).ignoresSafeArea() }
                else { GlassBackground().ignoresSafeArea() }
            }
            .translationTask(model.configuration) { session in await model.runApple(session) }
            .background {
                if let attempt = replies.systemTaskID, let configuration = replies.reverseConfiguration {
                    Color.clear.frame(width: 0, height: 0)
                        .translationTask(configuration) { session in await replies.runSystemReply(session, attempt: attempt) }
                        .id(attempt)
                }
            }
            .sheet(isPresented: $replies.showHistoryPicker) { VisibleReplyPicker(replies: replies) }
            .sheet(isPresented: $model.showSettings) { SettingsView(model: model) }
            .sheet(isPresented: $model.showCLIPicker) { CLIConnectionPicker(model: model) }
            .sheet(isPresented: $usage.showConnection) { ClaudeUsageConnectionView(usage: usage, prepareBridge: {
                if !model.bridge.enabled { model.bridge.start() }
                return model.bridge.connectionPath
            }) }
            .onAppear { model.refreshHealth() }
            .onReceive(NotificationCenter.default.publisher(for: .achuReaderInteracted)) { _ in model.readingHistory = true }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.refreshHealth() }
    }
}

struct CLIConnectionPicker: View {
    @ObservedObject var model: TranslatorModel
    @ObservedObject var bridge: BridgeCoordinator
    @Environment(\.dismiss) private var dismiss
    init(model: TranslatorModel) { self.model = model; self.bridge = model.bridge }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("选择 Claude Code 会话").font(.title2.bold())
            Text("自动填入请先在 Claude Code 的输入区按 ⌃⌥E，核对底部输入标记。仅在此处选择来源可开启读取；报告时间不代表当前窗口。")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: 10) {
                    if bridge.cliChoices.isEmpty {
                        Text("尚未收到 CLI 报告。请保持已登录的 Claude Code 打开，再刷新报告；无需先发送消息。")
                            .font(.system(size: 13)).foregroundStyle(.secondary).padding(.vertical, 20)
                    }
                    ForEach(bridge.cliChoices) { source in
                        Button { bridge.select(source.id) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(source.name).font(.system(size: 13, weight: .semibold))
                                    Spacer()
                                    if source.id == bridge.selected { Text("正在读取").font(.system(size: 11)) }
                                }
                                Text(source.reportDescription + (source.source?.model.map { " · " + $0 } ?? ""))
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                                Text((source.hasReplies ? "已接收正文" : "等待正式回复") + (source.delivery != nil ? " · 可核对输入来源" : " · 只读来源"))
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                        }.buttonStyle(.plain).disabled(model.busy)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.scrollIndicators(.visible)
            Text(model.status).font(.system(size: 11)).foregroundStyle(model.isError ? .orange : .secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("刷新报告") { model.connectCLI(releaseSelection: false) }.disabled(model.busy)
                Spacer()
                Button("取消") { dismiss() }
            }
        }.padding(24).frame(width: 500, height: 400)
    }
}

struct VisibleReplyPicker: View {
    @ObservedObject var replies: ReplyMonitor
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("选择要翻译的历史回复").font(.title2.bold())
            Text("以下是 Claude 当前可见的完整回复。选择后，将在伴侣中显示原文和中文。")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(replies.historyChoices) { work in
                        Button { replies.selectHistoryReply(work) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Claude · 第 \(work.candidate.ordinal) 条消息" + (work.candidate.segment > 0 ? " · 分段 \(work.candidate.segment)" : "")).font(.system(size: 11, weight: .semibold))
                                Text(String(work.candidate.text.prefix(500))).font(.system(size: 13)).lineLimit(4)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                        }.buttonStyle(.plain)
                    }
                }
            }.scrollIndicators(.visible)
            HStack { Spacer(); Button("取消") { dismiss() } }
        }.padding(24).frame(width: 460, height: 400)
    }
}

struct ChatBubble: View {
    let item: TranslatorModel.ChatItem
    let fontSize: CGFloat
    let copyTranslation: () -> Bool
    @State private var expanded = false
    @State private var copied = false
    var body: some View {
        HStack(alignment: .top) {
            if item.isUser { Spacer(minLength: 55) }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(item.isUser ? "你" : (item.chinese.isEmpty ? "Claude · 原文已读取" : "Claude · 中文译文"), systemImage: item.isUser ? "person.crop.circle" : "bubble.left")
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                    Spacer(minLength: 6)
                    if item.isUser && !item.foreign.isEmpty {
                        Button(copied ? "已复制" : "复制译文", systemImage: "doc.on.doc") { copied = copyTranslation() }
                            .controlSize(.mini).help("复制这条消息的完整外文译文")
                    }
                }
                if item.updating && !item.chinese.isEmpty {
                    Text("阶段性中文 · 后续片段正在更新").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                if !item.isUser && item.chinese.isEmpty {
                    MessageText(text: item.foreign, original: true)
                    Text("稳定片段将自动译成中文，无需等待整轮结束。").font(.system(size: 10)).foregroundStyle(.secondary)
                } else { MessageText(text: item.chinese, fontSize: item.isUser ? 15 : fontSize) }
                if !item.foreign.isEmpty && (item.isUser || !item.chinese.isEmpty) {
                    DisclosureGroup(item.language.name + (item.isUser ? "译文" : "原文"), isExpanded: $expanded) {
                        MessageText(text: item.foreign, original: true)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 5)
                    }.font(.system(size: 10))
                }
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(item.isUser ? Color.accentColor.opacity(0.07) : Color.clear, in: RoundedRectangle(cornerRadius: 16))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(item.isUser ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.08)))
                .onChange(of: item.foreign) { _, _ in copied = false }
        }
    }
}

struct HealthSummaryView: View {
    @ObservedObject var health: HealthCenter
    @ObservedObject var bridge: BridgeCoordinator
    let refresh: () -> Void
    @State private var expanded = false
    var body: some View {
        DisclosureGroup("状态检查", isExpanded: $expanded) {
            ScrollView {
                VStack(alignment:.leading,spacing:4) {
                    HStack {
                        Button(bridge.enabled ? "停止 CLI / Chrome 桥接" : "启用只读桥接（待真机验收）") { if bridge.enabled { bridge.stop() } else { bridge.start() } }
                        if bridge.enabled { Button("复制连接文件路径") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(bridge.connectionPath, forType: .string) } }
                    }.controlSize(.small)
                    Text(bridge.status).font(.system(size: 12)).foregroundStyle(.secondary)
                    ForEach(bridge.choices) { source in
                        Button("读取 " + source.name) { bridge.select(source.id) }.controlSize(.small)
                    }
                    ForEach(health.items) { item in
                        HStack(alignment: .top) {
                            Text(item.name + " · " + item.state.rawValue).frame(width: 120, alignment: .leading)
                            VStack(alignment:.leading,spacing:2) {
                                Text(item.detail).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                                if let url = item.officialURL { Link("官方政策说明",destination:url).font(.system(size:11)) }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.font(.system(size: 12)).padding(.vertical, 2)
                    }
                }
            }.frame(height:100).scrollIndicators(.visible)
        }.font(.system(size: 12)).padding(.horizontal, 20).padding(.vertical, 4)
            .onChange(of:bridge.enabled) { refresh() }
            .onChange(of:bridge.selected) { refresh() }
    }
}
