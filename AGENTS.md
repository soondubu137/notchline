# Codex in Notch Agent Constraints

本文件适用于本仓库及其所有子目录。任何在本仓库中工作的 Agent 都必须遵守以下约束。

## 问题清单在哪里

已知问题**不再记录在仓库内的文档里**。原 `docs/current-issues.md` 已于 2026-08-16 迁移到 GitHub 看板并删除：

- 看板：<https://github.com/users/soondubu137/projects/2>（编号约定、优先级定义与修复顺序见看板 README）
- Issues：<https://github.com/soondubu137/codex-in-notch/issues>

`CR-xxx` 编号沿用原文，git 历史中的提交信息直接引用它们。新发现的问题应开成 issue 并加入看板，不要在 `docs/` 下重建问题清单文件。修复某条问题时，在提交信息里引用对应 issue 编号。

设计结论、实测边界和架构约束仍然留在 `docs/`——只有**待办的缺陷**搬走了。

## 未受官方公开支持的 Codex 集成 Feature 登记

### 强制规则

- 默认优先使用官方文档和当前公开 schema 中定义、公开支持的 Codex 集成能力，包括 App Server、Hooks、公开 CLI/SDK 接口和官方 deep link。
- 任何生产 feature 只要依赖**未被官方公开文档或公开 schema 支持的 Codex 实现细节**，就必须在同一个改动中新增或更新 [`docs/non-public-codex-integration-features.md`](docs/non-public-codex-integration-features.md)；不得把登记工作留到后续任务。
- 不得仅因为 feature 没有通过 App Server 实现就登记。使用官方 Hooks、官方 deep link 或其他公开支持接口的 feature 不属于本清单，除非实现还依赖额外的私有细节。
- 必须登记的非公开依赖包括但不限于：
  - Codex Desktop 私有文件、状态 schema、IPC、bundle 内资源路径或未公开字段；
  - 未被官方文档承诺的 bundle identifier、文件位置、payload 字段或进程行为；
  - 通过逆向或实验观察、但未进入任何官方公开契约的行为。
- 修改已有非公开 feature 的 schema key、文件路径、协议、版本基线、实现方式、失败信号、保守降级或代码位置时，必须同步更新清单中的对应行。
- 如果官方后续提供了等价的公开支持能力，应优先迁移到官方接口，并在同一个改动中更新或移除清单行、旧的私有实现及其测试。

### 每条记录的最低要求

清单中的每个 feature 至少必须说明：

1. feature 是什么；
2. 为什么官方公开支持的接口无法完整实现；
3. 实际实现方法。

此外应保留依赖级别、Desktop 更新后的失效信号、保守降级行为和可直接定位的代码/测试路径。不得使用模糊描述隐藏真实私有依赖。

### 实现与验证流程

1. 实现前先检查官方 Codex 文档、当前公开 schema 和现有清单，确认能力缺口仍然存在。
2. 在设计实现时明确区分官方公开支持接口与非公开数据源，不得把私有行为包装成公开契约。
3. 对私有 schema 或文件依赖增加成功、缺失、损坏和版本不兼容测试，并采用 fail-closed 行为；不得把解析失败解释为有效空值、`Chats` 或其他成功状态。
4. 完成前检查代码、测试、PRD、技术设计与非公开 feature 清单是否一致，并验证清单中的相对链接仍然有效。
5. 交付说明中明确指出本次改动是否新增、修改、迁移或移除了未受官方公开支持的 Codex 集成 feature；如果不适用，也应在检查后明确说明。

遗漏清单更新视为改动未完成。
