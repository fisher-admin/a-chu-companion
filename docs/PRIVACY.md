# Privacy and permissions / 隐私与权限

## 中文

**聊天读取**：辅助功能用于绑定窗口的 Claude 可访问消息区及输入框，不扫描其他应用的对话。切换同窗会话会跟随读取；窗口关闭、权限撤销或离开 Claude 页面会提示或停止。仅在本次运行中保留最近十条完整回复译文和有界的待处理内容，不将聊天落盘；退出清空。清除本地记录不删除 Claude 的服务器记录。

**消息回填**：临时使用剪贴板，属于本次操作时恢复原内容；核对输入框及回填结果后才尝试配置的发送键。自动发送由用户选择，按键成功不等于服务器已收到。

**系统翻译**：默认调用 Apple Translation，不需要翻译 API 密钥。首次语言包下载可能联网，已安装包复用；具体处理遵循 macOS 系统翻译规则。

**可选 AI 翻译**：中文草稿和读取的外语回复发送至用户配置的 OpenAI 兼容服务，包含内容本身；该服务决定保存、费用及处理规则。密钥在 macOS 钥匙串，本项目不代理该服务。

**Claude 额度**：可以读取当前桌面登录或保存指定 session。指定凭据在本程序钥匙串；桌面 Cookie 数据库留在 Claude 原目录，读取不修改它。首次桌面连接可能请求读取 Claude Safe Storage；后台自动查询禁止重复弹出授权。查询只向 claude.ai 发只读组织／额度请求，携带相应会话凭据，不发送聊天正文、不调用模型、不统计 API 计费。网页／桌面不同账户需用户连接对应来源。

**偏好与签名**：语言、字号、发送方式和服务地址等偏好保存在本机。安装脚本在用户钥匙串创建／复用不可导出的本机签名私钥，签名配置留在应用支持目录。它们不随仓库发布，不改变系统证书信任，不是 Apple 公证。

**反馈和 CI**：公共 Issue、PR、Actions 日志与发布内容可被其他人读取，请只提供模拟／脱敏材料。CI 使用本机模拟接口和虚构凭据，不访问个人登录。检查工具不打印匹配到的密钥内容。没有扫描器能够保证发现所有类型的敏感内容。

## English

Accessibility is used for the bound Claude conversation and composer, not to collect conversations from unrelated apps. Reading follows conversations within that window. Closing the window, leaving Claude, or revoking permission can stop reading or produce a notice. Ten completed reply translations and bounded pending content live in memory; chat content is not persisted by the companion. Exiting clears it; clearing local records does not delete Claude's server-side history.

Delivery temporarily uses the clipboard and restores it when it still belongs to the operation. The target and pasted text are checked before the configured send key is attempted. Auto-send is optional; a successful keypress is not proof of server receipt.

Default translation uses Apple Translation without a translation API key. Initial packs may download, installed packs are reused, and processing follows macOS system translation behavior. Optional AI translation sends drafts and foreign replies to the configured provider, whose retention, pricing, and processing policies apply. Keys live in Keychain; the project does not proxy that service.

Usage can use the current desktop login or a supplied session. Supplied credentials are stored in this app's Keychain item. The desktop cookie database remains in Claude's directory and is not modified. First connection may ask to read Claude Safe Storage; automatic refresh does not repeatedly request authorization. Read-only organization/usage requests go to claude.ai with session credentials, without chat text or model calls. API billing is out of scope. Different browser/desktop accounts require the appropriate usage source.

Language, text size, send options, and provider settings are local preferences. Local installation creates/reuses a nonextractable signing key in the user's Keychain, with configuration in Application Support. These are not distributed, do not change system trust, and do not constitute Apple notarization.

Public issues, PRs, CI logs, and release material are visible to others. Share only synthetic/sanitized evidence. CI uses mock services and fictional credentials; it does not access personal logins. Checks do not print matched secret contents, and no scanner guarantees detection of all sensitive information.
