# Release checklist / 发布流程

Current releases provide source. Do not distribute the maintainer's local signed bundle, Keychain, certificates, or sessions. / 当前以源码发布，不分发维护者本机签名包、钥匙串、证书或登录会话。

1. Update CFBundleShortVersionString and CFBundleVersion in build.sh for application changes. Keep build numbers increasing; documentation-only preparation may retain the app version. / 应用改动更新版本及递增构建号；仅开源配置和文档可保留应用版本。
2. Add dated changes and tested scope to CHANGELOG and TEST_PLAN. Keep earlier entries, tags, and Git history. Never move a published tag to a different commit. / 补充日期、变化和验证范围，保留旧条目；已发布标签不得移动。
3. Run repository checks with --history, offline tests, loopback HTTP, and unsigned build. For install changes, also verify normal signing continuity locally. / 检查全部历史及本机测试；安装改动另验固定签名。
4. Merge only after the required CI checks pass; verify the intended commit and a clean checkout. / 必需 CI 通过后核对待发布提交。
5. Create an annotated vMAJOR.MINOR.PATCH tag at that exact commit, push the tag, and wait for tag CI. / 在核对的提交创建带说明的版本标签，推送并等待标签 CI。
6. Publish GitHub release notes with key changes, supported hardware/OS, verification gaps, and source installation instructions. / 发布说明包括变化、系统范围、未验证项和源码安装方式。
7. GitHub generates source archives. Additional binaries require a separate distribution identity, notarization, and validation on a clean Mac; do not label a CI unsigned build as notarized or ready for general installation. / 额外二进制需发行签名、公证及干净 Mac 验证，不能把 CI 包当成公证安装包。

Repository defaults: squash merges, automatic merged-branch deletion, read-only Actions tokens, pinned official actions, approval for outside contributors, weekly action updates, CodeQL security analysis, private vulnerability reporting, secret scanning/push protection, and main branch protection. Owner-admin bypass remains available for maintenance; never use it to skip verification. / 默认合并、安全及 main 保护以实际 GitHub 设置为准，维护者权限不得代替验证。
