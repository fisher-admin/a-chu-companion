# 三阶段优化实施计划

> 按用户已批准的独立审查方案执行；主执行者负责修改与验证，复杂共用校验和恢复策略只咨询推理顾问。保留现有开发分支和已测试的冻结副本，不重置或丢弃 Claude 的修改。

目标：修复已复现的回归，补齐翻译与读取恢复，完整模拟通过后集中安装，并开展桌面、网页和可见 CLI 的真实验收。

基线：1.1.7 build63，原始修改已保存为本机提交 `207a06d`；29 组496项模拟检查通过，已知假 session 引起仓库扫描失败。设计与逐项依据见 [独立审查报告](claude-change-review-2026-10-07.md)。

## 第一阶段：回归修复

- [x] 在 `Tests/ReviewRegressionTests.swift` 写限流成功/失败兜底、等待连接与重启额度、跨会话完成、术语跨领域、合法负数、正式正文同名提示的反例；逐项输出失败而非首项退出，保留修复前日志。
- [x] 修复 `Sources/ReplyPipeline.swift`：原服务的等待时间先记录；等待期间系统翻译可继续；失败兜底不能覆盖429恢复条件，每片段有重试时间，取消不启动兜底。
- [x] 修复 `Sources/ClaudeUsageMonitor.swift`：等待期间只收集候选；当前显示与保存偏好分开，来源切换撤销延迟刷新，迟到任务验证代次。
- [x] 修复 `Sources/SystemTranslationProtection.swift`：移除无领域边界的词语替换；仅保留明确技术短语的窄范围规则，转换正文后恢复字面量。
- [x] 修复 `Sources/TranslationFidelity.swift` 的负数列表识别、`Sources/ReplyCore.swift` 的正文误删、`Sources/ReplyMonitor.swift` 的跨会话完成去重。
- [x] 用真实生产类的合成输入逐项转绿；同时复跑 `FidelityFallback`、`UsageAccount`、`CodeSegment`、`Paragraph`、`OptimizationLifecycle` 相关组。

单组执行模式：`sources=(Sources/*.swift); sources=("${(@)sources:#Sources/Main.swift}"); swiftc -swift-version 5 -module-cache-path "$PWD/.build/cache" "${sources[@]}" Tests/ReviewRegressionTests.swift -o .build/review-regression-tests; .build/review-regression-tests --simulation`。所有测试资料均为合成内容，不读取真实密钥。

## 第二阶段：恢复与翻译质量

- [x] 扩充失败用例：短句附加回答、否定反转、表格单元格问句被回答、保护字面量、完整组装问句、取消与服务临时失败。
- [x] 共用正文/单元格的基础校验，在输出完成和发送前核对整条结果；保留启发式局限，对明显冲突结果不自动发送。每片段不固定增加另一模型审核请求。
- [x] 统一各远程翻译提示规则；保留服务专用协议适配和原文不可信数据隔离。
- [x] 将服务错误分为限流、临时错误、鉴权和取消；临时重试有次数和时间上限，原文显示不等待重试或系统语言准备。
- [x] 将普通读取短暂失败改为1、2、4、8秒逐步等待、最高60秒；成功即恢复正常轮询，用户停止及明确退出仍停止；用合成恢复用例核对不会复活已停止任务。
- [x] 将翻译失败和回填失败的处理分开；回填失败保留已生成译文，不重新翻译掩盖原因。
- [x] 精确登记已核实的测试假凭据，保持真实凭据检测严格；补齐 build59–63 的事实记录，草案明确标记为历史计划。

## 第三阶段：冻结与验收

- [x] build64源码冻结，运行 `./test.sh`、`./test-http.sh`、`./test-bridge.sh`、`./build.sh --unsigned`、`python3 -m unittest discover -s Tests -p RepositoryChecksTests.py`、`python3 Tools/check_repository.py --history`，记录退出码与实际数量；检查文档链接和差异空白。
- [x] 保留 build63 应用及签名要求；完成一次正常安装，核对签名、权限和已保存设置，不更改用户登录或无关CLI/浏览器配置。
- [ ] 先通过界面“仅翻译”做四语言、双向的有限真实翻译样本，核对无附加回答、否定反转、表格和字面量变更。
- [ ] 桌面Chat连续两轮研究、Code合成数据多阶段任务；核对自动外语发送、原文先显示、阶段中文及时、后台监控、历史选择和额度随当前入口更新。
- [ ] 清洁官方网页验证正文与额度；模拟扩展存在时排除干扰，不能把模拟页面当实测通过。
- [ ] Mac可见终端运行真正交互式Claude Code，核对当前会话身份、原文、阶段中文、额度与重置时间；静默运行不算可见终端验收。
- [ ] 能提供第二账户时测真实切换；不可获得时保留未验证状态，不创建账户或借用其他端身份凑结果。
- [ ] 更新README、CHANGELOG和最终结果文档；每项区分模拟、真实接口、界面及完整流程。发布前本机历史记录完整且公开扫描通过。

完成标准：已复现问题的修复前失败与修复后通过均可追溯；原文即时显示与阶段翻译并行；不重复发送、不覆盖草稿、不跨来源发布旧额度；实际完成的真实验收有证据，不把未执行项写成通过。

实测追加：build64系统“训练折内→training discount”词义冲突未被原形状检查发现；build65追加只供核对的狭窄冲突检测和英/德正文中文残留检查。已有研究未发送，Mac锁定与系统钥匙串授权待处理；后续真实项仍保持未勾选。
