# Companion-managed Web usage implementation plan

**Goal:** 在伴侣中准备和管理网页额度模块，用户仅处理必要授权。

**Architecture:** 随附额度用户脚本通过认证 loopback 服务发送遮蔽身份和额度。伴侣监督服务、发起焦点挑战并管理额度生命周期；不替换 AX 聊天收发。

**Tech Stack:** Swift Foundation/AppKit、Python 标准库、Tampermonkey GM 接口、Web Crypto HMAC。

Execution is inline under the user's explicit direction to handle routine work without additional approvals. No routine worker delegation; one reasoning-only Sol consultation reviewed the transport and focus boundary.

## 1. 协议与真实 socket 模拟

- [x] 在 `Tests/ManagedWebUsageTests.py` 定义实际 HTTP 的授权、目标绑定、失效和攻击输入测试，先运行并确认缺少模块失败。
- [x] 在 `Bridge/web/service.py` 实现 `WebSession`、`create_server` 和受监督 stdin/stdout 控制。只使用标准库，错误只发分类，无请求体日志。
- [x] 运行 `python3 Tests/ManagedWebUsageTests.py`，全部通过。

## 2. 最小额度模块

- [x] 在 `Tests/ManagedWebModuleTests.cjs` 模拟 GM 接口、焦点和 Claude JSON，签名使用真实 Web Crypto。
- [x] 在 `Bridge/web/usage.user.js` 生成私有安装密钥，复用 `Bridge/chrome/usage.js` 的账户与额度校验；消息只包含允许字段。
- [x] 运行 Node 模拟并核对序列、焦点、身份变更及不泄露凭据。

## 3. 伴侣接入与设置

- [x] 新增 `Sources/ManagedWebUsage.swift`，监督子进程与管道，提供安装、绑定、刷新、撤销方法。
- [x] 修改 `Sources/Main.swift` 接入额度回调及有限焦点等待；修改 `Sources/ClaudeUsageView.swift` 移除手填扩展流程。
- [x] 从 `TranslatorModel` 仅提供用户已选定的目标窗口恢复方法，不猜来源、不写入消息。
- [x] 编译并运行额度及连接相关回归；再一次完整回归。

## 4. 安装与真实接入

- [x] 更新 build、变更记录、隐私说明和开发历史，保留 build75/76 已有验收。
- [x] 固定原签名构建安装，核验已安装二进制与9个桥接资源；实际打开新版设置，未绑定时连接按钮禁用。
- [ ] 从伴侣发起安装授权；需要用户确认时只交接该授权，不要求开发者设置或任何 ID。
- [ ] 仅读取当前真实账户额度，核对成功和失效状态；没有真实心跳时明确尚未通过。
