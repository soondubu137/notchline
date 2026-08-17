# 将精确 Desktop 会话导航作为发布门槛（仅 Codex）

每个 Codex 列表行都承诺返回产生该状态的同一 Codex Desktop 会话，因此 V1 只接受受支持的 `threadId → Desktop 同一页面` 导航契约。只打开 Codex 首页、按标题搜索、猜测 URL、调用私有 IPC 或用辅助功能点击都被拒绝；如果目标 Codex 版本没有可验证的精确导航能力，该版本不能被标记为 V1 支持。

**该门槛按产品成立，只约束 Codex。** Claude Code 目前不存在任何受支持的方式聚焦一个已经存在的会话——官方 deep link 只能新建——所以把这条无条件地套用到第二个产品，等于用一个并不存在的能力去阻塞它。Claude Code 行的成功定义因此降级为唤起其宿主：Desktop 托管的会话激活 Claude Desktop，终端里的会话聚焦其标签页。降级是**不加标记**的：一行只携带一个标记，而那个标记是计时。因此点击后的那句反馈是唯一能说出差别的地方，它必须报告实际做到了什么，而不是照抄 Codex 的说法（见 `NavigationOutcome`）。

一旦官方为本地会话提供 deep link，Claude Code 应迁移过去，本条降级随之作废。
