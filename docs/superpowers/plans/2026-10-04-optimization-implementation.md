# 1.1.7 优化实施与模拟验收计划

> 在当前会话按任务顺序执行，不委派常规工作。用户已授权开发与模拟；真实 Claude、云翻译、正式安装、个人桥接配置与额度迁移均待单独指令及授权。

**Goal:** 按已确认方案完成阶段性原文与中文、阅读保护、服务来源隔离、被动健康检查和实验桥接，并以完整模拟证明行为。

**Architecture:** 复用现有 AX 解码与发送保护；在采集后直接发布原文，以有界的稳定切片调度中文，并用会话/原文/配置代次拒绝旧结果。CLI/Chrome 只提供只读事件桥接，额度替代来源在验收前不切换现有连接。AXObserver、SSE、托管 CLI、Azure/DeepL 和远程政策服务维持方案的条件性后置范围。

**Tech Stack:** Swift/AppKit/SwiftUI、Python 标准库本机 Unix socket 桥接、Chrome MV3；测试不需要真实登录或 key。

## 完成标准

- 所有本轮必做批次有可运行实现及模拟证据，不以接口占位代表完成。
- 阶段 A 中文在后续阶段和任务结束前出现；慢翻译不挡原文，已译片段保留，长文逐块返回。
- 十条译文、清除/淘汰失效、原位置更新、滚动选区、语言及字号保留。
- 凭据按规范化接口来源隔离，旧配置安全迁移；Gemini 原生模型保持。
- 被动检查不发推理请求；用量成功冷却、旧值/账号来源明确，迁移无隐形旧来源回退。
- CLI/Chrome 协议可模拟安装/卸载、分片、缺序、重放、导航和失效；不安装到个人配置。
- 全部适用自动测试、仅本机 HTTP、模拟 UI 和独立未签名构建通过。
- 提交真实环境方案及未测矩阵；不自动开展真实验证。

## 任务与验证

- [x] A1：`Sources/TranslationProfile.swift`、`Credentials.swift`、模型和设置页。先写来源规范化/旧绑定/跨地址测试，验证失败，再实现分账户迁移与 OpenAI/Grok 预设；`Tests/OptimizationTests.swift`。
- [x] A2：`Sources/ReplyPipeline.swift`、`ReplyMonitor.swift`、`TextTranslation.swift`。先写虚拟 0/3/3.2/12/36 秒时间线、忙队列、修订、清除、长段和背压测试。直接发布正式原文，按稳定切片排队并逐块回传。
- [x] A3：`TranslatorModel.swift`、`MessageText.swift`、`Views.swift`。修改现有行为断言并实际观察其失败；同 ID 原位更新，保留旧中文并标更新状态，滚动只由阅读意图触发；旧记录不复活。
- [x] B：`Sources/HealthStatus.swift`、主窗与设置页。注入本地检查及时间，验证离线、未配置、语言准备、冷却、单飞与错误分项；不自动联网生成。
- [x] C1：`Sources/UsageSources.swift`、额度监控/连接页。statusLine JSON 与可见 Usage 语义字段解析，账号确认、活性/证据时间、过期、源冲突与明确迁移；模拟新来源，不触碰真实 Cookie。
- [x] C2：`Sources/TranslationStructure.swift`。代码围栏、行内代码、URL/路径/占位符保护与往返；自然语言可译，失败明确保留原文；限制/取消不跨云回退。
- [x] D：`Sources/BridgeProtocol.swift`、`LocalBridge.swift`、`Bridge/`。Unix socket 与严格只读 schema、握手、大小与序列验证；CLI MessageDisplay/statusLine 和 Chrome Native Messaging/DOM，临时目录安装/三方卸载、畸形数据与扩展生命周期模拟。
- [x] E：先实现 AX 整体预算与合并，记录耗时。AXObserver/SSE 是否启用等待真实瓶颈测量，本轮不假称有性能收益。
- [x] F：完整模拟运行、隔离 UI、构建、仓库隐私/文档检查，更新 1.1.7/build34 与变更历史；不签名覆盖安装、不推送。

## 每批执行方式

1. 写实际行为断言，运行并记录预期失败。
2. 实现最小闭环，运行对应测试，修复至通过。
3. 将新增测试接入 `./test.sh` / `./test-http.sh` / Python 和 JavaScript 桥接检查。
4. 所有批次后执行完整回归、模拟画面交互与 `./build.sh --unsigned`。
5. 在 `docs/testing/` 写本轮真实结果；追加历史，不覆盖上一版本报告。

## 实施不等于正式启用

新的额度/CLI/扩展入口在界面标为待真实验收；需要用户主动启用与绑定来源。旧额度路径在新来源获授权验收后才执行迁移。桥接安装工具只生成/修改明确指定的测试目录，本轮不操作用户的真实 CLI 或 Chrome 配置。

## 完成记录（2026-10-05）

首轮必做批次已完成；全量 252 项应用回归、14 项本机 HTTP、4/8/5 桥接检查、隔离原生/Chrome UI 及未签名构建均实际通过。详见 [最终模拟报告](../../testing/optimization-implementation-report.md)。E 的 AXObserver/SSE、托管 CLI、其他供应商和远程清单仍按确认方案条件后置，不算已实现或已通过。真实测试全部未执行。
