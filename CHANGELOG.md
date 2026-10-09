# Changelog / 版本更新记录

All existing Git commits and previous verification records are retained. Entries describe actual app versions, not a claim that every historical build was separately released. / 保留全部提交与旧版验收记录；以下按实际应用版本归纳，不表示每个旧构建都曾单独发布。

[Full development archive / 完整开发记录](docs/DEVELOPMENT_HISTORY.zh-CN.md) · [Verification / 验收](TEST_PLAN.md)

## 1.2.0 — 2026-10-08 — build 79

Formal source release of the streaming optimization, originally recorded as build29. Build79 continues the existing build counter after build78; the build29 audit remains available. The build78 development branch is preserved separately and is not included in this release. See [release scope and known limitations](docs/releases/1.2.0.md) and [independent review](docs/reviews/2026-10-08-claude-1.2.0.md). / 正式源码发布原 build29 的流式优化，构建号接续 build78 使用 79；保留原审核记录。build78 开发分支单独保留，其全部功能未纳入本次发布。发布范围和已知问题见上述记录。

Release preparation restores local-artifact exclusions, historical synthetic-session exemptions and Google API key scanning, with regression coverage. / 发布整理恢复本机产物排除、历史虚构 session 的精确白名单和 Google 密钥检测，并补充回归检查。

### Added / 新增

- Streaming translation: completed sentences and paragraphs of a reply are translated while Claude is still writing and rendered strictly in source order; the 3-second post-completion wait is removed. Code fences pass through verbatim; terminal escape sequences are stripped. / 边接收边翻译：Claude 输出时即按句段翻译并严格按原文顺序显示，取消完成后 3 秒等待；代码块原样保留，终端控制字符被清除。
- Dual-engine translation with automatic fallback: AI output (Gemini or any OpenAI-compatible service) is validated for language, length, code fences, inline code, links and preambles; timeouts, 429, rejected keys and failed checks fall back per segment to system translation with a visible notice. A circuit breaker pauses AI after repeated failures and honours Retry-After. / 双引擎自动降级：AI 译文经语言、长度、代码、链接及开场白校验；超时、限流、密钥错误或校验失败时逐段改用系统翻译并提示，连续失败时暂停 AI 并遵守 Retry-After。
- Hardened AI prompt: `<source>` delimiting, direction-specific few-shot examples, `temperature: 0`, stop sequence and bounded output. "Use Gemini address" button in settings. / 加固翻译指令：原文定界、示例、零温度与停止序列；设置中可一键填入 Gemini 地址。
- System translation without a visible task on macOS 26 for installed language pairs, and a session broker for macOS 15 or missing packs. / macOS 26 已安装语言包可直接系统翻译；macOS 15 或缺少语言包时由窗口代为准备会话。
- "Disconnect" control. / 新增「断开」按钮。

### Fixed / 修复

- A Claude interface change no longer leaves reading silently waiting: unresolved transcript, message markers or composer for 45 seconds shows a clear warning, and reading recovers automatically. / Claude 界面变化不再无声等待：45 秒仍无法识别时明确提示，恢复后自动继续。
- Automatic sending checks whether the composer is empty or no longer contains the inserted translation; this is not proof of server receipt, and nonempty changes can produce a false positive (see known limitations). / 自动发送检查输入框清空或不再包含译文；这不证明服务器已接收，非空文字变化也可能被误判，见已知问题。
- Clipboard writes during insertion carry `org.nspasteboard.TransientType` and `ConcealedType`. / 回填剪贴板带临时与隐藏标记。
- Accessibility opt-ins enabled in Chrome/Electron are switched back off on disconnect, app switch or quit, leaving the app's own settings untouched. / 断开、切换或退出时关闭本程序开启的辅助功能选项，不改动应用自身设置。

### Removed / 移除

- Superseded full-reply tracker, single-reply work queue and translation lifecycle. / 移除被取代的整条回复追踪器、单条队列及旧翻译状态。

Application validation: 273 regression checks plus seven loopback HTTP checks, and real system-translation smoke tests including streamed AI-to-system fallback. See TEST_PLAN for native verification and gaps. / 应用验证为 273 项回归、7 项本机 HTTP 及真实系统翻译冒烟（含流式降级）；原生验收与未验证范围见 TEST_PLAN。

## 1.1.4 — 2026-10-03 — build 28

### Added / 新增

- Continuous reading immediately on connection, including prompts entered directly in Claude; background operation and same-window conversation following. / 连接即持续读取，支持 Claude 原窗口输入、后台读取及同窗会话跟随。
- Selection among visible completed historical replies; ten completed Chinese translations per run, clear action preserving draft/monitoring. / 可见历史选择、本次运行最近十条译文及保留草稿和监测的清除按钮。
- Persistent language and 12/14/16 text size, default 14. / 语言和三档字号记忆，默认 14。
- Usage progress bars, percentages and reset times; grouped top controls and one-line bottom controls. / 额度进度条、百分比、重置时间及紧凑布局。

### Fixed / 修复

- Sending no longer hides the companion window; draft focus is restored when appropriate. / 发送不再主动隐藏窗口，适时恢复输入焦点。
- Thinking/streaming delays no longer end monitoring after five temporarily incomplete reads. / 暂时正文不完整及长时间思考不再提前结束监测。
- Formal code and replies after historical attachments remain readable; tool-control prefixes are excluded. / 保留代码及附件后的正式正文，排除工具操作前缀。
- Original-first display, isolated system translation attempts, startup timeout/retry, and stale-result protection. / 先显示原文，隔离翻译任务，准备超时可重试并拒绝过期结果。
- New long translations open at the beginning; full body and scrollable ending preserved. / 长译文从头阅读，全文和末尾保留。

### Open-source preparation / 开源准备

- MIT license; bilingual README, contribution/conduct/security/support/privacy/release guidance. / MIT 许可与双语社区文档。
- Issue/PR templates, CODEOWNERS, dependency updates, credential-free CI and CodeQL. / 问题及 PR 模板、维护者归属、依赖更新、无个人凭据 CI 及 CodeQL。
- Explicit verification-only --unsigned build in a separate directory; normal fixed-signature install unchanged. / 独立目录的显式无签名构建，正常固定签名安装保留。
- Translation deadline tests tolerate hosted-runner scheduling and explicitly release late results after timeout; application deadlines are unchanged. / 翻译超时测试适应云端调度，超时后再释放迟到结果；应用等待时间未改。
- Local HTTP fixture readiness has a bounded 30-second startup allowance with failure diagnostics. / 本机 HTTP 夹具允许最多 30 秒启动，并保留失败诊断。
- Usage concurrency tests control simulated request completion instead of assuming millisecond timing; model preparation waits for its actual state. / 额度并发测试主动控制模拟返回，翻译准备测试等待实际状态。
- Full original README archived; commit history is not rewritten. / 原 README 完整归档，不改写提交历史。

Application validation: 157 regression checks plus seven loopback HTTP checks. See TEST_PLAN for native tests and gaps. / 应用验证为 157 项回归及 7 项本机 HTTP，实际界面验收及未验证范围见 TEST_PLAN。

Historical source checkpoints: [build21](https://github.com/fisher-admin/a-chu-companion/commit/b0ab04c), [build22](https://github.com/fisher-admin/a-chu-companion/commit/14b5d67), [build28](https://github.com/fisher-admin/a-chu-companion/commit/fecb818).

## 1.1.3 — 2026-10-03 — build 17

- Compact native glass interface and 610-point default width; pig-head A icon orange matched to the local Claude icon. / 收窄窗口与磨砂界面，猪头 A 图标橙色校准。
- Explicit desktop/session usage source, 24-hour local reset times, rounding at minute boundaries. / 明确额度来源及本地 24 小时重置时间，修复分钟边界。
- Fixed signing identity and authorization continuity retained. / 保留固定签名及授权连续性。
- Historical black header was replaced by system-adaptive appearance in 1.1.4. / 本版黑色标题区在 1.1.4 中改为跟随系统外观。

[Source checkpoint](https://github.com/fisher-admin/a-chu-companion/commit/81b22ab)

## 1.1.1 — 2026-10-03 — build 10

- English/German/Japanese/Korean selection, native glass interface and A pig icon. / 四种目标语言、磨砂界面及猪头 A 图标。
- Claude desktop/session usage, subscription capability identification, five-hour/weekly percentages and refresh on replies. / 桌面或 session 额度、套餐识别、两类使用比例及随回复刷新。
- Chinese 10,000 / foreign 50,000 character limits, segmented long-text handling, full scrolling reader. / 字符上限、长文分段及完整可滚动阅读。

[Source checkpoint](https://github.com/fisher-admin/a-chu-companion/commit/f578b86)

## 1.0.4 — 2026-10-02 — build 5

- Dedicated reusable local signing identity, strict identity check before replacement, stable install location. / 可复用本机签名、更新前身份核对及稳定安装位置。
- Permission changes detected while running without restart; drafts and active jobs preserved. / 运行期间识别授权变化，无需重启，保留草稿和任务。
- Consolidated app identity and removed obsolete local copies. / 统一应用身份及清理旧本机副本。

[Source checkpoint](https://github.com/fisher-admin/a-chu-companion/commit/5a9e407)

## 1.0.1 — 2026-10-02 — build 2

- Improved Claude composer paste verification and author-heading reply identification; clearer read status. / 改善 Claude 输入框回填验证、作者标题识别及读取提示。
- Historical permission recovery and translation lifecycle fixes recorded in Git. / 授权恢复及翻译生命周期修复留在历史中。

[Source checkpoint](https://github.com/fisher-admin/a-chu-companion/commit/fd0b76b)

## 1.0.0 — initial repository version — build 1

- Chinese/English companion workflow, native chat interface, optional sending and original reply access. / 中文与英文工作流、原生聊天界面、可选发送和原文入口。
- Initial source and tests uploaded; subsequent translation lifecycle adjustment preserved. / 初始源码与测试上传，后续翻译生命周期调整完整保留。

[Initial commit](https://github.com/fisher-admin/a-chu-companion/commit/4f962c6) · [Lifecycle adjustment](https://github.com/fisher-admin/a-chu-companion/commit/8502272)
