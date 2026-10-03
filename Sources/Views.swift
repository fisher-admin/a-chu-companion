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
                Spacer(minLength: 4)
                ClaudeUsageView(usage: usage)
                HStack(spacing: 6) {
                    Button { model.clearHistory() } label: { Image(systemName: "trash").frame(width: 30, height: 32) }
                        .buttonStyle(.plain).help("清空本地显示，不删除 Claude 会话").accessibilityLabel("清空本地对话").disabled(model.busy)
                    Button { model.showSettings = true } label: { Image(systemName: "gearshape").frame(width: 30, height: 32) }
                        .buttonStyle(.plain).accessibilityLabel("翻译设置").disabled(model.busy)
                }.foregroundStyle(.secondary)
            }.padding(.horizontal, 20).padding(.vertical, 16)
                .frame(maxWidth: .infinity)
                .background(Color.black.ignoresSafeArea(edges: .top))
                .environment(\.colorScheme, .dark)
            HStack(spacing: 8) {
                Text("中文").font(.system(size: 12, weight: .medium))
                Image(systemName: "arrow.left.arrow.right").font(.system(size: 10)).foregroundStyle(.secondary)
                Picker("对方语言", selection: $model.language) {
                    ForEach(TranslationLanguage.allCases) { language in Text(language.name).tag(language) }
                }.labelsHidden().frame(width: 100).disabled(model.busy || replies.translating)
                Spacer(minLength: 8)
                Circle().fill(model.hasTarget ? .green : .orange).frame(width: 7, height: 7)
                Text(model.hasTarget ? model.targetName : "未连接 Claude")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                if replies.watching { Button("停止读取") { replies.stop() }.controlSize(.mini) }
                Text(model.engine == "apple" ? "系统翻译" : "AI 翻译").font(.system(size: 10)).foregroundStyle(.secondary)
                    .padding(.horizontal, 7).padding(.vertical, 4)
                    .background(Color.primary.opacity(0.05), in: Capsule())
            }.padding(.horizontal, 20).padding(.vertical, 12)
            Divider()
            if !model.permission {
                HStack {
                    Image(systemName: "hand.raised")
                    Text("连接 Claude 需要辅助功能权限").font(.system(size: 12))
                    Spacer()
                    Button("前往开启") { model.requestPermission() }.controlSize(.small)
                }.padding(12).background(Color.orange.opacity(0.09))
            }
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
                                if !model.hasTarget {
                                    Label("点击 Claude 输入框，再按 ⌃⌥E 连接", systemImage: "link")
                                        .font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 4)
                                }
                            }.padding(.vertical, 30).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        ForEach(model.history) { item in ChatBubble(item: item).id(item.id) }
                        if !replies.status.isEmpty && (model.hasTarget || !model.history.isEmpty) {
                            HStack(alignment: .top, spacing: 7) {
                                if replies.translating { ProgressView().controlSize(.small) }
                                else { Image(systemName: "text.bubble").foregroundStyle(.secondary) }
                                Text(replies.status).font(.system(size: 11)).foregroundStyle(.secondary)
                                if replies.translating {
                                    Button("取消翻译") { replies.cancelTranslation() }.controlSize(.mini)
                                } else if replies.canRetry {
                                    Button("重试") { replies.retry() }.controlSize(.mini)
                                }
                            }.id("reply-status")
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }.padding(20)
                }.frame(minHeight: 260)
                    .task(id: model.chatRevision) {
                        await Task.yield()
                        guard !Task.isCancelled else { return }
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
            }
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 7) {
                    if model.busy { ProgressView().controlSize(.small) }
                    else { Image(systemName: model.isError ? "exclamationmark.circle" : "info.circle") }
                    Text(model.status).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
                }.foregroundStyle(model.isError ? .orange : .secondary).frame(minHeight: 18, alignment: .top)
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
                    }.frame(height: 90)
                    Text("回车提交 · Shift + 回车换行").font(.system(size: 10)).foregroundStyle(.secondary)
                }.padding(12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.10)))
                HStack(spacing: 14) {
                    Toggle("自动译回中文", isOn: $replies.enabled).toggleStyle(.switch)
                    Toggle("填入后发送", isOn: $model.autoSend).toggleStyle(.switch).disabled(model.busy)
                    if model.autoSend {
                        Picker("发送键", selection: $model.commandReturn) { Text("回车").tag(false); Text("⌘回车").tag(true) }
                            .labelsHidden().frame(width: 95).disabled(model.busy)
                    }
                    Spacer(minLength: 0)
                }.font(.system(size: 11)).controlSize(.mini)
                HStack(spacing: 8) {
                    if model.busy {
                        Button("取消") { model.cancel() }
                        Spacer()
                        Text("正在处理…").font(.system(size: 12)).foregroundStyle(.secondary)
                    } else {
                        Button("读取当前回复") { model.readCurrentReply() }.disabled(!model.hasTarget)
                        Button("仅翻译") { model.begin(insert: false) }.disabled(model.input.count > InputPolicy.limit || model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if !model.output.isEmpty { Button("填入译文") { model.insertResult() }.disabled(!model.hasTarget) }
                        Spacer(minLength: 0)
                        Button { model.begin(insert: true) } label: {
                            Label(model.autoSend ? "发送给 Claude" : "翻译并填入", systemImage: "paperplane.fill")
                        }
                            .buttonStyle(.borderedProminent)
                            .disabled(!model.hasTarget || model.input.count > InputPolicy.limit || model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }.controlSize(.regular)
            }.padding(18)
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
            .sheet(isPresented: $model.showSettings) { SettingsView(model: model) }
            .sheet(isPresented: $usage.showConnection) { ClaudeUsageConnectionView(usage: usage) }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.refreshPermission() }
    }
}

struct ChatBubble: View {
    let item: TranslatorModel.ChatItem
    @State private var expanded = false
    var body: some View {
        HStack(alignment: .top) {
            if item.isUser { Spacer(minLength: 55) }
            VStack(alignment: .leading, spacing: 8) {
                Label(item.isUser ? "你" : (item.chinese.isEmpty ? "Claude · 原文已读取" : "Claude · 中文译文"), systemImage: item.isUser ? "person.crop.circle" : "bubble.left")
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                if !item.isUser && item.chinese.isEmpty {
                    MessageText(text: item.foreign, original: true)
                    Text("中文译文将在翻译完成后显示。").font(.system(size: 10)).foregroundStyle(.secondary)
                } else { MessageText(text: item.chinese) }
                if !item.foreign.isEmpty && (item.isUser || !item.chinese.isEmpty) {
                    DisclosureGroup(item.language.name + "原文", isExpanded: $expanded) {
                        MessageText(text: item.foreign, original: true)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 5)
                    }.font(.system(size: 10))
                }
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(item.isUser ? Color.accentColor.opacity(0.07) : Color.clear, in: RoundedRectangle(cornerRadius: 16))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(item.isUser ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.08)))
            if !item.isUser { Spacer(minLength: 35) }
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: TranslatorModel
    @Environment(\.dismiss) private var dismiss
    @State private var engine = "apple"
    @State private var baseURL = ""
    @State private var aiModel = ""
    @State private var key = ""
    @State private var replaceKey = false
    @State private var error = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("翻译设置").font(.title2.bold())
            Picker("翻译方式", selection: $engine) {
                Text("系统翻译").tag("apple")
                Text("AI 翻译").tag("ai")
            }.pickerStyle(.segmented)
            if engine == "apple" {
                Label("无需 API 密钥", systemImage: "checkmark.seal").font(.headline)
                Text("使用苹果系统翻译。可在主窗口选择英文、德文、日文或韩文，回复始终译回中文。首次使用某种语言可能需要下载语言包；发送前建议检查译文。")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            } else {
                Text("使用支持 OpenAI 兼容格式的服务。你的中文和读取到的 Claude 回复会发送到该地址翻译；费用由该服务收取。")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 5) {
                    Text("接口地址").font(.system(size: 12, weight: .medium))
                    TextField("https://你的服务地址/v1", text: $baseURL).textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text("模型名称").font(.system(size: 12, weight: .medium))
                    TextField("填写服务提供的模型名称", text: $aiModel).textFieldStyle(.roundedBorder)
                }
                Toggle("新增或更换 API 密钥", isOn: $replaceKey)
                if replaceKey {
                    SecureField("API 密钥（留空将删除已存密钥）", text: $key).textFieldStyle(.roundedBorder)
                }
                Text("密钥保存在 macOS 钥匙串中，不写入配置文件。接口需支持 /chat/completions。")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Divider()
            Text("唤出快捷键：Control + Option + E\n请先点击目标输入框，再使用快捷键。\n自动发送请按各软件设置选择「回车」或「⌘ + 回车」。")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            if !error.isEmpty { Text(error).foregroundStyle(.red).font(.system(size: 12)) }
            HStack {
                Button("取消") { dismiss() }
                Spacer()
                Button("保存设置") {
                    let previous = (model.engine, model.baseURL, model.aiModel)
                    model.engine = engine; model.baseURL = baseURL; model.aiModel = aiModel
                    do { try model.saveSettings(key: key, replaceKey: replaceKey); dismiss() }
                    catch {
                        model.engine = previous.0; model.baseURL = previous.1; model.aiModel = previous.2
                        self.error = error.localizedDescription
                    }
                }.buttonStyle(.borderedProminent)
            }
        }.padding(26).frame(width: 440)
        .onAppear { engine = model.engine; baseURL = model.baseURL; aiModel = model.aiModel }
    }
}
