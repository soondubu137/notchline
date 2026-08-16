# 从当前快照重建而不回放历史事件

Codex in Notch 在启动、重连与重新校正时，从 Hook 随生命周期持续维护的当前活动投影和 Desktop 未读终态重建监视列表。一次性事件目录不作为可回放状态日志：启动前的事件文件不能直接创建行，历史 `Stop` 也不能恢复终态；`Stop/SessionEnd` 的唯一持久效果是把 Turn 从当前活动投影移除。独立 App Server 可能把 Desktop 正在执行的 Thread 报告为 `notLoaded`，所以仅依赖 `thread/list` 会误报 Idle，而持久化完整 reducer 又会恢复过期状态；最小当前投影在两者之间只保留当前精确身份和输入配对信息，不保存标题、Project、内容或终态历史。旧 helper 首次升级时可把尚未消费的事件队列折叠一次，但输出仍只能是最终活动集合。
