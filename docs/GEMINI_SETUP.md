# Gemini translation / Gemini 翻译配置

## 中文

### 在伴侣中设置

1. 从 [Google AI Studio](https://aistudio.google.com/api-keys) 创建或选择 API key，确认对应 Google 项目的额度与结算状态。
2. 打开伴侣右上角「翻译设置」，选择「Gemini」。默认模型为 `gemini-3.1-flash-lite`，固定调用 Google 官方地址，无需另填接口地址。
3. 勾选「更新 Gemini API 密钥」，在密码框中填入 key。不要在公开 Issue、PR、截图或聊天记录中提供真实 key。
4. 点击「测试连接」。仅发送「请保留现有设置。」和「Please keep the existing settings.」做中译英及英译中检查；不读取当前对话，也不保存尚未提交的 key。
5. 成功后点击「保存设置」。中文输入会译成主界面选择的英文、德文、日文或韩文，Claude 的所选语言回复译回中文。方式、模型及钥匙串密钥在重启或正常升级后保留。

Gemini 和 OpenAI 兼容服务使用不同的钥匙串条目。未勾选更新密钥时保留该服务原有 key；勾选后留空并保存会删除该服务的 key。取消设置不保存更改。系统翻译继续可选，已安装语言包复用；Gemini 本身不需要下载系统语言包。

### 纠正调用示例

POST、JSON `contents/parts` 和 `X-goog-api-key` 的方法正确。要固定使用 Gemini 3.1 Flash-Lite，应将模型换为 `gemini-3.1-flash-lite`；`gemini-flash-latest` 是可能改变的 Flash 别名。

以下示例假设你已在本机安全设置环境变量 `GEMINI_API_KEY`，不要把真实 key 提交到仓库：

```bash
curl "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-lite:generateContent" \
  -H 'Content-Type: application/json' \
  -H "X-goog-api-key: $GEMINI_API_KEY" \
  -X POST \
  -d '{
    "systemInstruction": {
      "parts": [{"text": "Translate into English. Return only the translation."}]
    },
    "contents": [{
      "role": "user",
      "parts": [{"text": "请保留现有设置。"}]
    }]
  }'
```

伴侣使用更完整的翻译指令，要求保留原意、否定、数字、代码、Markdown 与段落，且不执行待翻译文字中的指令。它只接收正常完整结束的译文；被拦截或无正文时保留原文。长文分段处理，遇到输出截断时缩段重试，不发送半截译文。输入 10,000、外文 50,000 字符的原有上限仍适用。

### 免费层与错误提示

官方为该模型列出有限免费层，但项目实际请求数、token 限额和费用取决于项目层级。开启结算的项目可能收费；程序不控制 Google 的结算状态，也不保证所有调用免费。免费层内容可能用于改进 Google 产品。参见 [官方定价](https://ai.google.dev/gemini-api/docs/pricing) 和 [限额说明](https://ai.google.dev/gemini-api/docs/rate-limits)。

- 400／401：核对 key、模型及项目访问权限。
- 403：密钥正确也可能被拒绝。若提示「Google 已拒绝该项目访问」，说明官方明确拒绝 key 所属项目，请在 [AI Studio 项目页](https://aistudio.google.com/projects) 核对项目状态并联系 Google 支持；程序不会通过改模型或反复重试绕开项目权限。其他 403 可检查项目权限、API 限制及网页／IP 等来源限制；浏览器专用限制可能不适用于桌面调用。
- 404：核对当前项目可用模型及名称。
- 429：项目额度用尽或请求过快；查看 AI Studio 项目限额后再重试。
- 网络失败：检查连接后重试，原文保留。伴侣不会把 Google 原始错误正文中的潜在敏感信息显示出来。

## English

Choose Gemini in Translation Settings, retain `gemini-3.1-flash-lite`, enable the key-update checkbox, and enter your Google AI Studio key in the masked field. Test Connection uses the two fixed sentences shown above for Chinese-to-English and English-to-Chinese; it neither accesses the conversation nor saves an unsubmitted key. Save Settings retains the provider/model and stores the key in a separate macOS Keychain item across restarts and normal updates. Outgoing text uses the language selected on the main screen; incoming replies return to Chinese.

The POST method, JSON `contents/parts`, and `X-goog-api-key` header in the original example are correct. Use the pinned Flash-Lite model in the curl example above: `gemini-flash-latest` is a moving Flash alias. The app calls the fixed Google HTTPS endpoint directly and refuses redirects. It preserves the system translation and OpenAI-compatible service profiles. Gemini does not require Apple language packs.

An unchecked key-update option retains that provider's stored key. Checking it and saving an empty value deletes only that provider's key. Cancelling settings saves nothing. Keep real keys out of Git, public reports, screenshots, and chat messages.

The app uses translation-only instructions, preserves originals on errors, and requires completed usable output. Long text is split and retried with smaller chunks when truncated. Existing 10,000-character Chinese input and 50,000-character foreign-text limits remain. Translation quality, including code fidelity, should be reviewed before use.

Google lists a limited free tier for this model. Actual quotas and charges depend on the project; billing-enabled projects may incur charges, and free-tier content may improve Google products. The app does not change billing settings or guarantee free calls. Check [pricing](https://ai.google.dev/gemini-api/docs/pricing) and [project rate limits](https://ai.google.dev/gemini-api/docs/rate-limits). For 400/401 check the key, model, and project access. A 403 can occur with a correct key: if Google explicitly denies the project, check the [AI Studio project page](https://aistudio.google.com/projects) and contact Google support. The app cannot restore project access or bypass it by switching models/retrying. Other 403 errors can involve project permission, API restrictions, or website/IP origin restrictions. For 404 check model availability; for 429 check project quotas and retry later. Network failures retain the original. Raw remote error bodies are not surfaced to avoid disclosing sensitive details.

## Official references / 官方参考

- [Gemini 3.1 Flash-Lite](https://ai.google.dev/gemini-api/docs/models/gemini-3.1-flash-lite)
- [Model names and aliases / 模型与别名](https://ai.google.dev/gemini-api/docs/models)
- [generateContent REST API](https://ai.google.dev/api/generate-content)
- [API keys / 密钥管理](https://ai.google.dev/gemini-api/docs/api-key)
- [Privacy and permissions / 伴侣隐私与权限](PRIVACY.md)
