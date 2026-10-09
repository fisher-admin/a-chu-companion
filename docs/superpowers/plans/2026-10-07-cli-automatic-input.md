# CLI 自动输入实施计划

**Goal:** 中文翻译后自动填入明确绑定的本机 Claude Code CLI；自动发送须满足可核对条件。

**Architecture:** 单独的 CLI 原生投递器 + 可测试内容策略；只读桥接只附加进程身份。TranslatorModel 保存输入绑定并冻结任务，不让回复快照撤销它。

**Tech Stack:** Swift/AppKit/Accessibility、Python 私有 Unix socket、现有翻译与保真校验。

执行方式为当前会话内顺序实现。复杂跨模块边界已向 fresh-context Sol max 仅咨询，不委派执行。

- [x] 1. `Tests/CLIDeliveryOriginTests.py`：先运行并保存缺少来源绑定的失败。实现 `Bridge/bridge.py` 的 `delivery_origin`、可选报文及 footer 输入标签，覆盖无 tty、非前台、进程重用和祖先循环。
- [x] 2. `Sources/CLIDelivery.swift` + `Tests/CLIDeliveryTests.swift`：底部标记/输入区解析、进程验证、空输入限制、精确 GUI 绑定和长粘贴不自动发送。
- [x] 3. `Sources/BridgeProtocol.swift` / `LocalBridge.swift`：仅合法 CLI 可选来源身份；旧无身份报文保持只读；无效/迟到报告不修改当前绑定。
- [x] 4. `TranslatorModel.swift`：捕获 CLI 表面、明确会话选择与精确匹配、Job 保存绑定；新正文不清除目标；填入和发送走 CLI 投递器；切源、取消及失败保留文本。
- [x] 5. `Views.swift`：CLI 已绑定时显示自动发送及填入按钮，未绑定时明确只读和重新连接提示。
- [x] 6. 独立原生 UI 夹具实际检查短文、多行、长折叠、重复填入阻止；切换由策略与模型回归覆盖；全量回归、独立无签名构建、公共仓库扫描。
- [x] 7. build69 沿原签名安装并重启，核对原权限/偏好；保留 build68 备份与 Git 检查点，记录真实验收待办。

关键命令：`python3 -m unittest Tests/CLIDeliveryOriginTests.py Tests/BridgeTests.py`；`./test.sh`；`./build.sh --unsigned`；`./install.sh`。每步读取退出码及结果，失败修复后重测，不以代码存在推断功能通过。
