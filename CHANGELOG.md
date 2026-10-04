# Changelog / 版本更新记录

All existing Git commits and previous verification records are retained. Entries describe actual app versions, not a claim that every historical build was separately released. / 保留全部提交与旧版验收记录；以下按实际应用版本归纳，不表示每个旧构建都曾单独发布。

[Full development archive / 完整开发记录](docs/DEVELOPMENT_HISTORY.zh-CN.md) · [Verification / 验收](TEST_PLAN.md)

## 1.1.6 — 2026-10-04 — build 32

- Add a separate Gemini translation choice using Google's native `generateContent` API, with `gemini-3.1-flash-lite` pinned by default. Both message translation and Chinese reply translation use the selected provider. / 新增独立 Gemini 翻译，直接使用 Google 原生接口，默认固定 Gemini 3.1 Flash-Lite；中文发送和回复回译共用配置。
- Preserve system translation and OpenAI-compatible profiles. Store the Gemini key in its own Keychain item, and persist the provider/model across restarts and normal updates. / 保留系统翻译及原有 AI 配置，Gemini 密钥独立存入钥匙串，翻译方式和模型支持重启及正常升级记忆。
- Add a cancellable connection check using two fixed synthetic sentences, without accessing chat content or saving an unsubmitted key. / 增加可取消的双向连接测试，仅用两句固定文字，不读取聊天或保存未提交的密钥。
- Explain project quotas, billing, free-tier data use, and credential errors. Reject incomplete/blocked translations; retry truncated long chunks at smaller sizes while preserving original text and existing limits. / 提示项目额度、费用、免费层数据规则及凭据错误；拒绝不完整或受限译文，长文截断自动缩段重试，保留原文和原有长度限制。
- Add twenty-two application regressions and seven loopback HTTP checks, for totals of 213 and 14. Preserve the existing signing identity and all earlier history; native/live evidence is recorded separately in TEST_PLAN. / 新增二十二项应用回归和七项本机 HTTP，合计 213／14 项；保留原签名及全部历史，界面和真实接口证据单独记录在 TEST_PLAN。

## 1.1.5 — 2026-10-04 — builds 29–31

- Recognize Claude Desktop Code session routes instead of pausing as though the conversation had closed. / 识别 Claude 桌面 Code 会话地址，修复误判页面关闭后停止读取。
- Collect Code replies across ordinal markers and sibling paragraphs, keeping final text and code while excluding tool cards and actions. / 按消息边界合并 Code 分段正文，保留末尾及代码，排除工具卡片和按钮。
- Active work indicators take precedence over a stale completion indicator; temporary incomplete Code snapshots continue waiting. / 正在运行的状态优先于旧完成提示，Code 暂时不完整时继续等待。
- Add seventeen sanitized Code regressions and a separate local Code fixture with twelve-second work pauses. / 新增十七项不含私人对话的 Code 回归及带十二秒等待的本机测试窗口。
- Build 30 translates each completed formal Code segment into a separate record while tools continue running; streaming tails wait, and segment identities preserve earlier translation jobs. Twelve additional segment checks cover timely acquisition, duplicate prevention and the total reply limit. / build30 在工具运行期间及时读取已完成正式分段，每段独立记录，未完成段落继续等待；分段身份避免取消前一段任务，新增十二项回归并保持整条原文上限。
- Build 31 starts translating formal Code text after three seconds without changes, even without another tool event or overall completion. Resumed streaming replaces the same segment after it settles; five more regressions cover this timing and prevent duplicate final records. The local fixture now waits thirty-six seconds to verify early display. / build31 正式 Code 正文稳定三秒后即开始翻译，不再等待下一工具事件或整轮结束；续写稳定后更新同一分段，新增五项时机及防重复检查，本机夹具延长为三十六秒以核对提前显示。
- Keep the existing signing identity and all earlier history. Native verification and outstanding cases are recorded in TEST_PLAN. / 保留原签名及全部旧历史，实际验收与待验证项见 TEST_PLAN。

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
