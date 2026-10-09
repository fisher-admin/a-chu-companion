# A畜伴侣 · AChu Companion

**用中文输入，以多种语言与 Claude 交流。**

[English](README.en.md) · [使用帮助](SUPPORT.md) · [版本更新](CHANGELOG.md) · [贡献](CONTRIBUTING.md) · [隐私](docs/PRIVACY.md)

[![CI](https://github.com/fisher-admin/a-chu-companion/actions/workflows/ci.yml/badge.svg)](https://github.com/fisher-admin/a-chu-companion/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

![A畜伴侣应用图标](docs/assets/companion-icon.png)

A畜伴侣是一款原生 macOS 菜单栏应用，把中文输入、外语回填、Claude 回复的中文翻译和账户额度放在一个窗口中。英文、德文、日文、韩文可选其一，中文始终是主要输入与阅读语言。

这是独立的社区项目，与 Anthropic 没有隶属关系，也不是 Claude 官方产品。它减少复制、粘贴和切换工具的操作，不保证翻译后的指令一定比中文原文更准确。

## 主要功能

- **双向翻译**：中文译为所选语言，Claude 的外语回复译回中文。默认使用 macOS 系统翻译，无需 API 密钥；已安装语言包复用。
- **双引擎与自动降级**：可选 Gemini 等 OpenAI 兼容 AI 翻译。AI 译文先经校验（语言、长度、代码块、行内代码、链接、多余开场白），超时、限流（429）、密钥错误或未通过校验时，该段自动改用系统翻译，并显示「已改用系统翻译」及原因；连续失败会暂停 AI 一段时间再试。
- **同页聊天**：回车提交，Shift＋回车换行；中文输入法选字的回车不提交。可仅翻译、回填后检查，或按设置自动发送。
- **边接收边翻译**：连接即开始读取，伴侣或 Claude 原窗口产生的回复都可获取。Claude 仍在输出时，已完整的句子或段落就开始翻译，并按原文顺序显示；代码块原样保留，不送翻译。识别正式回复，排除工具和运行状态。
- **发送核对与界面变化提示**：自动发送后确认 Claude 输入框已清空才报告「已发送」；Claude 界面结构变化导致持续无法读取时，约 45 秒后显示明确提示，界面恢复后自动继续。
- **后台运行**：切换到其他程序时继续读取。关闭伴侣窗口仅隐藏；停止读取或退出程序结束监测。保持 Claude 的已连接会话窗口打开。
- **跟随会话与历史选择**：同窗切换会话时自动跟随读取；发送到新会话前需重新连接输入框。滚动到历史回复后，可从当前可见完整回复中选择翻译。
- **长文阅读**：译文从开头显示，侧边滚动条浏览全文，外语原文可展开；中文字号 12／14／16，默认 14，语言和字号偏好保存。
- **临时记录**：仅本次运行保留最近 10 条已完成回复译文，退出清空；清除记录保留草稿，不删除 Claude 会话或停止监测。
- **账户额度**：五小时和每周额度显示进度条、已使用百分比、重置时间，随获取回复刷新。使用桌面登录或指定 session；缺失数据不会被当成 0%。
- **原生外观**：猪头中央 A 的菜单栏图标，随系统明暗外观变化的磨砂玻璃界面及紧凑布局。

## 系统与适配范围

| 项目 | 当前范围 |
| --- | --- |
| 平台 | Apple Silicon Mac；当前脚本构建 arm64 |
| 系统 | 最低部署目标 macOS 15；主要在 macOS 26 验证 |
| 聊天 | Claude 桌面版及 Chrome 中的 claude.ai |
| 翻译 | macOS 系统翻译；可选 Gemini 或其他 OpenAI 兼容 AI 翻译，失败时自动改用系统翻译 |
| 权限 | 回填和读取需要 macOS 辅助功能权限；桌面额度读取可能需要钥匙串授权 |
| 中文输入 | 最多 10,000 字符，包含标点与换行 |
| 外语内容 | 发出的译文及读取的原文各最多 50,000 字符，统一按字符计算 |

其他浏览器、Intel Mac 及 macOS 15 的实际使用尚未经过同等验证。Claude 界面变化、未提供给辅助功能的历史正文和暂停的浏览器页面可能影响读取。Claude 自身的消息大小、上下文和账户限制仍适用。

## 从源码安装

准备 Swift 编译环境（较新的 Xcode／Command Line Tools，需包含 macOS 26 SDK）和 Python 3。下载本仓库后，在项目目录执行：

```bash
git clone https://github.com/fisher-admin/a-chu-companion.git
cd a-chu-companion
./setup-signing.sh
./install.sh
open "$HOME/Applications/A畜伴侣.app"
```

首次设置会在你的 macOS 登录钥匙串中创建或复用本机专用签名。每台 Mac 使用自己的身份；不需要维护者的证书或登录信息。安装位置为 `~/Applications/A畜伴侣.app`。

当前发布以源码为主，没有 Apple Developer ID 公证的通用安装包。本机签名用于更新身份连续性，不代表 Apple 公证。CI 的验证包不作为正式安装包发布。

1. 在「系统设置 → 隐私与安全性 → 辅助功能」允许 A畜伴侣。
2. 点击 Claude 的消息输入框，用实体键盘按 **Control＋Option＋E** 连接。
3. 选择英文、德文、日文或韩文，在伴侣中输入中文，回车提交。
4. 默认仅填入译文，由你确认后发送；需要自动发送时开启「填入后发送」，选择回车或 Command＋回车。
5. 连接后自动读取完整回复。可随时停止、恢复，或点击「读取历史回复」。

正常授权后提示会自动更新，无需重启。沿用相同本机签名的正常升级可保留授权；换电脑、更改身份或撤销权限后可能需重新授权。

## 使用 Gemini 翻译

1. 在 [Google AI Studio](https://aistudio.google.com/apikey) 创建 API 密钥。
2. 打开伴侣的「翻译设置」，选择「AI 翻译」，点击「使用 Gemini 地址」（即 `https://generativelanguage.googleapis.com/v1beta/openai/`）。
3. 模型名称填写可用的 Gemini 模型，例如 `gemini-2.5-flash`（以 Google 文档当前列出的模型为准）；打开「新增或更换 API 密钥」并粘贴密钥，保存。

密钥只存入 macOS 钥匙串。请求使用固定翻译指令、示例及 `temperature: 0`，原文放在 `<source>` 标签中，避免模型回答或执行原文。AI 不可用时自动改用系统翻译，所以建议先在系统翻译下安装所选语言包。

## 更新与历史

```bash
git pull --ff-only
./install.sh
```

安装前检查原签名身份；构建失败或身份不一致时不替换已有正式应用。语言、字号和已安装语言包保留，运行期间聊天记录在退出时清空。

[CHANGELOG](CHANGELOG.md) 记录版本变化，[完整旧 README](docs/DEVELOPMENT_HISTORY.zh-CN.md) 保留早期开发记录，[TEST_PLAN](TEST_PLAN.md) 保留各版实际验收结果。Git 提交历史完整保留；发布标签对应实际源码提交。

## 数据与隐私

默认使用系统翻译，不需要翻译 API 密钥；首次语言包下载可能联网。可选 AI 翻译会将中文草稿及外语回复发送给你指定的服务，费用和数据规则由该服务决定。边接收边翻译会把一条回复分成多次较短的请求。

回填时写入剪贴板的译文带有临时和隐藏标记，剪贴板管理工具不会记录。点击「断开」或退出时，关闭伴侣为读取而在 Claude／Chrome 中打开的辅助功能选项。

聊天记录不写入磁盘；指定 session、翻译密钥保存在 macOS 钥匙串。额度使用只读请求，只向 Claude 官方域名发送对应会话凭据，不发送聊天消息；桌面与网页账户不同时需要连接正确的额度账户。

发送前核对原输入框；无法验证回填时不自动发送。超限、失败或取消保留内容并提示，长文完整翻译后合并，不发送半截译文。系统翻译可能改变代码中的标点，执行代码应核对外语原文。

完整说明见 [隐私与权限](docs/PRIVACY.md)，漏洞请通过 [私密安全报告](https://github.com/fisher-admin/a-chu-companion/security/advisories/new) 提交，不公开凭据或私人聊天。

## 开发与验证

```bash
python3 -m unittest discover -s Tests -p RepositoryChecksTests.py
python3 Tools/check_repository.py --history
./test.sh
./test-http.sh
./build.sh --unsigned
```

`--unsigned` 仅输出到 `dist/unsigned/`，不读取本机签名配置，不安装、不覆盖正式签名包。默认 `./build.sh` 与 `./install.sh` 仍要求固定本机签名。

GitHub CI 执行仓库检查、离线回归、本机模拟 HTTP 和无证书构建；CodeQL 分析 Swift、Python 和 Actions 配置。自动运行不登录 Claude、不发送真实消息、不安装语言包。本机语言、签名及实际 Claude 检查单独进行，详见 [贡献说明](CONTRIBUTING.md) 和 [验收记录](TEST_PLAN.md)。

当前应用回归为 273 项，另有 7 项本机 HTTP 检查；`./test-languages.sh` 在已安装语言包的 Mac 上用真实系统翻译验证往返翻译及「AI 限流→系统翻译」的流式降级。原生验证涵盖连续回复、长等待、后台读取、历史选择、停止与恢复、偏好记忆及接近五万字符回复。未完成的网页和系统组合不作为已通过宣传。

## 社区与许可

欢迎 [问题报告](https://github.com/fisher-admin/a-chu-companion/issues/new/choose)、功能建议和 Pull Request。先阅读 [CONTRIBUTING](CONTRIBUTING.md)、[行为准则](CODE_OF_CONDUCT.md) 和 [SUPPORT](SUPPORT.md)。

本项目采用 [MIT License](LICENSE)。Anthropic、Claude、Apple 等名称属于各自权利人；本项目许可不授予第三方商标权。
