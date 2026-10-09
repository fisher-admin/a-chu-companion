# Native Web Usage implementation plan

**Goal:** 在伴侣内直接读取所选Claude网页额度，移除浏览器组件安装流程。

**Architecture:** `WebUsageAccessibility`只操作选定窗口的官方页面和账户菜单；`NativeWebUsage`管理账户前后核验、窗口代次和报告。发送租约不归此模块所有。无凭据提取、后台浏览器激活或独立登录替代。

**Tech Stack:** Swift、AppKit、现有macOS辅助功能授权、CryptoKit哈希、离线合成AX节点与注入的操作环境。

用户已批准实施，复用当前codex分支和工作区，按计划内联执行。普通工作不再次询问，只有不可代办的真实授权或目标选择才交接。Sol仅审阅了跨模块设计，不实施。

## 1. 页面解析

- [x] 新建`Tests/NativeUsageParserTests.swift`，真实繁体页面结构使用合成数值，先调用现有`VisibleUsageParser.parse`确认“目前工作階段／已使用n%”失败。
- [x] 修改`Sources/UsageSources.swift`的标签和百分比顺序，保留重复／非法值拒绝。
- [x] 新增`WebUsagePage`：`Item(label:number:)`；`parse(_ items:[Item]) throws -> ClaudeUsageSnapshot`优先使用分区控件数值；`identity(_ lines:[String]) throws -> UsageAccountIdentity`仅接受唯一完整邮箱。加入冲突、产品分配、重置顺序与假网址失败用例，运行至通过。

## 2. 原生账户核验

- [x] 新建`Tests/NativeWebUsageTests.swift`，注入窗口可用／前台、账户和额度操作。覆盖后台零激活、唯一窗口、前后账户不一致、换绑取消和恢复失败。
- [x] 新建`Sources/NativeWebUsage.swift`：`bind(_ selection)`、`read(explicit: Bool) async throws`、`readOpenUsage()`和`unbind()`；用`Environment`注入`account`、`quota`、`restore`等真实动作；每一步核对窗口和任务代次。`onEvidence`和`onInvalid`沿用现有额度数据类型。
- [x] 新建`Sources/WebUsageAccessibility.swift`：只遍历精确窗口，识别唯一官方WebArea、侧栏账户菜单、Usage设置和控件；检查每阶段的前台状态，使用AXPress打开与关闭原有网页界面，不写消息或剪贴板。
- [x] 运行两组新检查，全部通过，再运行所有额度、连接、发送相关旧回归。

## 3. 接入及撤回安装

- [x] `TranslatorModel`提供只读网页目标；`Main`改接原生controller，删除Python服务启动、安装和焦点配对；回复后仅在允许的前台条件读取。
- [x] `Views`、`ClaudeUsageView`改为直接读取和已打开Usage入口，显示当前状态与背景刷新限制，不提供任何安装按钮、目录或ID。
- [x] `build.sh`升至78，打包仅CLI bridge程序，不带油猴与MV3组件；旧源码和测试作为历史保留。
- [x] 编译最终模块，完整回归；真实连接前先核对原签名和安装资源。

## 4. 验收与记录

- [x] 在正式伴侣里读取唯一已打开的真实Usage，核对两项数值、重置说明及遮蔽账户；不向Claude发消息。
- [x] 检查页面恢复和后台不抢焦点，记录已验证与尚未验证范围。
- [x] 更新README、隐私、版本和测试记录，凭据／链接／历史检查通过后提交。保留build77被用户撤回的原因和真实未通过结果。

完成说明：最终42组模拟全部通过；Chrome真实Usage、断开重连和Chat恢复通过。后台不抢焦点／账号切换仅模拟验证，其他浏览器和真实新回复后自动刷新未做，详见测试记录。
