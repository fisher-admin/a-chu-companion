# 本机 1.1.6 优化基线审查

审查日期：2026-10-04（America/Los_Angeles）。本报告对应本轮实际读取的工作树；不是 GitHub main 的审查。

## 基线与本轮边界

| 项目 | 本轮核实结果 |
| --- | --- |
| 源码 HEAD | `20e901624cbff43efd69d9931e29e9a51b5f2790` |
| 当前分支 | `codex/gemini-translation` |
| 构建脚本与已安装包 | 1.1.6 / build33，标识 `local.achu.companion` |
| 开始时未提交文件 | `TEST_PLAN.md`、`docs/superpowers/plans/2026-10-04-gemini-translation.md` |
| 开始时未跟踪文件 | 无 |
| 工具与平台 | Swift 6.3.2；脚本使用 Swift 5 语言模式；arm64；macOS 26.6.2 |
| 受审源码 | `Sources/` 中 25 个 Swift 文件；摘要见 [基线元数据](local-1.1.6-baseline.json) |
| 本轮工作 | 方案修订、源码与 UI 代码审查、现有模拟回归、独立未签名构建 |

原有两个未提交文件完整保留。本轮不修改生产源码、不修改正式安装、Claude 登录或用户配置；没有调用真实翻译服务或向真实 Claude 发送消息。未签名检查包仅用于验证构建，不作为授权应用运行。

## 现有链路

`ClaudeSource.capture → ClaudeDecoder → ConversationReplyTracker → ReplyWorkQueue → ReplyMonitor.translate → TranslatorModel.history → MainView`

采集与翻译已有各自的任务。采集按顺序获取快照后等待一秒，没有为每个轮询再并行启动一棵树遍历。当前不足是**展示原文仍要等到翻译队列取出该候选**，不是采集线程必须等翻译全部结束。

发送继续使用 `TargetBridge` 的目标、内容和粘贴校验；回复优化不得绕过这条发送链路。

## 原方案与本机差异

| ID | 本机证据与判定 | 建议动作 |
| --- | --- | --- |
| READ-01 | [Tracker](../../Sources/ConversationReplyTracker.swift) 已允许 Code 正式分段稳定约三秒后输出，不等待工具边界或整轮完成；17 项 Code 分段模拟通过 | 保留已修复逻辑，新增独立原文预览；不得把“可翻译”改称“整轮已完成” |
| READ-02 | [ReplyMonitor](../../Sources/ReplyMonitor.swift) 的 `onReplyAcquired` 在 `translate` 开始时调用；`continueReplies` 在翻译忙时直接返回 | 新快照的有效原文先进入展示，再独立排队翻译 |
| READ-03 | Chat 的最新回复仍需完成条件及稳定期；Code 与 Chat 规则已分开 | 保留最终完成保护，预览使用独立状态 |
| READ-04 | [ClaudeAccessibility](../../Sources/ClaudeAccessibility.swift) 在 detached 任务读取 AX；没有 AXObserver，也没有整次正文快照的总时间预算 | 先加入预算与采集健康状态，通知唤醒作为后续优化；保留轮询 |
| MODEL-01 | [TranslatorModel](../../Sources/TranslatorModel.swift) 的 `recordReplyOriginal` 在原文改变时清空同条中文 | 改为片段级失效；未改变的已译片段保留 |
| MODEL-02 | `recordReply` 先删除同 ID 再追加；每次更新设置滚动目标 | 原位置更新，滚动意图与文本版本分开 |
| UI-01 | [MessageText](../../Sources/MessageText.swift) 在长文文本改变时无条件回顶；现有 EditorTests 明确验证这个行为 | 新回复初次从头读；同条增量更新保留滚动与选区，修改对应测试契约 |
| UI-02 | 原生主题、磨砂玻璃、字号 12/14/16、紧凑单排操作均已存在 | 保留；重点整理状态与阅读，而非重做外观 |
| TRANS-01 | [GeminiTranslation](../../Sources/GeminiTranslation.swift) 已使用 Google 原生协议；[设置页](../../Sources/TranslationSettingsView.swift) 已有系统/AI/Gemini 三项 | 复用原生 Gemini，保留用户模型与已保存配置 |
| TRANS-02 | [Credentials](../../Sources/Credentials.swift) 已隔离 Gemini 与兼容服务的钥匙串账户 | 原方案“所有 AI 共用一份 key”已不适用；继续补兼容服务的来源绑定 |
| TRANS-03 | 自定义 `baseURL` 可改变，兼容服务钥匙串账户不会随接口来源改变 | 加入 profile/来源绑定与迁移，禁止无提示把旧 key 发给新来源 |
| TRANS-04 | [TextTranslation](../../Sources/TextTranslation.swift) 分块后整体返回；兼容请求 `stream: false`；真实代码保护依赖提示词 | 优先完成逐片段返回和结构保护，再测是否需要 SSE |
| USAGE-01 | [UsageMonitor](../../Sources/ClaudeUsageMonitor.swift) 仍只有桌面登录/session 来源；启动和新候选触发刷新 | 增加可见 Usage 页面、可选 statusLine 来源与成功冷却；本轮不读取真实凭据 |
| USAGE-02 | 当前有 single-flight、账户失效保护、旧值状态及十分钟过期判断；snapshot 仅在内存 | 复用保护；迁移前明确跨重启旧值是否保存，不能声称已经有持久额度缓存 |
| HEALTH-01 | 主窗口打开时检查权限，启动时单独刷新额度；没有统一的分项自检和兼容清单 | 实现轻量、无推理请求的健康中心 |
| SOURCE-01 | 没有 CLI hook/statusLine 桥接、NDJSON 适配器或浏览器扩展 | 新能力按模拟与真实验收分阶段，不能宣传三端已统一 |

## 已验证的保护

本轮现有测试覆盖：Code 稳定分段、Chat 长暂停保护、同段修订和去重、旧会话/旧翻译失效、权限变化、草稿保留、十条已完成译文、取消与超时、Gemini 独立配置、重定向拒绝、长 Unicode 与分块完整性、模拟额度账户切换及旧数据状态。

这些保护是后续改造的回归底线。传输层的 echo 测试不证明真实翻译模型不会改写代码；虚拟时间的三秒稳定测试不证明真实 AX 或云翻译已达到某个延迟目标。

完整运行结果及原方案 54 项的适用性见 [模拟验证报告](../testing/optimization-validation.md)。原生 UI 代码审查见 [UI 基线](ui-before.md)。真实测试单列在 [真实环境测试方案](../testing/real-environment-test-plan.md)。
