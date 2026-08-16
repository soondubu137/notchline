# 使用 Codex Desktop 的 Project 身份

会话行中的 Project 必须对应 Codex Desktop 左侧边栏由用户创建的 Project 实体；一个 Project 可以包含一个或多个仓库，没有归属 Project 的会话显示 `Chats`。V1 不得从 `cwd`、Git 根目录或路径名称推断 Project，因为这些对象与用户管理的 Desktop Project 并非一一对应；如果受支持的集成接口不能取得 Desktop Project 身份和名称，该能力不允许以近似值降级发布。
