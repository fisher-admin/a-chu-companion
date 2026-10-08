# Changelog / 版本更新记录

All existing Git commits and previous verification records are retained. Entries describe actual app versions, not a claim that every historical build was separately released. / 保留全部提交与旧版验收记录；以下按实际应用版本归纳，不表示每个旧构建都曾单独发布。

[Full development archive / 完整开发记录](docs/DEVELOPMENT_HISTORY.zh-CN.md) · [Verification / 验收](TEST_PLAN.md)

## 1.1.8 — 2026-10-08 — build 77 — 伴侣管理网页额度连接

- Prepare and manage the quota module inside the companion; normal installation authorization replaces folder and extension-ID setup. / 由伴侣准备、管理额度模块，以正常安装授权替代手动目录和ID配置。
- Authenticate the uniquely focused, user-selected page before activating the panel. Keep tab identity separate from document/app generations; pairing failure does not block sending or translation. / 面板取得焦点前核对唯一的手选网页，区分标签与页面及程序代次，额度连接失败不阻断发送和翻译。
- Persist local transport grants; relay masked identity and quota, clear failed reads, and recover temporary heartbeat loss without another grant. / 保留本机接口授权，仅传遮蔽账户和额度，读取失败隐藏旧值，短时失联恢复不重新授权。
- Preserve build76 and all earlier results; real runtime authorization and Claude quota remain separate acceptance steps. / 保留build76及全部旧结果，真实组件授权和额度另列验收。见[记录](docs/testing/companion-managed-web-usage-2026-10-08.md)。

## 1.1.8 — 2026-10-08 — build 76 — 网页Code会话地址与持续读取

- Recognize the official Web Code homepage and `session_…` routes as Code transcripts, keeping polling active through the mode transition. Unrelated paths remain excluded. / 补齐官方网页Code首页和会话地址识别，切换模式时保持轮询；无关页面仍排除。
- Preserve build75 `86a81ef`, including its live Desktop and Web Chat results and the Web Code failure that led to this repair. / 保留build75提交、桌面与网页Chat实际通过结果，以及网页Code停止读取的实际失败。
- Add 15 Web Code checks covering navigation, malformed routes and localized tool-summary exclusion. Sending and quota source isolation are unchanged. / 新增15项网页Code检查，覆盖导航、错误地址与中文工具提示排除，保持发送规则和额度来源隔离。见[验收记录](docs/testing/web-code-navigation-2026-10-08.md)。

## 1.1.8 — 2026-10-08 — build 75 — 中文界面回复读取与网页额度诊断

- Recognize English, Traditional Chinese and Simplified Chinese transcript, authorship, ordinal and completion metadata while preserving reply text. / 识别英文、繁体和简体中文的消息区、作者、序号及完成标记，保留回复原文。
- Exclude localized message-action reveal buttons from tool activity and remove repeated tool prefixes only beside their matching cards. / 中文消息操作按钮不再误判为工具事件；仅在对应工具卡片旁去掉重复的工具提示前缀。
- Diagnose missing or invalid Web native-host setup for the connected browser and publish acquisition failures in the main quota display. Do not substitute Desktop credentials. / 按所连浏览器检查网页额度入口配置，缺失、失效或获取失败显示具体原因，不以桌面登录代替网页账户。
- Retain the shared manual input sender and removed translation review. All 38 offline suites passed. Preserve build74 `1bdd1b0` and earlier history; see the [build75 record](docs/testing/localized-reader-web-usage-2026-10-08.md). / 保持三端手选发送及取消质量审核，38组离线回归通过；保留build74及历次记录。

## 1.1.8 — 2026-10-08 — build 74 — 手选输入位置、三端统一发送

- Pin the input chosen by the user's shortcut immediately and share one sending implementation across Desktop, Web and CLI. Read-source/usage reports cannot clear or redirect the sending target. / 快捷键立即保存手选输入位置，桌面、网页、CLI共用发送实现；回复或额度报告不清除、不改投发送目标。
- Remove semantic quality rejection, review notices and assembled-text gates from outgoing and incoming translation. Retain provider-only-translation instructions, formatting and service fallback. / 删除发送和回译中的质量拒绝、核对提示及拼接后审核；保留仅翻译指令、格式处理和服务备用翻译。
- Dispatch one paste and optional Return without inspecting recommendations, CLI layouts, input value/caret or paste receipts. Include multiline, tables and collapsed displays; restore only the selected physical window/input. / 不检查建议、布局、输入内容／光标或粘贴回执；单行、多行、表格与折叠显示都按设置粘贴和回车，仅恢复选定的窗口／输入位置。
- Preserve cancellation, changed Chinese drafts and replaced connection identities. Report missing physical targets and partial dispatch explicitly; never retry a paste automatically. / 保留取消、中文草稿改变及连接更换的处理；输入位置失效和部分按键失败给出具体提示，不自动重复粘贴。
- Preserve build73 `62b7571` and all prior verification history. See the [build74 record](docs/testing/manual-input-direct-send-2026-10-08.md). / 保留build73提交及历次验证记录，详见本次记录。

## 1.1.8 — 2026-10-08 — build 73 — CLI组合快捷提示兼容

- Recognize the observed combined auto-mode/agents footer hints, including separate rows and the alternate solid-triangle glyph. / 兼容截图中的auto mode与agents组合提示、分别成行及实心三角符号。
- Share the bounded hint grammar with operational notice parsing; permission choices remain separate from message input, and unknown trailing text remains rejected. / 输入与操作提示共用有界的提示识别；选择菜单不会变成聊天输入，未知尾随内容仍拒绝。
- Preserve build72 `2ae15ac`, previous failures and pending live acceptance. See the [build73 record](docs/testing/cli-combined-hints-2026-10-08.md). / 保留build72提交、此前失败及真实验收待确认状态，详见记录。

## 1.1.8 — 2026-10-08 — build 72 — 系统默认翻译与CLI提示

- Default to system translation and retain the original input binding and fill/send choices after cloud failure, without a service-switch review step. / 系统翻译默认；云翻译失败后保留原输入绑定及填入／发送选择，不因切换翻译服务另设确认。
- Give each outgoing system task its own view identity; equal-language retries and cloud fallback no longer depend on an old callback. / 系统翻译任务分别启动，同语言重试与备用翻译不再依赖旧任务回调。
- Read more than twelve visual input rows, wrapped current markers and known CLI hints. Preserve exact content, process/focus checks and repeat-paste protection; unknown/collapsed receipt remains unsubmitted. / 修订视觉换行、标记换行和已知提示行识别，保留完整内容、进程焦点及重复粘贴核对，未知或折叠内容不自动回车。
- Separately display and locally translate current CLI operational prompts. Keep choice keys/order and command details, reject menus as message composers, and retire stale translations when reading or source identity changes. / CLI运行、选择及权限提示先显示原文、稳定后独立本机翻译；保留选项编号和命令，不混入正式回复，也不代操作选项。
- Preserve build71 `d106b52`, its installed backup and all earlier records. Verification, simulator-only boundaries and pending live-terminal acceptance are documented in the [build72 record](docs/testing/system-default-fallback-2026-10-08.md). / 保留build71提交、应用备份和历次记录；验证、模拟器边界及真实终端待确认项详见记录。

## 1.1.8 — 2026-10-08 — build 71 — CLI推荐提示兼容

- Accept rendered prompt suggestions during binding, translation preflight and paste instead of requiring an empty display. Let the normal CLI paste dismiss suggestions, then verify the exact translation before optional Return. / 连接、翻译和粘贴前不再要求显示内容为空；推荐文字由CLI正常输入消除，完整核对译文后才按设置回车。
- Preserve repeated-fill protection using in-memory receipt digests; mixed or truncated input remains unsubmitted. / 通过本次运行中的接收摘要保留重复填入保护，混合或截断内容不自动发送。
- 54 CLI input, 30 routing and 22 model checks passed. A native synthetic window with visible suggestions verified one paste and one Return. Preserve build70's user-reported failure and keep real-terminal acceptance separate. / 54项CLI输入、30项路由及22项翻译状态通过；原生模拟推荐文字下粘贴和回车均为1次。保留build70真实失败，终端验收另列。见[修订记录](docs/testing/cli-prompt-suggestions-2026-10-08.md)。

## 1.1.8 — 2026-10-08 — build 70 — CLI快捷键直接连接

- Capture the active CLI text surface before configuring reports; verify the same window when the footer or process identity arrives later. The shortcut no longer opens a session picker. / 快捷键先保存当前CLI输入表面，再准备报告；页脚或进程身份迟到时仍核对同一窗口，不再弹出会话选择。
- Preserve capture failures independently of reply/usage status and keep the sending control visible but disabled until input is verified. / 连接失败原因独立显示，发送入口始终可见，输入未核对时保持禁用。
- Ignore only trailing blank viewport rows when checking the current footer; retain shell/menu, nonempty draft and process/focus guards. / 末尾空白行不再遮挡连接标记；普通命令行、选择菜单、已有草稿及进程焦点检查保持。
- All 34 offline groups, 49 CLI input checks, 30 routing checks and 23 Python checks passed. Native synthetic windows verified delayed first binding and actual single/multiline/collapsed paste behavior. Preserve build69's real input failure separately; live terminal acceptance remains pending. / 完整34组离线回归、49项CLI输入、30项路由及23项Python通过；原生模拟验证延迟直连与短文、多行、折叠粘贴。保留build69用户实际填入失败，真实终端验收另列。见[修订记录](docs/testing/cli-shortcut-binding-2026-10-08.md)。

## 1.1.8 — 2026-10-07 — build 69 — CLI自动填入修复

- Bind CLI input separately from reply reading, checking the original window, current footer and process-bound marker; replies no longer clear the input target. / CLI输入与回复读取分别绑定，核对原窗口、当前会话页脚及进程标记，正文到达不再清除输入目标。
- Paste once. Verified single-line receipt permits optional Return; multiline/table or collapsed pastes require terminal confirmation. Changed focus, session, process or cancellation stops further actions and preserves text. / 译文只粘贴一次；短单行完整核对后可自动回车，多行、表格及折叠长文需终端确认；焦点、来源、进程改变或取消时保留文本并停止后续按键。
- Wait through temporary redraw without repeating paste; restore the previous clipboard only while this operation still owns it. Older reports remain read-only. / 临时重绘在同一次粘贴后等待核对，不重复粘贴；仅当剪贴板仍属本次操作时恢复原内容，旧报文保持只读。
- Offline and native synthetic-window results are separate from pending real-terminal acceptance. Prior builds and failures remain. / 离线回归、原生模拟与待完成的真实终端验收分别记录，旧版本及失败证据完整保留。见[测试记录](docs/testing/cli-automatic-input-2026-10-07.md)。

## 1.1.8 — 2026-10-07 — build 68 — installed / CLI会话辨认与复制修复

- Open an actionable CLI session picker from unverified/non-editable capture. Show bounded directory/model labels and local report times; match the terminal footer identifier explicitly without guessing a session or terminal brand. / 无法识别或捕获终端输入时打开可操作的会话选择页；显示目录末级名、模型、报告时间，按终端底部编号明确选择，不按终端品牌或最近来源猜选。
- Bind one session independently of cwd; migrate only exact old account states while preserving invalidated/conflicting identity isolation and original files. Retain existing status-line output. / 同一会话切目录不再生成额外连接；只迁移精确旧状态，保留失效／冲突身份隔离、原文件和用户状态栏。
- Add current/history outgoing translation copy actions, keep completed/fallback status visible, and hide invalid automatic-send controls for CLI. Paste and confirm in the terminal manually. / 新增当前和历史外文复制按钮，翻译完成与兜底提示不被等待读取遮盖；CLI隐藏无效自动发送控制，复制后回终端粘贴并确认发送。
- Preserve build67 as `d9b8b90` with an installed backup. All 33 groups / 621 declared checks, HTTP19, socket4, Python19 and Node13 passed; source/script/resource consistency and the original signing requirement verified. Synthetic and installed-editor clipboard tests passed. Noninteractive Gemini key access was unavailable; the installed fixed-sentence check used system fallback. Physical terminal verification and full live acceptance remain separate. / 保留build67提交及应用备份；完整33组621项、HTTP19、socket4、Python19及Node13通过，冻结源码／脚本／资源及原签名已核对。模拟窗口与正式伴侣编辑器复制通过；Gemini无弹窗密钥读取受限，固定句由系统兜底。实体终端及完整真实验收另列，见[修复记录](docs/testing/cli-workflow-repair-2026-10-07.md)。

## 1.1.8 — 2026-10-07 — build 67 — installed / CLI连接分流修复

- Route verified Desktop/Web composers separately from read-only CLI sessions. An unverified terminal composer no longer closes discovery or enters native reply reading; release old usage without guessing a replacement. / 已核实的桌面和网页保留原生读取；终端输入不再关闭只读入口或误入原生读取，旧额度解除，不猜测当前会话。
- Add a main-window CLI acquisition and session-selection menu, independent of terminal brand. Selected sessions remain reading while waiting for formal text; late connection errors cannot replace the new selection. CLI input remains manual. / 主界面增加CLI报告获取与明确会话选择，不依赖终端品牌；等待正文时持续读取，迟到错误不覆盖新选择，终端输入仍由用户完成。
- Accept the observed German indirect-question form “geben Sie an, ob”, retaining direct-question, assertion, number and literal checks. / 兼容实际德文间接问句表达，保留直接问句、附加答案、数字和字面量保护。
- Preserve build66 as `f0db179` and its installed backup. All 33 groups / 608 declared checks, 19 loopback HTTP checks and bridge checks passed; 107 frozen source files and five scripts matched installation under the original signing requirement. Live acceptance is recorded separately. / 保留build66提交及应用备份；完整33组608项、本机HTTP19项及桥接检查通过，107个源文件与5个脚本冻结核对，沿原签名安装；真实验收另列。

## 1.1.8 — 2026-10-07 — build 66 — installed / 间接问句修订

- Accept matching English/German indirect questions for Chinese requests such as “explain whether”, without requiring a trailing question mark. Direct questions becoming answers and added assertions remain checked. / 中文“请说明是否……”可忠实译成以句号结尾的英/德间接问句；直接问题变答案、附加内容的保护仍保留。
- Add six regression cases: 34 quality checks first reproduced two false rejections, then passed. All 32 groups / 585 declared checks and 19 loopback HTTP checks passed; unsigned packaging and unchanged-identity installation verified. / 新增6项用例，34项质量检查先复现2项误拦再全部通过；完整32组585项、本机HTTP19项通过，构建与原签名安装已核对。
- Align the actual-language test harness with production literal protection. All four system round trips and 49,031-character / 1,400-paragraph translation preserve the final marker; retain the old unprotected-harness failure. / 真实语言测试使用正式文字保护；系统四语言往返及49,031字符的1,400段和尾标记通过，保留旧脚本绕过保护的失败。
- Preserve build65 and keep live service/access failures distinct from simulated acceptance. See the [execution record](docs/testing/optimization-results-2026-10-07.md). / 保留build65；真实服务拒绝、钥匙串等待及未完成三端验收单独记录，不用模拟结果代替。

## 1.1.8 — 2026-10-07 — build 65 — installed / 实测问题修订

- Add a review notice for the observed statistical training-fold/discount mistranslation, without rewriting normal discount sentences. / 针对系统实测“训练折内→training discount”增加狭窄核对提示，保留候选并暂停自动发送；普通折扣语句不被改写。
- Hold English/German output whose unprotected prose still contains substantial Chinese for explicit review; leave valid Japanese/Korean scripts and protected literals unchanged. / 英/德目标正文仍有较多中文时供人工核对；日/韩字符及代码、文件名等字面量不误判。
- Preserve build64 as commit `67d924e`, including its 575-check regression and actual system-translation findings. / build64 保存为 `67d924e`，保留575项回归及真实系统翻译观察。
- Four new checks first reproduced two missing safeguards; all 32 groups / 579 declared checks, 19 loopback HTTP checks and bridge contracts passed. Installed under the unchanged designated signing requirement with build64/63 backups preserved. Mac lock and protected system UI prevent completion of live acceptance; see the [execution record](docs/testing/optimization-results-2026-10-07.md). / 新4项用例先复现2项缺口，完整32组579项检查、本机HTTP19项及桥接检查通过；沿原签名安装，保留build64/63备份。Mac锁屏及受限系统界面导致真实验收尚未完成，参见执行记录。

## 1.1.8 — 2026-10-07 — build 64 — installed checkpoint / 已安装优化检查点

- Preserve Claude's original build63 as commit `207a06d`, without resetting the branch or rewriting earlier version history. / Claude 原始 build63 已保存为 `207a06d`；保留此前全部提交与实测记录。
- Share cooldowns across incoming/outgoing cloud requests; preserve the primary error before local fallback, honor Retry-After, and bound temporary recovery to three attempts per slice. / 发送和回译共用服务等待状态；系统兜底前保留原失败原因，遵守限流等待，每片段临时失败最多自动尝试三次。
- Keep old usage hidden while waiting for the current entrance, including saved bindings after restart; include conversation identity when detecting reply completion. / 等待当前入口时不恢复旧额度；重启保存的绑定只作为候选，相同回复在不同会话分别刷新。
- Remove broad terminology substitutions, preserve literals through script conversion, and distinguish negative numbers from Markdown lists. / 移除泛化术语替换；繁简转换先处理正文再恢复文件名；负数不再误判成列表。
- Apply shared fidelity checks to prose and table cells, validate reassembled numbers/literals/table layout, and hold uncertain translations for review before automatic delivery. Deterministic checks do not prove full semantic equivalence. / 正文与单元格共用校验，完整拼接后再核对数字、字面量和表格；疑似附加解释的译文供核对，暂停自动发送。这些规则不能证明所有语义都正确。
- Recover temporary reading errors with 1–60 second backoff; stop distinctly on explicit permission revocation or source exit. Keep delivery failures separate from translation fallback. / 普通读取错误逐步等待1至60秒后恢复；权限撤销或目标退出明确停止。回填失败保留译文，不再重新翻译掩盖原因。
- Add independent red/green regression evidence and a precise synthetic-fixture exception to repository scanning; live acceptance is recorded separately in the [execution report](docs/testing/optimization-results-2026-10-07.md). / 新增独立修复前失败与修复后通过证据，扫描仅对指定文件中的已核实假凭据精确放行；真实验收另列，不以模拟结果替代。

## 1.1.7 — 2026-10-07 — builds 59–63 — historical Claude audit batch / Claude 原始审核修改批次

- Preserve the original source snapshot and build63 installation evidence. The exact per-build release sequence was not documented; this grouped entry does not invent separate releases or acceptance results. / 保留原始源码与 build63 安装证据；原修改未留下完整的逐构建发布说明，本条按批次记录，不虚构每个构建的单独发布或验收结果。
- Introduce shared shape/length checks, review-only outgoing system fallback, local reverse-translation fallback, technical phrase correction, completed-reply usage refresh and streaming Code continuity. / 增加译文形状与长度检查、发送方向只供核对的系统兜底、回复回译系统兜底、术语纠正、完整回复额度刷新以及 Code 流式容器连续识别。
- Independent baseline: 29 offline groups / 496 declared checks, 14 loopback HTTP checks and bridge contracts passed; repository scanning flagged a verified synthetic session in a new test file. Important uncovered regressions are documented in the [independent review](docs/testing/claude-change-review-2026-10-07.md). / 独立基线29组496项离线检查、本机HTTP14项及桥接检查通过；扫描命中新测试中的合成 session。未被原测试覆盖的问题见独立审查，不将此批次称为完整真实验收通过。

## 1.1.7 — 2026-10-07 — build 58 — installed / 桌面后台输入框核对

- Preserve the explicitly captured live composer when Claude exposes only its background page as focused while the companion is active. Continue checking the original window, conversation, value and caret; verify actual focus again before insertion. / Claude在伴侣前台时只暴露后台页面焦点，仍可核对先前明确绑定的有效输入框；保留窗口、会话、内容和光标检查，实际回填前再次核对焦点。
- Reproduce the failed preflight before repair, add five guards, and pass the full 28-group / 429-check offline regression. Install under the unchanged designated signing requirement; preserve build57 and earlier evidence. / 修复前复现发送预检失败，新增五项保护，完整28组429项离线回归通过；沿原指定签名安装，保留build57及全部旧记录。
- Live Desktop Chat showed automatic usage connection, one translated research question sent automatically, and formal text/table acquisition. Gemini also appended an unsolicited answer and returned HTTP 503 during reverse translation; full live acceptance remains incomplete. / 真实桌面Chat观察到额度自动连接、一条研究问题外语自动发送及正式原文和表格取得；但Gemini附加了答案，回译期间还出现HTTP 503，完整真实验收尚未通过。
- A translation-only repair candidate remains isolated locally and is not part of this installed or uploaded build. See the [current results and preserved failures](docs/testing/three-channel-active-usage-2026-10-07.md). / 纯翻译修复候选仍在本机隔离目录，未并入本安装版或上传源码；参见[当前结果与保留的失败记录](docs/testing/three-channel-active-usage-2026-10-07.md)。

## 1.1.7 — 2026-10-07 — build 57 — installed / 补充获取的状态提示

- build56 安装版发现“入口已配置”提示盖住随后获取的等待与失败结果。网页/CLI获取按钮先清除上一次操作提示，让当前获取进度和结果可见；保留 build56 的实际测试及失败记录。
- 沿用 build56 的自动跟随、同源网页查询和CLI报告通道，不改变登录或额度来源。
- 已安装并独立核对签名与资源；安装版合成网页/CLI聊天连接验证自动跟随，无需另行确认额度账户。真实和模拟边界及待验收步骤见[完整记录](docs/testing/three-channel-active-usage-2026-10-07.md)。

## 1.1.7 — 2026-10-07 — build 56 — installed / 聊天连接自动获取额度

- 额度跟随桌面聊天、已选择的网页或 CLI 来源自动连接；切换来源先清除旧值，身份核对后采用对应报告。设置保留补充获取按钮。
- 网页入口使用官方页面当前会话进行同源只读账户与额度请求，前后核对身份；不读取、储存或转发 Cookie。多组织及结构变化不猜测，不用桌面账户兜底。
- 新增 CLI 配置、主动获取当前报告和移除入口；保留原状态栏输出、无关设置。明确重复报告不代表服务器刷新，缺失额度不显示 0%。
- 网页额度请求独立于正文读取，网络等待不阻塞原文显示或翻译。仅增加固定的只读获取命令，拒绝任意脚本或地址。
- 安装、模拟和真实三端验收分别记录；保留 build55 及全部历史证据，未完成的真实环境项目不宣称通过。

## 1.1.7 — 2026-10-07 — build 55 — installed / 清除记录后的阅读提醒

- Clear the new-content reminder and resume normal following when local records are cleared. Preserve the Chinese draft, continuous reading and retired-message protection. / 清除本地记录时同步清除“有新内容”提醒并恢复正常跟随；保留中文草稿、持续读取和旧消息退役保护。
- Reproduce the stale reminder before repair, then pass four related groups with 41 checks. Verify the installed UI with synthetic history selection, clearing and a new reply; retain build54's full 420-check record separately. / 修复前复现提醒残留，相关四组41项通过；安装版完成合成历史选择、清除及新回复界面核对。build54完整420项记录单独保留，不把它改写为55全量检查。
- Install with the unchanged designated signing requirement, preserve the build54 backup, restore Gemini and remove synthetic messages and the local test listener. Real Web, visible-terminal and account-switch limitations remain recorded. / 沿原指定签名安装，保留build54备份，恢复Gemini并清理模拟消息及本机测试通道；真实网页、可见终端和账户切换的限制仍如实记录。见[安装版补测](docs/testing/installed-ui-follow-up-2026-10-07.md)。

## 1.1.7 — 2026-10-07 — build 54 — installed / 三种额度入口与当前账户保护

- Separate Desktop, Web and Claude Code CLI connection choices. Selecting an entrance filters candidates; only confirmation switches the active connection. / 桌面、网页及 Claude Code CLI 分为三个入口；选择只筛选候选，确认后才切换连接。
- Bind visible usage to a verified account fingerprint and capture generation/order. Missing identity hides old usage; retired-account and late-generation reports cannot restore it. Preserve old settings as unverified rather than trusting a manual alias. / 可见额度绑定已核对账户及读取代次、顺序；身份缺失隐藏旧额度，退役账户和迟到报告不能恢复。旧设置保留，但人工备注不再被当作身份。
- Anchor CLI identity at SessionStart using official auth metadata; changed global login invalidates the old session rather than relabeling its cached usage. Preserve user hooks and status line during install/uninstall. / CLI 启动时核对官方登录信息；全局账户变化使旧会话额度失效，不给缓存额度改名。安装和卸载保留用户原 hooks 与状态栏。
- Support the current Usage route and This week heading, preserving reset text before percentages and excluding product shares. / 兼容当前 Usage 路由和 This week 标题，正确对应位于百分比前的重置时间，并排除产品占比。
- Pass 28 local groups / 420 declared checks, 14 loopback HTTP checks, four socket contracts, 11 Python and eight Node bridge checks; native synthetic connection UI verified. Installation and real account-switch acceptance are recorded separately. / 28组420项本地检查、本机HTTP14项、socket4项、Python11项和Node8项通过；本机合成连接面板已验证。安装及真实账户切换分别记录，不以模拟代替实测。
- Install and verify the unchanged designated signing requirement; 90 frozen source files match validation. Preserve build53 and its evidence. Desktop authorization, automatic Web usage and real account-switch acceptance remain pending. / 已安装并核对原指定签名，90个冻结源码文件与验证时一致；保留build53及其证据。桌面登录授权、网页自动额度连接和真实账户切换仍待验收。见[专项记录](docs/testing/account-usage-test-2026-10-07.md)。

## 1.1.7 — 2026-10-07 — build 53 — installed / 已知表头语义冲突兜底

- Preserve the original technical header Honest MSE when its explicit definition denies unbiasedness but a provider nevertheless returns an unbiased label. Keep faithful procedural translations and explicit affirmative claims. This conservative shared guard applies to system, compatible AI and Gemini output. / 原文明示否认无偏性、服务仍将Honest MSE译成无偏表头时，保留原专业名称；忠实的流程译名及原文明示的肯定声明不受影响。兜底适用于系统、兼容AI及Gemini输出，不宣称解决全部术语质量问题。
- Add three regression contracts using the contradiction observed in the real build52 Gemini replay; retain that failed semantic result. / 依据build52真实Gemini重放中的冲突，新增三项检查；保留语义复核失败记录，实际安装及复核另列。
- Pass 27 local regression groups with 408 declared checks, 14 loopback HTTP checks and a clean unsigned build. Install and verify the original designated signing requirement; visible-terminal acceptance is recorded separately. / 27组408项声明检查、14项本机HTTP及独立无签名构建通过，已沿原指定签名安装并核对；可见终端实测单独记录，不以模拟结果代替。

## 1.1.7 — 2026-10-07 — build 52 — installed / 表格限定语、目录断行与输入框更新

- Retain a definition's directly adjacent negative qualification in bounded table context; keep unrelated paragraphs excluded. Shared AI/Gemini cell instructions do not infer unbiasedness from an honest evaluation procedure. / 表格术语上下文保留直接相邻的否定限定语，保持长度限制并排除无关段落；AI及Gemini共用规则，不将honest流程名推断为无偏性质。
- Keep inline directory references inside their Code sentence without flattening explicit code blocks or literal line breaks. / Code句内目录保持在原句中，真实代码块及原有换行保留。
- Snapshot the verified same-conversation focused composer anew before each job. Freeze it during translation. Pin a new saved conversation only immediately after the companion's own send; conflicting or unresolved transitions require reconnecting without resending. / 每次任务开始前更新经过核对的同会话焦点输入框，翻译期间冻结目标；只在伴侣受控发送后确认新会话，冲突或无法确认时要求重连且不重发。
- Reproduce observed failures before repairs. Preserve build51's real-test evidence, provider terminology limitations and all prior versions. / 先复现再修复；保留build51实测、翻译术语限制及全部旧版记录。完整回归、安装和实际复核分别记录。
- Pass 27 regression groups with 405 declared checks, 14 loopback HTTP checks, bridge checks and a clean unsigned build; install under the same designated signing requirement. Real Gemini replay still mistranslates the Honest MSE header despite the retained denial; build53 adds a conservative guard for that observed conflict. / 27组405项声明检查、14项本机HTTP、桥接及清洁无签名构建通过，沿原指定签名安装；真实Gemini重放仍误译Honest MSE表头，尽管否定限定语已保留，53继续增加该已知冲突的保守兜底。

## 1.1.7 — 2026-10-06 — build 51 — installed / 清除记录后的读取恢复

- Keep cleared and expired reply identities across translation-pipeline recreation. Do not translate hidden retired messages after restarting reading or changing settings. Explicit history selection may restore a cleared reply. / 清除及过期记录在翻译任务重新创建后仍保持清除状态；重启读取或修改设置不再偷偷翻译已隐藏的消息。手动选择历史可恢复指定回复。
- Reproduce the failure before repair and add three recovery contracts covering visible originals on failure, restart after clearing, new replies and explicit historical recovery. / 修复前复现失败，新增三项恢复检查，覆盖失败时原文显示、清除后重启读取、新回复及手动历史恢复。实际验收单列，保留旧失败记录。

## 1.1.7 — 2026-10-06 — build 50 — installed, actual filename check passed / 保留包裹节点中的句内文件名标记

- Retain a static filename marker through single-span accessibility wrappers and join it only with explicit surrounding sentence spacing or punctuation. Preserve literal source line breaks, code blocks, tables and following paragraphs. / 句内文件名经过单片段界面容器时仍保留标记，仅在两侧明确属于句子空白或标点时衔接；保留原文自带换行、代码块、表格和后续段落。
- Add four paragraph contracts after reproducing the wrapped-reference failure. Build49's observed live failure remains in the execution record; simulation and installation are reported separately. / 包裹节点检查先复现失败，再补四项段落检查。build49真实复核失败继续保留，模拟、安装和实测分别记录。

## 1.1.7 — 2026-10-06 — build 49 — Code homepage and credential recovery / Code 首页、句内文件名与额度争用修订

- Keep an empty desktop Code homepage connected while waiting for its conversation. Unrelated pages and untrusted origins remain excluded. / Code 空白首页等待新会话，不再误判为关闭页面；无关页面和不可信来源仍被排除。
- Preserve flattened static filename nodes inside their Code sentence when explicit inline spacing is present. Keep genuine paragraphs, code blocks, tables and tool-stage boundaries. / Code 采集展开后的静态文件名，有明确句内空白时保持在原句中；保留真实段落、代码、表格和工具阶段边界。
- Apply bounded, cancellable credential-contention recovery to both usage identity reads. Do not retry HTTP requests, authentication failures or credential writes. / 额度请求前后核对登录身份时，对短暂凭据占用作有上限、可取消的等待；不重试 HTTP、认证失败或凭据写入。
- Clear a transient read-wait display after successful unchanged capture, retaining the latest translation success or failure and reusing cached Chinese. / 读取恢复但正文未变时，清除滞留的等待读取提示，保留最新翻译成功或失败状态，复用已有中文。
- Include Google API key patterns in the public repository/history audit, with synthetic-only verification. / 公开仓库与历史检查增加 Google API 密钥模式，使用合成数据验证。
- Reproduce each observed failure before the correction. Candidate regression, installation and live checks are recorded separately; build47/48 failures and all prior records remain. / 先复现已观察到的失败，再修订。候选回归、安装及实际复核另列，保留 build47/48 的失败和全部旧记录。
- Pass 27 local regression groups (378 declared checks), HTTP and bridge checks, then install with the original designated signing requirement. Gemini bilingual checks and desktop usage retrieval succeed; actual Code filename line breaks remain unresolved in this build. / 27组378项声明检查、本机HTTP及桥接检查通过，沿原指定签名要求安装。Gemini双向检查与桌面额度读取成功，但真实Code文件名断行在此构建仍未解决。

## 1.1.7 — 2026-10-06 — build 48 — authorization continuity / 持久授权升级验证

- 功能源码与已通过26组回归的build47一致，只变更内部构建号以验证用户选择“始终允许”后的签名升级授权保留。
- 保留build47和更早版本记录、备份；跨升级实际结果见本轮测试报告，不预先记为通过。
- 实测未通过：旧式钥匙串分区规则匹配build47程序指纹，不匹配build48；系统确实保存了“始终允许”，不能归因于用户未授权。未放宽规则，已恢复功能相同的原build47安装包继续测试，build48备份及失败记录保留。

## 1.1.7 — 2026-10-06 — build 47 — credential contention / 翻译与额度读取争用修订

- 真实桌面Chat首轮复现额度刷新短暂占用钥匙串，导致正式原文显示后回译立即报忙碌；保留失败记录，不记为首次成功。
- 只对密钥读取的短暂占用增加有上限、可取消的后台等待；默认最多等待约两秒。共享访问入口仍立即拒绝占用，认证和不安全策略错误不重试，不重复发HTTP请求，保存操作不加入自动重试。
- 新增临时占用恢复、持续占用停止、认证策略失败、取消等待及保存操作边界检查。先确认旧实现失败，再检查修订；真实复测结果另记。

## 1.1.7 — 2026-10-06 — build 46 — legacy Keychain policy / 旧钥匙串交互策略修订

- Share one fail-fast gate for translation keys, session credentials and usage metadata. Automatic operations disable this process's legacy Keychain interaction; explicit background connection checks briefly allow it and restore the disabled state before returning data. / 翻译密钥、登录会话和额度元数据共用快速失败的访问入口；自动操作禁止本进程的旧式钥匙串交互，明确的后台连接检查短暂允许确认，并在返回数据前恢复禁止状态。
- Do not queue reads behind an authorization dialog. An unconfirmed or failed policy state blocks further queries until restart. Keep modern noninteractive contexts as an additional safeguard. / 不把读取排在授权窗口后无限等待；交互状态无法确认或恢复失败时停止进一步查询，保留现代非交互认证对象作为额外保护。
- Read historical bound keys without automatic copying, keep saves and deletes noninteractive, and move UI save operations to background work. Bound outgoing credential acquisition to ten seconds. / 历史密钥仅按原绑定来源读取，不自动复制；保存与删除保持无弹窗，界面保存操作移至后台，发送前密钥获取限定十秒。
- Isolate regression preferences and prohibit real credentials in simulation. Add eight policy contracts; retain build45's observed legacy-policy failure and all earlier records. / 隔离回归偏好，模拟运行禁止访问真实凭据；新增八项策略检查，保留 build45 实测无弹窗策略失败及全部旧记录。
- The two deprecated legacy API diagnostics are intentional compatibility use, not suppressed. Signed installation and actual authorization are verified separately in the [execution record](docs/testing/follow-up-results-2026-10-06.md). / 两处旧接口弃用警告属于有记录的兼容使用，不隐藏；签名安装及真实授权行为另见[执行记录](docs/testing/follow-up-results-2026-10-06.md)。

## 1.1.7 — 2026-10-06 — build 45 — credential responsiveness / 密钥等待与界面响应修订

- Read saved translation credentials off the main actor; automatic reads use a noninteractive authentication context, while an explicit connection check may request system confirmation. / 已保存翻译密钥在后台读取；自动读取使用非交互认证对象，主动“测试连接”可由系统请求确认。
- Retain the selected provider and endpoint before waiting, and reject late credentials from cancelled requests. Preserve originals and saved keys when access is unavailable. / 等待前固定服务和接口来源，取消后拒绝迟到凭据；无法访问时保留原文及已保存密钥。
- Add four credential access contracts without reading real keys. An authentication-service restriction in the test sandbox was reproduced and separately checked in a normal process. / 新增四项不读取真实密钥的检查；测试沙盒认证服务限制已复现并在普通进程另行核对。
- This build also includes the build44 candidate's table-definition correction. Installation and actual Keychain behavior are recorded separately; no claim of permanent authorization is made from simulation. / 包含 build44 候选的表格定义修订；安装及真实钥匙串行为单列记录，不从模拟结果宣称永久授权已完成。见[执行记录](docs/testing/follow-up-results-2026-10-06.md)。

## 1.1.7 — 2026-10-06 — build 44 — candidate / 表格定义修订候选

- Match explicitly defined statistical labels across Markdown emphasis and narrowly defined affirmative `is` clauses. Keep the original text unchanged and reject ambiguous or negative definitions. / 明确统计定义可跨 Markdown 强调标记及范围有限的肯定 `is` 句匹配；原文不变，不猜测含糊或否定定义。
- Pass 24 regression groups (346 checks) and an actual system-translation sample with a bold definition below a table. Build44 was constructed but not installed; previous failures and provider prose limitations remain recorded. / 24 组 346 项回归及表格下方加粗定义的实际系统翻译样本通过。build44 已构建但未安装；旧失败和供应商正文措辞局限保留。

## 1.1.7 — 2026-10-06 — build 43 — CLI ordering correction / CLI 正文顺序修订

- Buffer a bounded number of concurrent MessageDisplay batches and assemble them in sequence. Do not publish missing prefixes, duplicate replayed batches or invent absent text. / 对同时到达的正文批次作有界暂存，按序拼接；不显示缺失前缀，不重复追加重放批次，不猜补正文。
- Treat startup statusLine reports without subscription windows as unknown, preserving the existing usage source. / CLI 启动时尚无订阅额度字段，按未知处理，不误报为无效连接，也不补假零或切换既有来源。
- Include explicit definitions immediately below a table in cell context. Ignore unrelated appended prose so it does not restart in-flight cell translations. / 表格下方的明确术语定义也作为单元格语境；无关的后续正文不触发在途单元格重译。
- This correction follows an observed out-of-order CLI delivery in build42. Validation and remaining live gaps are recorded separately; existing failures and history remain. / 修订依据 build42 真实 CLI 中观察到的批次乱序；验证及未测项见[执行记录](docs/testing/follow-up-results-2026-10-06.md)，保留既有失败和历史。

## 1.1.7 — 2026-10-06 — build 42 — filename and table protection / 文件名与表格保护

- Protect ordinary filenames locally for all translation providers. / 所有翻译方式共用本机普通文件名保护。
- Share bounded, separate table context with compatible AI services and Gemini. Use explicit unambiguous source definitions for system table labels. / 兼容 AI 与 Gemini 共用独立且受限的表格语境；系统表头采用原文明示且无冲突的定义。
- Add metadata-only Gemini HTTP status evidence and repair language-check compilation dependencies. / 增加仅含状态的 Gemini 请求证据，并补齐语言检查编译依赖。
- Preserve the fixed signing identity, settings, prior versions and test records. System prose semantics still require review; accurate table labels do not prove every statistical sentence is correct. / 保留固定签名、设置、旧版本与测试记录；系统正文语义仍须核对，表头正确不代表所有统计句子均准确。

## 1.1.7 — 2026-10-06 — build 41 — paragraph continuity / 段落连续性修订

- Assemble inline links, file references and whitespace-separated emphasis inside their paragraph before joining actual paragraph containers. Preserve list items, literal code lines and Code stage boundaries. / 先在段落内合并句内链接、文件引用及带空白的强调文字，再合并真实段落；保留列表项、代码原有换行和 Code 阶段边界。
- Trim provider-added whitespace at translation slice edges and collapse extra line breaks in single-line prose slices, using the shared system/AI translation path. Preserve intentional multiline source and table-cell escaping. / 在系统与 AI 共用流程中清除翻译片段首尾新增空白，合并单行正文中额外插入的换行；保留多行原文结构及表格单元格转义。
- Reinforce one-paragraph translation instructions and reject abnormal short-cell output containing whole context paragraphs. Originals, completed Chinese and explicit retry remain available. / 强化单段翻译规则，拒绝将整段语境误填进短表头的异常结果；保留原文、已有中文和明确重试提示。
- Retain all previous build records, including build40's subsequent authorized installation and unsuccessful table-context retest. / 保留全部旧构建记录，包括 build40 后续获授权安装及表头语境仍不合格的复测；本轮证据见[段落排版记录](docs/testing/paragraph-layout-2026-10-06.md)。

## 1.1.7 — 2026-10-06 — build 40 — candidate / 本地修订候选

- Parse the full source on every reply update before skipping translated prefixes, retaining table context, numeric protection and cell escaping during repeated polling or appended rows. / 回复更新时先解析完整原文再跳过已译前缀，重复读取或增加表格行时继续保留语境、数字保护及单元格转义。
- Keep outstanding translation failures visible after another stage succeeds; retry only unfinished slices. / 后续分段成功后仍显示尚未解决的翻译失败，重试仅处理未完成片段。
- The authorized third Code task demonstrated an early Chinese stage, but another stage remained untranslated and table terminology failed. Total logged Gemini attempts exceeded the batch limit; monitoring and online testing were stopped. / 获授权的第三个 Code 任务证明阶段中文提前出现，但另一个阶段未译、表格术语错误；日志累计 Gemini 尝试超过本批上限，已停止读取和在线测试。
- This candidate is verified locally and is not installed or presented as fully live-tested. All previous builds and verification records remain. See [supplement results](docs/testing/real-code-supplement-results-2026-10-06.md). / 候选仅完成本地验证，未安装，不宣称真实测试全部通过；保留全部旧构建及证据。详见[补测结果](docs/testing/real-code-supplement-results-2026-10-06.md)。

## 1.1.7 — 2026-10-05 — build 39 — contextual table translation / 表格语境修订

- Give Gemini bounded nearby prose and table words for cell meaning, isolated per translation task. Translate only the selected cell; keep numbers, code, URLs, formulas and table geometry local. / 为 Gemini 提供有限的相邻正文及表格文字以判断单元格词义，每个翻译任务独立；仍只翻译指定单元格，数字、代码、网址、公式与行列结构在本地保留。
- Recognize CSV and TSV result references without discarding the entire formal file list. Keep standalone punctuation and numeric fragments local. / 识别 CSV、TSV 结果文件引用，避免丢弃整份正式文件列表；独立符号及纯数字片段不请求翻译。
- Request character counts include contextual data; previous builds and live-test limitations remain recorded. / 请求字符计数包含上下文；保留全部旧构建与实测限制记录。

## 1.1.7 — 2026-10-05 — build 38 — Code streaming and tables / Code 流式与表格修订

- Identify the explicit streaming Code renderer after a verified user anchor, retaining the eventual message identity before turn completion. Reject ambiguous boundaries and exclude its activity footer. / 在已核对用户消息之后识别 Code 的明确流式容器，任务结束前沿用最终消息身份；不确定边界继续等待，排除流式运行提示。
- Preserve ordinary accessibility table rows as Markdown; translate cell text while keeping numbers, code, formulas and delimiters locally. Render Chinese tables with horizontal scrolling and Markdown copy. / 将普通辅助功能表格按行列保存为 Markdown；翻译单元格文字，数字、代码、公式和分隔符留在本地；中文表格支持横向滚动及 Markdown 复制。
- Retain all earlier build entries and test evidence. Code live validation is recorded separately; development checks do not imply every real source passed. / 保留全部旧构建历史与测试证据；Code 实测另行记录，不用开发检查代替所有真实入口验收。

## 1.1.7 — 2026-10-05 — build 37 — history navigation correction / 历史阅读定位修订

- Selecting an already translated historical reply opens that reply at its beginning and shows its saved Chinese without another cloud request. / 选择已经翻译的历史回复时跳到该条开头，复用已有中文，不再次调用云服务。
- Replace the selection prompt with a ready status after a cached result is selected. / 选中已有译文后显示就绪提示，不再停留在“请选择”。
- Retrying the same failed unsent draft replaces its pending row while keeping a fresh attempt identity. / 同一未发送草稿翻译失败后重试不再新增重复消息，保留新的任务身份以拒绝旧任务的迟到结果。
- The three authorized desktop Chat research prompts produced exactly three Claude replies. Gemini returned intermittent 503 errors; Chinese completed after retries, so uninterrupted translation is not declared passed. / 已授权的三轮桌面 Chat 研究问题只产生三条 Claude 回复；Gemini 间歇返回 503，中文在重试后取得，不宣称全程连续翻译通过。

## 1.1.7 — 2026-10-05 — build 36 — formal reply correction / 正式回复识别修订

- Use the author heading's answer preview to find the start of a flat desktop reply; exclude preceding thinking summaries while retaining repeated formal paragraphs. / 根据作者标题中的正式正文预览确定读取起点，排除前面的思考摘要，保留正文中有意重复的段落。
- Unmarked flat assistant content remains pending until a formal answer is identifiable. / 没有可核对正式正文的平铺内容继续等待，不当成回复翻译。
- Coalesce completed reply paragraphs within the existing 3,000-character boundary; streaming paragraphs and Code stages remain incremental. Log request character counts without text or credentials. / 完成回复在原有 3,000 字符分块范围内合并段落；流式段落和 Code 阶段继续及时翻译，请求日志只记录字符数。
- Live validation continues on the existing research conversation; no extra research topic is generated. / 在现有研究会话继续实测，不新增研究话题。

## 1.1.7 — 2026-10-05 — build 35 — desktop test correction / 桌面实测修订

- Restrict Gemini to literal translation and encode source requests separately from translation rules, retaining questions and response constraints. / 强化 Gemini 的纯翻译角色，原文作为独立数据传入，保留提问和回复约束，避免代替 Claude 回答。
- Record only counts and whitespace flags when paste verification fails; no message content or keys are logged. / 粘贴核对失败时仅记录字数和换行标记，用于定位兼容性问题，不记录正文或密钥。
- Real desktop academic testing is in progress; this entry does not declare the live scenarios passed. / 真实桌面学术场景仍在测试，本条不代表实测通过。

## 1.1.7 — 2026-10-05 — build 34 — development / 开发待真实验收

- Publish formal originals immediately and translate stable fragments independently, returning Chinese per slice before turn completion; retain translated prefixes and reject retired/configuration/session results. / 正式原文立即显示，稳定片段独立翻译并逐块回传中文，无需等整轮结束；保留已译前缀并拒绝失效结果。
- Keep same-record ordering, scroll position and selection; preserve ten translated records and explicit clear/retry/cancel behavior. / 同条原位更新，不抢滚动，维护选区、十条译文和清除／重试／取消流程。
- Bind compatible-service keys and model preferences to normalized endpoints; add OpenAI/Grok presets without changing native Gemini. / 兼容服务密钥和模型偏好绑定接口来源，新增 OpenAI/Grok 预设，Gemini 原生配置保持。
- Add passive health checks, cooldown and server wait handling, structural code/URL/path protection, and bounded AX traversal. / 增加被动状态检查、冷却及服务等待处理，保护代码／URL／路径并限制 AX 遍历预算。
- Check credential presence without reading secret data or prompting; keep dated official policy links and scrollable details within the narrow window. / 无弹窗检查密钥元数据，不读取正文；内置有日期的官方政策链接，详情在窄窗内滚动。
- Add opt-in read-only CLI/Chrome transport and visible Usage/statusLine sources with explicit binding and rollback-safe migration. / 新增主动启用的 CLI／Chrome 只读桥接及可见 Usage／statusLine 用量来源，明确绑定，迁移后旧版本不会自动读回旧来源。
- Keep all previous history and signing scripts. This is a simulation-verified development build; real Claude, cloud services, production installation and personal adapter configuration remain separately gated. / 保留旧历史及签名脚本；这是仅模拟验收的开发构建，真实 Claude、云服务、正式安装及个人配置仍须另行指令和授权。具体结果见 [本轮报告](docs/testing/optimization-implementation-report.md)。

## 1.1.6 — 2026-10-04 — builds 32–33

- Add a separate Gemini translation choice using Google's native `generateContent` API, with `gemini-3.1-flash-lite` pinned by default. Both message translation and Chinese reply translation use the selected provider. / 新增独立 Gemini 翻译，直接使用 Google 原生接口，默认固定 Gemini 3.1 Flash-Lite；中文发送和回复回译共用配置。
- Preserve system translation and OpenAI-compatible profiles. Store the Gemini key in its own Keychain item, and persist the provider/model across restarts and normal updates. / 保留系统翻译及原有 AI 配置，Gemini 密钥独立存入钥匙串，翻译方式和模型支持重启及正常升级记忆。
- Add a cancellable connection check using two fixed synthetic sentences, without accessing chat content or saving an unsubmitted key. / 增加可取消的双向连接测试，仅用两句固定文字，不读取聊天或保存未提交的密钥。
- Explain project quotas, billing, free-tier data use, and credential errors. Reject incomplete/blocked translations; retry truncated long chunks at smaller sizes while preserving original text and existing limits. / 提示项目额度、费用、免费层数据规则及凭据错误；拒绝不完整或受限译文，长文截断自动缩段重试，保留原文和原有长度限制。
- Add twenty-two application regressions and seven loopback HTTP checks, for totals of 213 and 14. Preserve the existing signing identity and all earlier history; native/live evidence is recorded separately in TEST_PLAN. / 新增二十二项应用回归和七项本机 HTTP，合计 213／14 项；保留原签名及全部历史，界面和真实接口证据单独记录在 TEST_PLAN。
- Build 33 identifies Google's explicit project-access denial in a 403 response and directs users to project status/support, instead of treating it as an invalid key. Remote error text and project identifiers remain hidden. Two additional regressions bring the application total to 215; Google project access cannot be restored by this app. / build33 识别 403 中 Google 明确拒绝项目访问的原因，引导核对项目状态及联系支持，避免误导用户检查正确的密钥；仍不显示远端正文及项目标识，新增两项回归后合计 215 项。伴侣无法替 Google 恢复项目权限。

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
