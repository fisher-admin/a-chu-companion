# Contributing / 贡献指南

[中文首页](README.md) · [English](README.en.md) · [行为准则 / Conduct](CODE_OF_CONDUCT.md)

## 中文

欢迎问题修复、文档、界面改进和 Claude 可访问界面适配。提交前先搜索已有 Issue；较大功能先说明使用场景、范围及预期行为，避免重复工作。安全问题使用 [私密漏洞报告](https://github.com/fisher-admin/a-chu-companion/security/advisories/new)。

1. Fork 后从 main 新建分支，保持改动聚焦；不要改写已有版本历史。
2. 安装较新的 Swift 编译环境（含 macOS 26 SDK）和 Python 3。应用是 Swift／SwiftUI／AppKit 原生项目，没有 npm 或第三方 Swift 包安装步骤。
3. 修改逻辑时增加有意义的失败／成功检查；文档修改核对中英文说明和文件链接。
4. 按修改范围运行下列命令，并在 PR 中如实列出已运行项与未验证项。

```bash
python3 -m unittest discover -s Tests -p RepositoryChecksTests.py
python3 Tools/check_repository.py --history
./test.sh
./test-http.sh
./build.sh --unsigned
git diff --check
```

只需构建检查时用 --unsigned，产物不作为日常授权应用。实际运行使用自己 Mac 的 ./setup-signing.sh 和 ./install.sh，不提交本机证书、私钥或签名配置。不改动别人的系统信任或重置全部辅助功能授权。

需要验证真实翻译／权限时，阅读 [TEST_PLAN](TEST_PLAN.md)，并在本机运行 ./test-languages.sh（会使用系统翻译，未安装语言可能需要下载）；签名检查为 python3 Tests/SigningTests.py。先安装正常签名包，再进行此项检查。构建本机对话夹具用 ./build-fixture.sh，打开 dist 中的测试应用；这些交互检查不属于无凭据 CI。

界面截图和复现对话使用模拟内容。未经明确授权，不向实际 Claude 会话发送测试消息；不要公开 Cookie、session、API 密钥、个人会话链接或私人聊天。即使 CI 通过，也不能把未验证平台描述为已支持。

提交说明应交代问题、修改后的行为和验证；按需更新 CHANGELOG 和两份 README。代码使用现有样式；.editorconfig 和 .gitattributes 统一文本规则。不引入无关格式化或重构。提交的贡献按项目 MIT 许可提供，不另要求 CLA。

## English

Contributions to fixes, documentation, interface improvements, and Claude Accessibility integration are welcome. Search existing issues first. Discuss substantial features with a concrete use case and scope. Report security problems [privately](https://github.com/fisher-admin/a-chu-companion/security/advisories/new).

Fork, branch from main, and keep changes focused. Preserve existing version history. Use a recent Swift toolchain with the macOS 26 SDK and Python 3; this native Swift/SwiftUI/AppKit project has no npm or third-party Swift package setup.

Add meaningful failure/success coverage for behavior changes. Check both READMEs and local links for documentation changes. Run the commands above as appropriate, and report exactly what was tested and what remains unverified.

Use --unsigned for build verification only. For actual operation, set up your own local identity and install normally. Never commit certificates, private keys, signing configuration, or credentials; do not change system trust or reset all Accessibility permissions.

Manual language checks use ./test-languages.sh and may download missing system packs. Local signing checks use python3 Tests/SigningTests.py after a normal signed build. ./build-fixture.sh prepares a local chat fixture. These checks require your local environment and are excluded from credential-free CI; follow [TEST_PLAN](TEST_PLAN.md).

Use synthetic screenshots and conversations. Obtain explicit authorization before sending messages in real Claude conversations. Remove credentials, personal conversation URLs, and private text before sharing evidence. Passing CI does not establish support for untested platforms.

Explain the problem, resulting behavior, and validation in your PR. Update CHANGELOG and both READMEs where relevant, follow existing code style, and avoid unrelated reformatting. Contributions are provided under the project's MIT License; no separate CLA is required.
