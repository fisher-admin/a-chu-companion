import SwiftUI

@MainActor struct SettingsView: View {
    @ObservedObject var model: TranslatorModel
    @Environment(\.dismiss) private var dismiss
    @State private var engine = "apple"
    @State private var baseURL = ""
    @State private var aiModel = ""
    @State private var geminiModel = GeminiProtocol.defaultModel
    @State private var key = ""
    @State private var replaceKey = false
    @State private var error = ""
    @State private var connectionMessage = ""
    @State private var testID: UUID?
    @State private var testTask: Task<Void, Never>?
    private var provider: RemoteTranslationProvider? { .init(rawValue: engine) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("翻译设置").font(.title2.bold())
            Picker("翻译方式", selection: $engine) {
                Text("系统翻译").tag("apple")
                Text("AI 翻译").tag("ai")
                Text("Gemini").tag("gemini")
            }.pickerStyle(.segmented)
            if engine == "apple" {
                Label("无需 API 密钥", systemImage: "checkmark.seal").font(.headline)
                Text("使用苹果系统翻译。可在主窗口选择英文、德文、日文或韩文，回复始终译回中文。首次使用某种语言可能需要下载语言包；发送前建议检查译文。")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            } else {
                if engine == "gemini" {
                    Text("直接使用 Google Gemini 翻译中文消息和 Claude 回复。默认固定使用 Gemini 3.1 Flash-Lite。")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    field("Gemini 模型", placeholder: GeminiProtocol.defaultModel, value: $geminiModel)
                    Text("官方提供有限免费额度，实际额度与费用取决于你的 Google 项目；已开启结算的项目可能收费。免费层内容可能用于改进 Google 产品。")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                } else {
                    Text("使用 OpenAI 兼容服务。中文消息和 Claude 回复会发送到你指定的地址翻译；费用由该服务收取。")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    field("接口地址", placeholder: "https://你的服务地址/v1", value: $baseURL)
                    field("模型名称", placeholder: "填写服务提供的模型名称", value: $aiModel)
                }
                Toggle(engine == "gemini" ? "更新 Gemini API 密钥（留空可删除）" : "更新 API 密钥（留空可删除）", isOn: $replaceKey)
                    .font(.system(size: 12))
                SecureField(replaceKey ? "输入新的 API 密钥" : "保留此服务已保存的密钥", text: $key)
                    .textFieldStyle(.roundedBorder).disabled(!replaceKey)
                    .accessibilityLabel(engine == "gemini" ? "Gemini API 密钥" : "AI API 密钥")
                Text(engine == "gemini" ? "Gemini 密钥单独保存在 macOS 钥匙串，不覆盖其他 AI 服务的密钥。" : "密钥保存在 macOS 钥匙串，接口需支持 /chat/completions。")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Button(testID == nil ? "测试连接" : "正在测试…", action: testConnection).disabled(testID != nil)
                    if testID != nil { ProgressView().controlSize(.small) }
                    if !connectionMessage.isEmpty { Text(connectionMessage).font(.system(size: 11)).foregroundStyle(.secondary) }
                }
                Text("仅发送两句固定测试文字，不保存未提交的密钥，也不读取对话内容。")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Divider()
            Text("唤出快捷键：Control + Option + E\n先点击目标输入框，再使用快捷键。\n自动发送可选择「回车」或「⌘ + 回车」。")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            if !error.isEmpty { Text(error).foregroundStyle(.red).font(.system(size: 12)) }
            HStack {
                Button("取消") { dismiss() }
                Spacer()
                Button("保存设置", action: save).buttonStyle(.borderedProminent).disabled(testID != nil)
            }
        }.padding(26).frame(width: 460)
        .onAppear { engine = model.engine; baseURL = model.baseURL; aiModel = model.aiModel; geminiModel = model.geminiModel }
        .onChange(of: engine) { cancelTest(); key = ""; replaceKey = false; error = "" }
        .onChange(of: baseURL) { cancelTest() }
        .onChange(of: aiModel) { cancelTest() }
        .onChange(of: geminiModel) { cancelTest() }
        .onChange(of: key) { cancelTest(); error = "" }
        .onChange(of: replaceKey) { cancelTest(); error = "" }
        .onDisappear { cancelTest() }
    }
    private func field(_ label: String, placeholder: String, value: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.system(size: 12, weight: .medium))
            TextField(placeholder, text: value).textFieldStyle(.roundedBorder)
        }
    }
    private func cancelTest() {
        testID = nil; testTask?.cancel(); testTask = nil; connectionMessage = ""
    }
    private func testConnection() {
        guard let provider else { return }
        error = ""; connectionMessage = ""; let id = UUID(); testID = id
        let base = baseURL; let selectedModel = engine == "gemini" ? geminiModel : aiModel
        let enteredKey = key; let useEnteredKey = replaceKey
        testTask = Task {
            do {
                let credential = useEnteredKey ? enteredKey : try Credentials.read(for: provider)
                try await TranslationConnectionCheck.run(provider: provider, baseURL: base, model: selectedModel, key: credential)
                guard testID == id, !Task.isCancelled else { return }
                connectionMessage = "连接成功，中译英及英译中均已返回。"
            } catch {
                guard testID == id, !Task.isCancelled else { return }
                self.error = error.localizedDescription
            }
            if testID == id { testID = nil; testTask = nil }
        }
    }
    private func save() {
        let previous = (model.engine, model.baseURL, model.aiModel, model.geminiModel)
        model.engine = engine; model.baseURL = baseURL; model.aiModel = aiModel; model.geminiModel = geminiModel
        do { try model.saveSettings(key: key, replaceKey: replaceKey); dismiss() }
        catch {
            model.engine = previous.0; model.baseURL = previous.1; model.aiModel = previous.2; model.geminiModel = previous.3
            self.error = error.localizedDescription
        }
    }
}
