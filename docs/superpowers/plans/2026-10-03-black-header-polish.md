# 黑色顶部与通透聊天界面实施计划

**Goal:** 实现用户要求的黑色顶部和更通透玻璃，实际安装验收。

**Architecture:** Main.swift 配置原生标题栏，GlassBackground.swift 负责原生磨砂和减少透明度适配，Views.swift 调整聊天布局。ClaudeUsageCore.swift 仅修正显示格式，账户读取和发送逻辑保持原有结构。

**Tech Stack:** SwiftUI、AppKit、Foundation，macOS 15+。

- [x] Tests/UsageTests.swift：用实际时间 2026-10-09T20:59:59.851728+00:00 重现分钟显示偏差，覆盖跨日及普通分钟；先运行失败测试。
- [x] ClaudeUsageCore.swift：格式化前按最近 60 秒四舍五入，明确 HH；Tools/CheckClaudeUsage.swift 让诊断原文和解析来自同一请求。运行 UsageTests 和 UsageMonitorTests。
- [x] Main.swift：fullSizeContentView、隐藏原生文字标题；黑色品牌区延伸到原生标题栏，保留关闭和缩放按钮。用户追加指定当前窄窗：默认 610 × 780 点，最小 610 × 710 点。
- [x] GlassBackground.swift：保留 underWindowBackground 原生材质，透明度由 1 降到 0.92；开启减少透明度时用不透明背景。实际预览发现 hudWindow 太亮，已排除。
- [x] Views.swift：黑色品牌区；单行语言/连接工具区；欢迎说明更简洁；输入区和气泡 ultraThinMaterial、轻描边；明确输入字数和发送主按钮，保持原有操作及长文本阅读区。
- [x] CompanionIcon.swift：原品牌纯色 #D97757 经用户反馈偏淡后，直接对照本机 Claude 图标；背景改为 #D97757 → #DB6944 轻微渐变，A、眼睛及鼻孔 #D9704E，猪头 #FAF9F5，鼻头浅橙；template 分支保持单色。生成、采样并查看应用图标。
- [x] build.sh / README.md：版本 1.1.3 build17，说明黑色顶部和通透玻璃、24 小时重置时间及实物取色。
- [x] 正式安装后使用 CUA 检查黑色标题、欢迎页、四种语言、草稿、设置及额度刷新；用本地独立聊天夹具检查短/长回复布局及最小窗口，不向 Claude 发送测试消息。
- [x] 验证签名身份与自动额度连接保留，完成文档、git diff --check、提交并同步现有私人 GitHub 仓库。

追加账户来源问题：用户询问 web / CLI / 桌面登录。官方说明同一 Claude 账户的不同入口共享订阅额度，API 密钥调用不使用订阅额度。当前明确展示桌面 / 指定 session 来源；不把未核实的浏览器或 CLI 账户默认为桌面账户，不宣称已实现自动浏览器账户或 CLI OAuth 读取。

用户后续明确本次只完成桌面端和网页版，不加入 CLI 或 API 计费。8 项额度解析／显示测试和 8 项连接集成测试通过；正式程序实际中译英成功，最小窗口和本地短／长对话已检查。最终 build16 橙色图标、无重复授权的启动额度读取、手动刷新及精确身份校验通过。真实 Claude 多轮发送验证仍保留在 TEST_PLAN.md 中，未以本地界面预览替代。

build17 按本机 Claude 实际图标校准橙色及渐变。正式安装包图标采样中位值 #DA704E，原 Claude #D9704E；原生窗口查看通过，启动已连接额度读取成功，原签名身份校验通过。纯色版 build16 的手动刷新验证不受此图标修改影响。
