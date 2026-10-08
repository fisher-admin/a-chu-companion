# Privacy and permissions / 隐私与权限

## 中文

**聊天读取**：辅助功能用于绑定窗口的 Claude 可访问消息区及输入框，不扫描其他应用的对话。切换同窗会话会跟随读取；窗口关闭、权限撤销或离开 Claude 页面会提示或停止。仅在本次运行中保留最近十条完整回复译文和有界的待处理内容，不将聊天落盘；退出清空。清除本地记录不删除 Claude 的服务器记录。

**消息回填**：临时使用剪贴板，属于本次操作时恢复原内容；核对输入框及回填结果后才尝试配置的发送键。自动发送由用户选择，按键成功不等于服务器已收到。

**系统翻译**：默认调用 Apple Translation，不需要翻译 API 密钥。首次语言包下载可能联网，已安装包复用；具体处理遵循 macOS 系统翻译规则。

**可选 AI 翻译**：中文草稿和读取的外语回复发送至用户配置的 OpenAI 兼容服务，包含内容本身；该服务决定保存、费用及处理规则。密钥在 macOS 钥匙串，本项目不代理该服务。

**可选 Gemini 翻译**：选择后，中文草稿与读取的外语回复直接发送至 `generativelanguage.googleapis.com`，使用 Google 原生接口；仅向固定官方 HTTPS 地址发送密钥请求头，不接受重定向。Gemini 密钥使用独立钥匙串条目，保留原有 AI 服务密钥；不将密钥写入偏好、日志、仓库或 URL。Google 决定数据处理和费用；免费层有项目限额，内容可能用于改进 Google 产品，已开启结算的项目可能收费。程序不会自动切换到另一个付费模型或服务。测试连接只发送界面说明的两句固定测试文字，不读取草稿或 Claude 对话，不保存未提交的密钥；保存设置才更新该服务的钥匙串条目。

**Claude 额度**：可以读取当前桌面登录或保存指定 session。指定凭据在本程序钥匙串；桌面 Cookie 数据库留在 Claude 原目录，读取不修改它。首次桌面连接可能请求读取 Claude Safe Storage；后台自动查询禁止重复弹出授权。查询只向 claude.ai 发只读组织／额度请求，携带相应会话凭据，不发送聊天正文、不调用模型、不统计 API 计费。网页／桌面不同账户需用户连接对应来源。

**伴侣管理网页额度（build77）**：网页模块仅在claude.ai使用页面已有登录同源获取当前账户与额度，不使用Cookie API，不转发Cookie、完整邮箱、聊天正文或登录令牌。只向127.0.0.1认证接口发送遮蔽账户、身份指纹、百分比和重置时间。首次安装由用户授权；本机传输密钥保存在脚本管理器隔离存储和伴侣用户私有目录，非Claude登录凭据。它们不随仓库发布。账户变化、退出或失联先隐藏旧值；撤销授权关闭此接入，不影响聊天收发。当前需要已有获准运行的网页组件；独立WebView登录不能冒充外部浏览器当前账户。

**偏好与签名**：语言、字号、发送方式和服务地址等偏好保存在本机。安装脚本在用户钥匙串创建／复用不可导出的本机签名私钥，签名配置留在应用支持目录。它们不随仓库发布，不改变系统证书信任，不是 Apple 公证。

**反馈和 CI**：公共 Issue、PR、Actions 日志与发布内容可被其他人读取，请只提供模拟／脱敏材料。CI 使用本机模拟接口和虚构凭据，不访问个人登录。检查工具不打印匹配到的密钥内容。没有扫描器能够保证发现所有类型的敏感内容。

## English

Accessibility is used for the bound Claude conversation and composer, not to collect conversations from unrelated apps. Reading follows conversations within that window. Closing the window, leaving Claude, or revoking permission can stop reading or produce a notice. Ten completed reply translations and bounded pending content live in memory; chat content is not persisted by the companion. Exiting clears it; clearing local records does not delete Claude's server-side history.

Delivery temporarily uses the clipboard and restores it when it still belongs to the operation. It restores the input manually selected by the user, then pastes and optionally presses Return. It does not inspect input suggestions, read back pasted text or add translation-quality approval. Auto-send is optional; a successful keypress is not proof of server receipt.

Default translation uses Apple Translation without a translation API key. Initial packs may download, installed packs are reused, and processing follows macOS system translation behavior. Optional AI translation sends drafts and foreign replies to the configured provider, whose retention, pricing, and processing policies apply. Keys live in Keychain; the project does not proxy that service.

Selecting Gemini sends drafts and foreign replies directly to `generativelanguage.googleapis.com` using Google's native API. The key is sent only as a header to the fixed official HTTPS host; redirects are refused. Gemini uses a separate Keychain item, preserving the existing AI-service key. Keys are not written to preferences, logs, Git, or URLs. Google's data and pricing policies apply: the free tier has project limits, content may improve Google products, and billing-enabled projects may incur charges. The app does not automatically switch to another paid model or service. Test Connection sends only the two fixed synthetic sentences described in the UI, without drafts or Claude conversations, and does not save an unsubmitted key. Saving settings updates only the selected provider's Keychain item.

Usage can use the current desktop login or a supplied session. Supplied credentials are stored in this app's Keychain item. The desktop cookie database remains in Claude's directory and is not modified. First connection may ask to read Claude Safe Storage; automatic refresh does not repeatedly request authorization. Read-only organization/usage requests go to claude.ai with session credentials, without chat text or model calls. API billing is out of scope. Different browser/desktop accounts require the appropriate usage source.

Language, text size, send options, and provider settings are local preferences. Local installation creates/reuses a nonextractable signing key in the user's Keychain, with configuration in Application Support. These are not distributed, do not change system trust, and do not constitute Apple notarization.

Public issues, PRs, CI logs, and release material are visible to others. Share only synthetic/sanitized evidence. CI uses mock services and fictional credentials; it does not access personal logins. Checks do not print matched secret contents, and no scanner guarantees detection of all sensitive information.

## 1.1.7 experimental bridge / 实验桥接

The read-only bridge uses a private local socket and rotating token. It never exposes API keys to a browser or hook. Only explicitly enabled Claude tabs or configured CLI events are received; session storage holds selected tab IDs, not chat text. Usage adapters relay only subscription windows, used percentages and reset descriptions. Account binding is user-confirmed; switching to a visible source disables hidden credential fallback. No adapter is installed by normal startup. / 只读桥接使用私人本机端口与轮换令牌，不向浏览器或 hook 提供 API key；只接收用户启用的标签或配置的 CLI 事件。会话存储仅含标签编号，不保存正文。用量仅传订阅窗口、比例和重置说明；账号由用户确认，可见来源迁移后关闭隐藏凭据回退。正常启动不安装适配器。

Code fences, inline code and explicit URLs/paths are kept locally when translating surrounding prose. Natural-language slices still reach the selected cloud translator when cloud translation is enabled. The simulation fixture uses separate preferences, blocks real API requests and Keychain access, and never connects to real Claude. / 翻译周围正文时，代码围栏、行内代码和明确 URL／路径在本地保留；选择云翻译后，自然语言片段仍发送至用户选定服务。模拟程序隔离偏好，禁止真实 API 及钥匙串读取，也不连接真实 Claude。

Passive credential checks query only the selected endpoint's Keychain metadata, with interaction disabled. They do not read secret data, migrate keys or infer that a model can generate. Locked or permission-limited results remain unknown. Policy links and their check date are built in; displaying the health panel does not fetch those pages or issue translation requests. / 被动密钥检查只查询当前接口对应的钥匙串元数据，并禁止交互；不读取密钥正文、不迁移密钥，也不推断模型能否生成。锁定或权限不足仍标未知。政策链接和核验日期内置，显示状态面板不打开网页、不发送翻译请求。

## Tables and contextual translation / 表格与语境翻译

Ordinary table geometry and numeric cells remain local. Gemini receives only translatable cell text plus, when needed, a bounded excerpt of nearby natural-language prose and table words (at most 1,200 characters). This context helps disambiguate terms; it is untrusted data, and the model is instructed to translate only the selected source text. Protected code, formulas, explicit paths and URLs are omitted from context. Logs contain request character counts, including contextual text, rather than message content or credentials. / 普通表格的行列结构和数值单元格保留在本地。Gemini 仅接收需翻译的单元格文字，并在需要时接收有限的附近自然语言正文和表格文字（最多 1,200 字符），用于判断词义。语境作为不可信数据，规则限定模型只翻译选定原文；受保护的代码、公式、明确路径和网址不进入语境。日志记录包含语境的请求字符数，不记录正文或密钥。

## 当前账户与额度来源（build54）

桌面、网页和 CLI 的账户分别核对。手工账户备注不构成身份。桥接仅接收账户指纹及遮蔽名称，不转发原始邮箱、Cookie、OAuth 或 API key；这些身份信息只用于本机比较，不发送给翻译服务。CLI 使用官方 `claude auth status` 的元数据，在会话启动时绑定；全局登录变化后旧会话额度失效。隔离安装目录内的 `achu-account-state` 保存有权限限制的指纹、遮蔽名称和读取序号，不保存聊天或凭据。卸载恢复用户设置；状态文件不会再被调用。

网页只在当前可见账户菜单能提供唯一身份、同次读取前后身份一致时接收可信额度。昵称、套餐名称和手工 session 不能证明浏览器当前账户。身份无法确认时隐藏额度，等待核对；这不是自动浏览器额度连接已经真实验收的声明。

## 连接聊天自动取得额度（build56）

上述 build54 DOM 账户采集被网页同源只读请求替代。用户启用的官方 claude.ai 标签使用浏览器已有会话请求账户与唯一组织额度，并在请求前后核对身份。没有 Cookie 读取权限，不提取、保存或传递 Cookie/OAuth；原始账户响应、邮箱和组织标识只在页面采集器短暂处理，本机只收遮蔽名称、指纹和限额。多组织不猜测。停止、导航或身份变化使未完成请求失效。请求与聊天正文读取独立，私有接口结构变化会明确失败。

聊天连接自动使用经过核对的同一来源报告；手动 session 仍是独立来源，不自动跟随浏览器。CLI 设置动作仅包装用户原状态栏并加入本工具会话入口，可撤回；不会读取 OAuth，不因获取报告而向模型发送消息。状态栏定时/主动重跑只能称“当前报告”，不能证明服务器刷新。正常启动不自动安装扩展或修改个人 CLI 配置。

Managed Web usage (build77) uses the actual page login through same-origin requests, without Cookie APIs, chat text, full email or login tokens in the relay. Only masked identity and quota reach the authenticated loopback interface. Transport grants live in isolated userscript storage and the companion private directory; these are not Claude credentials and are not distributed. Revocation and invalid identity clear Web quota independently of chat. A permitted runtime is currently required; an independent WebView login is not treated as the external browser account.
