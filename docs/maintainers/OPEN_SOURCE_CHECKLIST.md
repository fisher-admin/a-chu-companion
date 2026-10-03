# Open-source verification / 开源验收记录

Date / 日期：2026-10-03。This is a dated snapshot, not a promise that settings cannot change. / 以下记录此次实际核对结果，设置以后可能变化。

## Repository / 仓库

| Item / 项目 | Verified state / 已核对状态 |
| --- | --- |
| Visibility / 可见性 | Public / 公开 |
| License / 许可 | MIT, recognized by GitHub / GitHub 已识别 |
| Introduction / 介绍 | Chinese and English READMEs, scope and source installation / 双语首页、适配范围和源码安装 |
| Community / 社区 | Contribution, conduct, security, support, privacy; issue forms, PR template, CODEOWNERS; community profile 100% / 社区文件和表单齐全 |
| Collaboration / 协作 | Issues and Discussions enabled; documentation stays in Git / 问题和讨论开启，文档留在 Git |
| Merges / 合并 | Squash only, update branch available, merged branches auto-delete / 合并新增改动，保留既有历史 |
| Actions / 自动检查 | Read-only content token, official actions only, full commit SHA required, no PR approval by token / 只读、官方固定版本、不能代替人审查 |
| Outside contributions / 外部贡献 | All outside contributors need workflow-run approval / 外部贡献运行须审批 |
| Dependency updates / 依赖更新 | Weekly grouped Actions updates, vulnerability alerts and security updates enabled / 定期更新及安全提醒开启 |
| Private security reports / 私密报告 | Enabled / 已开启 |
| Secret scanning / 密钥检测 | Scanning and push protection enabled; no open alerts at verification / 已开启检测和推送保护，核对时无告警 |
| Code scanning / 代码扫描 | Swift, Python and Actions analysis passed; no open alerts at verification / 三类安全分析通过，核对时无告警 |
| Main protection / 主分支 | Five required checks from GitHub Actions, current-base checks, one code-owner approval, stale approval dismissal, resolved conversations, linear history, no force push/delete / 五项检查、审查及历史保护 |
| Maintainer access / 维护权限 | Owner-admin bypass retained for maintenance; verification is still required / 管理员保留维护权限，仍须先验证 |
| Version tags / 版本标签 | Active v* rules block update/deletion, allow creation, no configured bypass / 允许新版本，保护已有标签 |

## Source verification / 源码验证

Verified application source checkpoint / 已验证源码：[`e5562b2`](https://github.com/fisher-admin/a-chu-companion/commit/e5562b26150df9d6550e491d4eb62b648739a649)，1.1.4 build 28。

- [Main CI](https://github.com/fisher-admin/a-chu-companion/actions/runs/37135662034): five repository-tool tests, full-history pattern and documentation checks, 157 app regression checks, seven loopback HTTP checks, and the optimized unsigned app bundle passed. / 仓库、本机回归、HTTP 和应用构建全部通过。
- [CodeQL](https://github.com/fisher-admin/a-chu-companion/actions/runs/37135662048): Swift, Python and Actions passed. Swift source extraction takes longer than the ordinary build; use the configured analysis timeout. / 三类分析通过；Swift 提取比普通构建慢，使用已配置的超时时间。
- Local signing continuity verified: the existing installed app and signed bundle were not replaced; the verification bundle cannot match the fixed authorized identity. / 原应用、签名包未被替换，临时包不能匹配原授权身份。
- All 12 pre-existing commits, their old verification records and the original README are retained. The old tip was `4f71a214ed36633fc4a5e54c43e159ec6fa11e51`; it remains an ancestor of the public release. / 旧提交和记录完整保留，无改写。
- Git history and current tracked files were checked for explicit credential patterns without printing values. The two whitelisted session strings are exact synthetic test fixtures, not a maintainer login. GitHub secret scanning reported zero alerts. / 凭据检查不输出密钥，测试假数据明确区分；零告警不等于能识别所有可能的秘密。

The existing [TEST_PLAN](../../TEST_PLAN.md) remains the authority for native tests and unverified combinations. No real Claude message was sent by these automated checks. / 实际界面和未验证范围见旧验收记录，自动检查不发送真实 Claude 消息。

## Release / 发布

- [v1.1.4 source release](https://github.com/fisher-admin/a-chu-companion/releases/tag/v1.1.4) published at 2026-10-03 16:32:15 UTC; annotated tag resolves to the verified source commit above. / 正式源码发布及带说明标签对应已验证提交。
- [Tag CI](https://github.com/fisher-admin/a-chu-companion/actions/runs/37136887328) passed with the same full checks and application build. / 标签独立完整检查通过。
- The actual GitHub tar archive was downloaded and all 88 files compared byte-for-byte with Git at v1.1.4. There are no separately uploaded binary assets, local build folders, certificates or credential stores. / 实际归档逐文件一致，不附带本机程序或凭据存储。
- The release contains source only, with local signing instructions and explicit platform-verification limits; it is not an Apple-notarized installer. / 明确源码安装和验证范围，不作为 Apple 公证安装包。

The closing record update changes documentation only; application sources, tests, build scripts and workflows remain identical to v1.1.4. Local documentation/history checks and repository-tool tests are repeated for this record. The commit uses [skip ci] to avoid repeating the same native build and code analysis; required PR checks and branch protections stay enabled. / 最后的记录提交只改文档，程序及自动检查文件与已通过的版本完全一致；本机重新检查文档、历史和仓库工具，避免重复相同构建和安全分析，后续 PR 的必需检查和保护继续生效。
