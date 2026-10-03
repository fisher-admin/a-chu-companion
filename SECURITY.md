# Security policy / 安全政策

## Reporting / 报告方式

Use GitHub's [Report a vulnerability](https://github.com/fisher-admin/a-chu-companion/security/advisories/new) to contact the maintainer privately. Do not open a public issue containing exploits, session keys, cookies, API keys, private keys, or real chat content.

请使用 GitHub [私密漏洞报告](https://github.com/fisher-admin/a-chu-companion/security/advisories/new) 联系维护者，不要在公开 Issue 中附带漏洞利用细节、凭据或私人聊天。

Provide the affected version/build, macOS version, reproduction steps with synthetic data, expected impact, and any suggested fix. If a credential was exposed, revoke or rotate it with its issuer; deleting a post or commit does not revoke it. Reports are handled on a best-effort basis; no response SLA is promised.

提供受影响版本／构建号、macOS 版本、模拟数据复现步骤、影响及建议修复。已泄露的凭据应向签发服务撤销或更换，删除文字或提交不会使凭据失效。维护者尽力处理，不承诺固定响应时限。

## Supported versions / 维护范围

Security fixes target the latest released version. Older releases remain in Git history and CHANGELOG for traceability; upgrade before requesting a fix. / 安全修复针对最新发布版本。旧版历史仍保留，建议先升级再复核。

## Boundaries / 边界

- Accessibility permits reading the connected chat window and inserting text; it is not sandbox-wide permission to collect other apps. / 辅助功能用于已连接窗口，不代表任意收集其他应用。
- Supplied sessions and translation API keys use macOS Keychain; local signing private keys remain on each user's Mac. / 凭据与本机签名私钥留在各自电脑的钥匙串。
- Default CI uses no personal secrets and cannot send real Claude messages. Repository content permissions are read-only; CodeQL can write only security scan results. Fork workflows use restricted tokens and require maintainer approval for outside contributors. / 默认 CI 不使用个人密钥或发送真实消息，仓库内容只读，CodeQL 仅写安全扫描结果，外部贡献运行受审批控制。
- Pattern-based repository checks supplement GitHub secret scanning; neither is a guarantee that every secret is detectable. / 模式检查与 GitHub 密钥检测相互补充，并非绝对无泄露保证。

See [Privacy](docs/PRIVACY.md) for translation and usage data flows. / 数据处理说明见 [隐私](docs/PRIVACY.md)。
