# 三端自动额度与补充获取实施计划

**目标**：聊天连接自动获取对应额度，设置提供网页/CLI 获取与安装路径。

**架构**：Monitor 跟随具体 binding，身份合格才采用。网页同源 GET 前后核对，CLI 请求官方状态栏新报告；socket 确认响应只携带固定的只读请求。

- [x] 新增自动跟随合同：连接时隐藏旧值、只接收匹配来源、解绑/换号/缺数据处理；先红后绿。
- [x] 新增网页请求与 CLI 安装/主动报告测试；先红后绿。
- [x] 实现三端连接回调、只读获取通道、设置按钮及安装指导，保留已有手动 session。
- [x] 运行相关 Swift/Python/Node 回归；build57一次完整Swift28组424项退出0，检查隐私及无关CLI配置保留。
- [x] 安装 build56 并点击三端界面，执行可行真实检查；发现提示问题后修订安装 build57，保留55/56备份。
- [x] 更新版本历史和分端测试报告，包括可复现手动步骤与真实未完成项。
- [ ] 三端真实完整验收：桌面当前绑定及会话访问、无模拟脚本且已配置的网页入口、Mac可见终端、真实双账户条件尚未全部形成，不能用模拟替代。

结果以[三端自动额度测试记录](../../testing/three-channel-active-usage-2026-10-07.md)为准。安装版合成来源证明只选聊天来源即可自动跟随额度；设置只作补充。57完整一次Swift结果与56分批及中断分别记录。

验证命令：`./test.sh`、`./test-bridge.sh`、`node --test Tests/WebUsageTests.cjs`、`python3 -m unittest discover -s Tests -p ActiveUsageTests.py`、`python3 Tools/check_repository.py`。安装前保留 build55 备份，并验证指定签名要求不变。当前 checkout 的历史修改保持，不另行提交或发布。
