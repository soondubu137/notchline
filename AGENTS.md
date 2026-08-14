# Codex in Notch Agent Constraints

本文件适用于本仓库及其所有子目录。任何在本仓库中工作的 Agent 都必须遵守以下约束。

## 非公开 App Server Feature 登记

### 强制规则

- 默认优先使用官方文档和当前公开 schema 中定义的 Codex App Server JSON-RPC 能力。
- 任何生产 feature 只要不是**完全**通过公开 App Server 实现，就必须在同一个改动中新增或更新 [`docs/non-public-app-server-features.md`](docs/non-public-app-server-features.md)；不得把登记工作留到后续任务。
- “部分使用公开 App Server”仍然属于必须登记的范围。只要身份、实时性、启动、导航、配置、恢复或其他关键环节依赖 App Server 以外的接口，就必须登记。
- 必须登记的非公开依赖包括但不限于：
  - Codex Desktop 私有文件、状态 schema、bundle 内资源路径或未公开字段；
  - Codex Hooks、本地文件桥、CLI 配置文件或其他独立于 App Server 的事件通道；
  - Desktop bundle identifier、进程探测、deep link、Launch Services 或其他平台集成；
  - 通过实验观察但未进入官方 App Server 契约的行为。
- 修改已有非公开 feature 的 schema key、文件路径、协议、版本基线、实现方式、失败信号、保守降级或代码位置时，必须同步更新清单中的对应行。
- 如果公开 App Server 后续提供了等价能力，应优先迁移到公开接口，并在同一个改动中更新或移除清单行、旧的私有实现及其测试。

### 每条记录的最低要求

清单中的每个 feature 至少必须说明：

1. feature 是什么；
2. 为什么公开 App Server 无法完整实现；
3. 实际实现方法。

此外应保留依赖级别、Desktop 更新后的失效信号、保守降级行为和可直接定位的代码/测试路径。不得使用模糊描述隐藏真实私有依赖。

### 实现与验证流程

1. 实现前先检查官方 App Server 文档、当前 schema 和现有清单，确认能力缺口仍然存在。
2. 在设计实现时明确区分公开 App Server 数据与非公开数据源，不得把私有行为包装成公开契约。
3. 对私有 schema 或文件依赖增加成功、缺失、损坏和版本不兼容测试，并采用 fail-closed 行为；不得把解析失败解释为有效空值、`Chats` 或其他成功状态。
4. 完成前检查代码、测试、PRD、技术设计与非公开 feature 清单是否一致，并验证清单中的相对链接仍然有效。
5. 交付说明中明确指出本次改动是否新增、修改、迁移或移除了非公开 App Server feature；如果不适用，也应在检查后明确说明。

遗漏清单更新视为改动未完成。
