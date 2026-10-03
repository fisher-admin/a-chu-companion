# 持续读取 Claude Implementation Plan

> 按用户已指定的交互在当前工作区逐项实施；使用本会话的调试、测试先行和完成前验证流程，避免另建任务或重复审批。

**Goal:** 连接即持续读取 Claude 正式回复，允许直接在 Claude 输入，长中文译文从头阅读；可见历史回复供选择，保留本次运行最近 10 条译文。

**Architecture:** 用会话级回复跟随代替单次发送绑定；作者正文与生成状态共同确定可翻译回复，监测与发送生命周期分离。串行翻译队列保留每条完整回复，气泡具有按会话与序号稳定的身份。聊天滚动到更新气泡顶部，原生长文本框保留独立可见滚动条。

**Tech Stack:** Swift、AppKit、SwiftUI、Accessibility、Translation。

## 1. 会话级追踪与完成识别

Files: Sources/ReplyCore.swift、Sources/ClaudeAccessibility.swift、Tests/ReplyTests.swift。

- [x] 写失败检查：连续两条 Claude 原窗口输入、空会话、生成期间稳定停顿不输出、同一回复改写、已翻译回复不重复、会话变化拒绝旧 tracker。
- [x] 运行 swiftc Sources/Core.swift Sources/ReplyCore.swift Tests/ReplyTests.swift；确认行为断言失败。
- [x] 实施 ConversationReplyTracker：init(baseline:conversation:) 初始化当前尾部；observe(conversation:messages:responseComplete:now:) 返回按序完整候选；isCurrent(_:) 供任务与队列核对当前版本。
- [x] ClaudeSource 的 ReplySnapshot 增加 responseComplete。界面树读取结束提示及停止按钮，旧消息的工具区域不影响最新回复完成判断。会话历史的旧缺号仅形成尾部边界，不排除完整最新消息。
- [x] 检查当前窗口的根区域变化并重新寻找当前 claude.ai 区域；所有内容仅来自绑定窗口。
- [x] 运行回复回归，检查未标记最新消息仍拒绝，代码完整，旧结果不会进入新会话。

## 2. 连接、监测和发送分离

Files: Sources/ReplyMonitor.swift、Sources/TranslatorModel.swift、Sources/Main.swift、Tests/ModelTests.swift。

- [x] 写失败检查：停止保持、普通发送取消不停止读取、连续候选排队不覆盖、原文与中文使用稳定气泡。
- [x] ReplyMonitor.connect 只绑定窗口，立即 watching=true，再由轮询完成首个快照初始化。持续等待临时不完整快照，不限制单次发送等待时间。
- [x] 轮询采集完整候选入队；当前译文结束／失败后处理下一条，只有同序号改写或停止／会话变化取消旧任务。
- [x] TranslatorModel.prepareTarget 连接后调用 startReplyReading；finish 不 arm 或 restart；failed/cancel 只处理发送；明确停止和重新开始读取保留。
- [x] 超限原文保留并继续监测，不停止整个会话。
- [x] 运行模型、权限及回复检查，覆盖旧任务取消保护。

## 3. 回复开头及滚动条

Files: Sources/TranslatorModel.swift、Sources/Views.swift、Sources/MessageText.swift、Tests/EditorTests.swift。

- [x] 写失败检查：recordReplyOriginal／recordReply 把滚动目标设为回复 id 顶部；长阅读框换文本时回到零点，未换文本保留阅读位置。
- [x] Views 根据目标用 scrollTo(id, anchor: .top)，发送与清空使用 bottom；顶部连接提示后显示停止／开始读取，删除重复的自动读取开关。
- [x] LongMessageReader.updateText 更新正文时 scroll(.zero)，legacy scroller 且不自动隐藏；完整文字和可选择／复制保留。
- [x] 运行原生编辑器检查，验证完整头尾和滚动位置。

## 4. 历史选择与最近十条

- [x] 写失败检查：12 条完整译文只留下最后 10 条；重新翻译同一身份不重复，退出后不恢复记录。
- [x] ClaudeSource.captureVisibleReplies 以窗口、输入框和滚动区的位置过滤可见完整正式回复；不读取整页文字。
- [x] ReplyWorkQueue 将历史任务与自动任务统一排队；切换会话保留手动选择的原文，退休旧自动任务。
- [x] Views 显示多候选列表、聊天区上方「清除记录」和运行期间保留提示；只有一个候选直接翻译。
- [x] 清除保留草稿和监测，取消未完成回复防止回写。157 项完整回归通过。

## 5. 原生验收与交付

Files: Tests/fixture.html、build.sh、README.md、TEST_PLAN.md。

- [x] 增加夹具生成状态与每轮不同回复；先思考 12 秒、生成停止提示、工具卡片及长正文齐备。
- [x] 完整 ./test.sh、./build-fixture.sh、./install.sh。正式 build28 用现有身份签名安装，CUA 打开。
- [x] 用户实体连接后，本机直接两轮＋伴侣一轮均自动读取，停止＋恢复通过，长回复头尾／滚动条通过。历史列表选择单独检查；自动验收不依赖历史按钮。
- [x] 恢复真实 Claude 连接，只读现有完成回复并检查自动显示；不发送真实测试消息。记录确实完成与未验证部分。
- [ ] git diff --check、自审、提交并推送用户已有 GitHub 仓库，核对远端与本机一致。

## 追加布局

- [x] Claude 助手气泡移除右侧 35 点占位，阅读区右边距缩至 8 点，扩大正文可用宽度。
- [x] 读取提示移至输入框上方，减少页头、输入区和控件间距，正常状态不重复展示发送提示。
- [x] 五小时及每周额度采用线性进度条＋百分比＋重置时间，缺失数据不画成零；90% 以上用橙色。
- [x] 正式 build28 原生布局复核。

- [x] 顶部三项操作并排，进度条随额度区宽度伸展；底部操作合并一行。
- [x] build28 默认 610 点窄窗口、已有译文时的单行操作及顶部设置入口原生复核。
