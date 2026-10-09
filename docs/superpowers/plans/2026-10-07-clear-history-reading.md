# 清除记录后的阅读提醒修复

> 按已授权的测试修复范围在当前会话执行，使用 systematic-debugging、test-driven-development 和 verification-before-completion；不另建工作树、不提交或发布。

**Goal:** 清除所有记录后不再显示“有新内容”，下一条回复正常定位，并保留草稿和持续读取。

**Architecture:** 清除记录仍退役原消息并取消旧翻译；随后调用已有 `resumeFollowing()` 同步重置阅读状态、提醒和滚动定位。不改变消息来源、额度账户或翻译规则。

**Evidence:** build54安装版实际执行历史选择、清除、新回复、停止读取后，空记录界面仍显示“有新内容”。`clearHistory()`只清空列表和定位，遗漏 `readingHistory`、`hasNewContent`；`resumeFollowing()`已提供完整状态重置。

**Tech Stack:** Swift/SwiftUI，现有模型与读取恢复测试。

- [x] 在 `Tests/ModelTests.swift` 用历史阅读时到达新回复、随后清除的流程断言提醒消失、自动跟随恢复，下一条原文正常定位；先运行确认旧实现失败（退出133）。
- [x] 将 `Sources/TranslatorModel.swift` 的清空定位收尾替换为 `history = []; resumeFollowing()`。
- [x] 运行 Model22、ReadRecovery6、Optimization6、OptimizationLifecycle7，共41项；构建并沿原签名安装build55，保留build54备份。
- [x] 在安装版用本机合成历史与新回复重现原流程，核对清除后没有提醒、草稿保留、下一条仍取得；关闭测试来源、清空模拟草稿与记录、恢复Gemini，确认连接文件移除。
- [x] 追加版本和测试结果，不把本机合成验证记为真实Claude验收。完整三来源、可见终端及两账户未完成项保持待验收。
