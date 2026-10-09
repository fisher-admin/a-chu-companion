# 三入口与当前账户识别实施计划

> 在当前会话内按 executing-plans 执行。用户要求减少参与，已授权继续修复和测试；本轮不创建新工作树、不提交、不发布。

**Goal:** 明确三种额度连接，阻止旧账户额度误归入当前账户。

**Architecture:** 保留 Source 持久化值，新增语义入口过滤；UsageEvidence 增加身份与代次序号，由 monitor 检查并失效旧账户。生产者只从官方登录状态和当前可见页面取得身份，不读取或转发 OAuth。

**Tech Stack:** Swift/SwiftUI、Python 标准库、MV3 JavaScript。

- [x] 在 UsageAccountTests.swift 写模拟行为合同，运行观察旧实现失败：A→B→迟到 A、无身份、另一来源、重启及候选隔离。
- [x] 在 Sources/UsageSources.swift 添加可选身份、代次、序号；在 ClaudeUsageMonitor.swift 实现来源筛选、候选上限与失效规则。
- [x] 更新 ClaudeUsageView.swift 为桌面/网页/CLI 三入口，展示真实身份核对状态；备注仅作为备注。旧 session 入口明确不代表当前浏览器账户。
- [x] 在 BridgeProtocolTests.swift 先写迟到额度、空身份事件、乱序测试，再修改 BridgeProtocol.swift。
- [x] 在 BridgeTests.py 写 SessionStart 和当前登录变化合同；实现隔离状态文件与身份指纹、保留用户原 hooks/statusLine 并可卸载。
- [x] 在 BridgeChromeTests.cjs、BridgeWorkerTests.cjs 写身份缺失/原文仍可读合同；实现网页当前 DOM 身份及代次转发。无法确认当前身份时不显示额度。
- [x] 分批运行新增测试与全部 test.sh、test-bridge.sh、HTTP、仓库检查，核对个人 CLI 设置未改；去重后28组420项。
- [x] 更新版本历史、测试矩阵和隐私说明，安装build54并核对原签名；保留旧版本及失败记录。
- [ ] 完成真实桌面额度、可见终端研究、网页自动额度和两账户切换验收。受本人确认或工具控制限制的部分保留待验收，不重复申请许可。
