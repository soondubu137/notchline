# 对未经验证的 Desktop 集成 fail closed

Codex in Notch 只使用公开、受支持且经过版本能力验证的 Desktop 观察与导航契约；新版本或字段变化在验证前显示 `Codex version unsupported`，而不是读取私有资源或以历史、路径和窗口状态推断实时真值。这牺牲了对未知版本的乐观兼容，但避免把错误会话、Project、未读和导航结果伪装成真实监视数据。
