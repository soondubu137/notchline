## 1. Notchline 自身创建的文件

这些文件全部位于 `~/Library/Application Support/Notchline/` 下，并按产品划分命名空间（`agents/codex/`、`agents/claudeCode/`），因此卸载一个产品的集成不会连带删除另一个产品的套接字：

| 文件                          | 用途                                                         | 创建位置                                                     |
| ----------------------------- | ------------------------------------------------------------ | ------------------------------------------------------------ |
| `agents/<agent>/hook.sh`      | 产品每收到一个事件便运行一次的四行辅助脚本（通过 `nc -U` 写入套接字）。权限模式为 `0700`；只要文件字节与当前构建中的版本不同，就会重写 | `ClaudeCodeHookSetup.swift:111`、`HookIntegration.swift:825` |
| `agents/<agent>/hook.sock`    | 监听器绑定的 Unix 域套接字。路径特意保持简短——`sun_path` 的上限是 104 字节 | `AgentHookListener.swift:180`                                |
| `agents/<agent>/install.json` | 包含两个日期（`installedAt`、`lastEventAt`），权限模式为 `0600`。每次启动只写入一次 `lastEventAt`，它也是唯一会被回读的字段 | `HookIntegration.swift:652`                                  |
| `agents/claudeCode/usage/`    | 空目录。它仅作为应用自身运行 `claude -p /usage` 时固定使用的工作目录，使会话注册表和 Hook 存储能把这类会话与用户创建的会话区分开来 | `ClaudeCodeUsageReader.swift:419`                            |

应用还会在自身目录**之外**写入另外两类文件，也就是用户的产品配置文件：

| 文件                                                         | 说明                                                         |
| ------------------------------------------------------------ | ------------------------------------------------------------ |
| `~/.codex/hooks.json` / `~/.claude/settings.json`            | 原地编辑，并且只修改应用自身的键。以原子方式写入，权限模式为 `0600`；写入前会比较字节，写入后会回读 |
| `~/.codex/hooks.json.notchline-backup`、`~/.claude/settings.json.notchline-backup` | 用户文件在最近一次修改前的副本——**每次写入都会刷新**，并非保留首次修改前的版本（`ManagedHooksFileEditor.swift:192`） |

此外还有偏好设置文件 `~/Library/Preferences/com.yinfenglu.Notchline.plist`，其中包含四个键（`productAttribution`、`quotaFolded`、`hasCompletedOnboarding`、`selectedDisplayID`）。

Hook 事件的 payload 完全不会写入磁盘——它们会直接进入内存中的 reducer，因此不存在预览缓存、事件队列或会话状态文件。

## 2. 唯一会持续增长的内容：额度读取 transcript

```
~/.claude/projects/-Users-<you>-Library-Application-Support-Notchline-agents-claudeCode-usage/
```

每次额度读取都是一个真实的 Claude Code 会话，因此 Claude Code 会在自己的项目树中为每次读取保存一份约 3.4 KB 的 `.jsonl` transcript。每 5 分钟读取一次（`freshness: 300`）——应用运行期间每天大约产生 **1 MB**。目前这台机器上共有 **214 个文件，占用 852 KB**。

Notchline 会统计这些文件的大小，但绝不会删除它们——文件夹命名规则会同时扁平化路径分隔符和空格，所以 `…/a b` 与 `…/a-b` 会落入同一个目录，而这个文件夹也可能包含用户的真实工作内容。设置页会显示其大小，并提供 `Show in Finder` 文件夹图标按钮（tooltip 即 `Show in Finder`）；是否处理由用户自行决定（`ClaudeCodeUsageTranscripts.swift`、`SettingsWindow.swift`）。

Codex 一侧不会留下同类文件——它通过 `codex app-server` 的只读 `account/*` RPC 获取额度，不会创建对话。

## 3. 一项值得了解的情况

你的应用支持目录中还留有日期为 8 月 14 日的 `~/Library/Application Support/Notchline/current-activity.json` 和 `current-activity.lock`。**当前工作树中没有任何代码会读写它们**，它们也不在 `retiredArtifacts` 删除列表中（`HookIntegration.swift:160`）——所以这是旧版构建留下的残留文件，安装和卸载都不会清理。它们很小（分别为 258 字节和 0 字节），没有危害，但卸载后仍会保留。

另外，仓库根目录中的 `default.profraw` 是运行插桩二进制文件后生成的覆盖率构建产物，并非发布版应用产生的文件。
