# A畜伴侣只读桥接 / Read-only bridge

## 当前网页额度连接（build77）

在已指定Claude网页后，从伴侣「连接额度 → 网页端」发起授权。程序准备额度模块和本机接口，浏览器只显示正常安装授权；无需加载文件夹、填写ID或自行配置native host。已有获准运行的Tampermonkey是本机接入条件，正式商店组件尚未发布。授权后「连接已指定网页」返回原手选输入区并配对；刷新为补充。不读取Cookie或正文，只传遮蔽账户与额度。见[验收与限制](../docs/testing/companion-managed-web-usage-2026-10-08.md)。

English: The companion prepares the quota-only module and loopback interface. Users handle normal installation authorization, without folders or IDs. A permitted Tampermonkey runtime is currently required; the Store component is not yet published. The companion pairs the previously selected page. No Cookie or chat text is relayed.

下方按原版本保留历史流程；当前三端发送以build74手选输入规则为准，旧版接收核对和质量审核不再适用。

## build69：CLI自动填入

桥接传输仍然只读；自动输入由伴侣独立的本机窗口绑定完成。在已登录Claude Code的输入区（可保留推荐文字）按实体 **Control＋Option＋E**，核对底部会话编号和20位「输入」标记。只在唯一匹配当前窗口、焦点、会话及存活前台CLI进程后启用自动填入；单独选择会话只开启读取和额度，不凭最新报告猜测发送目标。旧无输入标记报文保持只读。

中文翻译后粘贴一次。短单行全文核对后，可按「填入后发送」偏好自动回车；多行、表格及折叠长文需在终端确认。切源、焦点变化、进程挂起/退出、取消或迟到结果停止后续按键，临时重绘在同一次粘贴后等待。不会写入TTY、发送socket控制命令或改变终端品牌设置。来源仅附加PID、TTY、启动时间和绑定标记，不附加进程参数、凭据或正文。[模拟结果与真实验收](../docs/testing/cli-automatic-input-2026-10-07.md)。

English: The bridge transport remains read-only. A separate local GUI binding checks the original focused surface, current footer/session and live foreground CLI process before pasting once. Verified single-line receipt permits optional Return; multiline/table/collapsed pastes require terminal confirmation. Source/focus/process changes or cancellation stop further keys. Older reports remain read-only, and choosing a reply source alone does not authorize input. No TTY writes or socket control commands are introduced.

## build68：CLI 会话选择与复制译文（历史）

主界面点击「连接 CLI」，或在已登录的 Claude Code 终端按实体键盘 **Control＋Option＋E**，打开会话选择页。对照终端底部「A畜伴侣 CLI · 编号」选择同一编号；候选显示目录末级名、模型、最近接收报告时间及正文状态，不按终端品牌识别，也不自动猜选最新会话。不同会话分别保留；同一 session_id 切换工作目录保持同一连接。目录只传末级名，不传完整路径。

连接后中文按回车或「仅翻译」得到外文，点击「复制译文」，回到 Claude Code 按 **⌘V** 粘贴并确认发送。每条已完成的中文发送记录也有「复制译文」，清空或修改草稿后仍可复制历史外文。CLI 连接为只读，不显示无法使用的自动发送控件，不向终端模拟回车。已有用户状态栏仍保留；收到额度报告不代表已收到回复，也不代表服务器刷新。

来源摘要为可选字段，旧报文仍兼容。升级只迁移精确匹配的本会话旧账户状态，保留失效或冲突身份隔离及原文件；不猜测当前登录，也不扫描全部聊天。正式回复入口仍须核实当前 Claude Code 的 MessageDisplay 支持，只有 statusLine 不能读取正文。

English: Open **Connect CLI**, or press physical **Control+Option+E** in Claude Code, then match the companion's session identifier to the terminal footer. Directory basename, model, local report time and body status distinguish candidates without depending on terminal brand or automatically selecting one. A session keeps its identity across directory changes. Translate Chinese, click **Copy translation**, paste with **⌘V**, then confirm submission in the terminal. Completed outgoing history retains its own copy action. User status-line output and invalidated-account isolation are preserved. Status-line usage alone does not supply reply text; MessageDisplay support must be verified separately.

下面保留历史版本的配置和验收记录；当前CLI操作以build69流程为准。[build68修复记录](../docs/testing/cli-workflow-repair-2026-10-07.md)。

## build56：连接聊天时自动取得对应额度

额度跟随所连接的聊天来源；设置的获取按钮是补充。首次安装入口后，桌面绑定、网页绑定或只读 CLI 来源选择会自动核对并获取本来源额度，不需要再勾选账户连接。切换来源先隐藏旧值，不将另一端登录混入当前来源。

- **桌面**：绑定 Claude 输入框即无弹窗读取当前桌面登录。钥匙串尚未允许时明确提示，在设置中使用桌面读取入口处理一次；自动刷新不循环弹窗。
- **网页**：在设置 → 网页端 → 配置网页入口中打开扩展文件夹。Chrome/Edge加载入口后，填写32位扩展ID，点“连接网页入口到伴侣”；在需要的 claude.ai 标签点击图标启用，然后连接聊天。也可点“获取网页额度”补充获取。每次在该标签当前浏览器会话中同源读取 `/api/account`，请求唯一组织的 `/usage?skip_spend=1`，再核对账户；浏览器自动携带现有登录，不读取或转发 Cookie。多组织、身份变化、失败或结构变化立即不采用。Safari 尚无入口包，不宣称支持。
- **CLI**：设置 → CLI → “配置 CLI 入口”，保留原状态栏并安装本工具 SessionStart/statusLine。在任意终端启动新的 `claude` 会话，正常完成一次回复，在状态检查选择该只读来源；额度随连接自动取得。也可点“获取 CLI 当前报告”，实际请求官方 CLI 重跑状态栏。它不是官方服务器新查询，数据来自 CLI 最近报告；没有字段时显示未提供。可用“移除 CLI 入口，恢复原状态栏”撤回本工具设置。不会安装未经核实的 MessageDisplay。

网页额度网络请求与正文采集并行，不使原文/翻译等待额度。每次完整回复及每60秒尝试获取；停用入口或导航时丢弃未完成请求。服务器接口不是公开稳定 API，需分别实测真实浏览器；尚未完成的项目见专项报告，不能以本地模拟替代。

English: Connecting a chat follows that exact usage source automatically. Settings provide recovery and opt-in setup. The Web adapter makes same-origin read-only account/usage requests using the browser's existing session, verifies identity before and after, and relays only masked identity and subscription windows. Multiple organizations are rejected rather than guessed. CLI requests a new official status-line report, not a proven server refresh; it preserves user settings and provides removal. Quota networking never blocks reply capture. Safari and real browser acquisition remain subject to separate acceptance.

## 之前版本的边界与基础安装步骤（保留记录）

1.1.7 的 CLI / Chrome 入口是实验功能，默认关闭。CLI 已在官方 2.1.292 中完成两轮隔离实测：计划和最终正文能读取，其中一轮英文计划的中文在最终正文结束前显示；三段正式回复的条件未形成，不能视为全部阶段验收。Chrome 只读扩展仍只有模拟证据，没有在本批安装；浏览器 AX 适配与带模拟脚本的网页测试另行记录，不能代替官方网页服务验收。详情见[本轮进度矩阵](../docs/testing/follow-up-status-2026-10-06.md)。桥接不会发送消息、读取 Cookie/OAuth、改变模型或执行网页指令，不替代原有桌面 AX 连接。

## 连接方式

1. 在伴侣「状态检查」中主动启用只读桥接，复制连接文件路径。
2. 按以下方法安装所需入口。本轮开发没有操作任何个人配置；真实安装须先得到用户单独授权。
3. 正常会话产生报告后，伴侣列出来源。明确点击要读取的来源；不会自动把任意标签或终端绑定为当前目标。
4. 桥接输入仅支持翻译/复制；不向任意终端模拟回车。停止读取关闭桥接及其本机端口。

连接文件包含临时本机令牌，应视为私人文件：不要提交、贴到聊天或截图。目录权限 700，文件和 socket 权限 600。正常安装使用 `~/Library/Caches/local.achu.companion/bridge/connection.json`，重启时轮换令牌；模拟使用临时路径。它没有云服务 key，也不会保存正文。

## CLI：先用量，后确认 MessageDisplay

需要 Python 3.9+ 和用户已经安装的官方 Claude Code。先核对该版本是否支持 `MessageDisplay`；只支持 statusLine 的版本可以单独接额度。安装不会调用 Claude 来消耗额度或制造回复。

在经过授权的配置目录中运行，路径均明确填写：

```bash
python3 Bridge/bridge.py --install-cli --config-dir /path/to/approved/config --connection /path/to/private/connection.json
```

已确认支持正式 MessageDisplay 的版本，可增加 `--message-display-supported`。未确认时默认不安装回复 hook。先安装 statusLine 后要加入 hook，先卸载，再以该选项安装。交互模式逐行批次；非交互模式可能一次给出完整消息，不能宣传同等实时。

```bash
python3 Bridge/bridge.py --uninstall-cli --config-dir /path/to/approved/config
```

安装保存本项目条目和原 statusLine 的最小恢复记录（600 权限），中断可重试。卸载只撤回本项目 hook；若用户后来修改 statusLine，保留后改值。已有 statusLine 以原输入运行并保留输出；桥接传输超时 250ms，不等待翻译。确认原 statusLine 的运行时限是否适合该机器，真实验收后再启用。

从消息中间接入时，缺失的前半段不被猜测；等待新的完整消息。`final` 表示单条消息结束，不能代表整个工具任务结束。CLI 没有网页视野信息，因此不列入“当前可见历史回复”。

## Chrome：用户主动启用的标签

扩展目录为 `Bridge/chrome`，MV3，权限仅 `nativeMessaging`、`storage` 和 `https://claude.ai/*`。Storage 只保留本次浏览器会话主动选择的标签编号；不保存正文、Cookie 或 token。

1. 获授权后加载该扩展，记下准确的 32 位扩展 ID。
2. 生成与该 ID 唯一绑定的 Native Messaging host 文件：

```bash
python3 Bridge/bridge.py --install-native --output-dir /path/to/approved/native-host-directory --extension-id abcdefghijklmnopabcdefghijklmnop --connection /path/to/private/connection.json
```

示例 ID 只是格式示例，不是真实 ID。真实 Chrome 使用其 Native Messaging 目录；本轮仅在临时目录模拟。

3. 在要读取的 Claude 标签点击扩展图标启用，再在伴侣选择对应来源。其他标签默认不采集。图标 ON 表示最近传输成功；`!`/`?` 表示连接断开或数据未接受。
4. 只读取正式正文，排除工具/思考/操作按钮，恢复代码围栏与行内代码。历史选择只列实际与视口相交的完成回复。每五秒完整快照用于重连；重复报告不会重复翻译，也不会将相同额度刷新为新证据。
5. 同标签导航换代次，旧页迟到报文拒绝；后台暂停或页面结构不支持时等待新同步。卸载扩展并移除本项目生成的 manifest/launcher 即撤销入口，不删除 Chrome 登录资料。

用量页仅在用户主动打开并启用的官方 `/settings/usage` 页面读取。该页面关闭或冻结不会查询新额度；伴侣保留旧值并注明时间。来源账号需在连接页明确确认，未确认不覆盖现有账户。

## 模拟验证

```bash
./test.sh
./test-bridge.sh
./test-http.sh
node --test Tests/BridgeChromeTests.cjs Tests/BridgeWorkerTests.cjs
```

可选浏览器 DOM 测试需要本机 Playwright 和 Chrome，使用独立临时配置并拦截全部页面请求：

```bash
ACHU_PLAYWRIGHT_MODULE=/path/to/playwright node Tests/BrowserAdapterSmoke.cjs
```

真实兼容性、安装/卸载和断线恢复按 [真实测试方案](../docs/testing/real-environment-test-plan.md) 单独验收。

## English

The 1.1.7 adapters remain experimental, opt-in and read-only. Two isolated sessions on official Claude Code 2.1.292 verified plan and final-body delivery; one English plan was translated before the final body ended. A three-formal-stage condition was not produced, so complete stage coverage is unverified. The Chrome bridge extension has only synthetic evidence and was not installed in this batch. Browser AX tests with a mock script do not establish official web-service compatibility. See the [current matrix](../docs/testing/follow-up-status-2026-10-06.md). The adapters do not send messages, read login credentials, change models, or run page commands. Live installation and testing require separate user authorization.

Enable the local bridge, install the desired adapter in an explicitly approved directory, then select its source in the companion. Confirm `MessageDisplay` support before enabling the hook; otherwise install statusLine alone. Existing terminal output and unrelated hooks are preserved. Uninstallation keeps later user changes. CLI history has no viewport guarantee and is excluded from visible-history selection.

The Chrome extension reads only enabled top-level Claude tabs. It uses native messaging and session storage, with no cookie, debugger, or all-site access. Full snapshots support recovery after reconnect; navigation epochs reject old-page events. Only completed replies intersecting the viewport are offered as visible history. Connecting the chat automatically follows its verified account/source usage; settings are supplementary. Unverified identity clears previous usage, and another channel's login is never used as a fallback.

Connection files contain private rotating local tokens. Do not publish them. Chat text is kept only in memory; no model API credentials are shared with the bridge. See the independent live test plan before claiming compatibility with a real Claude installation.
