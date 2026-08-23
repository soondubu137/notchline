## 1. 打开 Codex Desktop 开关

`ProductConnectionRows` 绑定到 `MonitorStore.setIntegrationEnabled(true, for: .codex)`（`SettingsWindow.swift:281`）。这个调用只记录用户意图；每个产品各自的收敛任务会应用该意图，并在每一步之后重新读取目标状态，因此连续快速切换会被合并，最终以最后一次切换为准（`MonitorStore.swift:1511`）。收敛过程会依次调用 `LiveCodexMonitorService.installHooks()` → `CodexHookRegistrar.install()`：

1. **空操作保护**——如果注册状态已经是 `.complete`，就不会写入任何内容。重写不仅会重新格式化一个不属于本应用的文件，*还会*重新编号 Hook 组；Codex 使用 `<path>:<event>:<group index>:<handler index>` 作为信任键，因此重写会在没有提示的情况下使用户已经信任的定义失效（`HookIntegration.swift:835`）。
2. **辅助脚本**——以 `0700` 权限创建 `~/Library/Application Support/…/agents/codex/`，并写入权限同为 `0700` 的 `hook.sh`。这个四行脚本会把 payload 传给同一目录中的 `hook.sock`。
3. **编辑文件**——`ManagedHooksFileEditor` 对 `~/.codex/hooks.json` 执行“读取—修改—写入”：在*每次写入之前*，先把刚刚读取的原始字节完整复制到 `hooks.json.notchline-backup`（`0600`）；移除属于本应用的所有当前或旧版 handler；在末尾为每个受管理事件追加一个组；以 `0600` 权限原子写入；最后重新读取并验证。如果根节点不是对象、事件值不是数组，或文件字节在编辑期间发生变化，它会拒绝操作，而不是强行转换（`ManagedHooksFileEditor.swift:36`）。
4. **五项定义**，均无 matcher：`UserPromptSubmit`、`PermissionRequest`、`PreToolUse`、`PostToolUse`、`Stop`。Handler 为 `{"type":"command","command":"/bin/sh '<helper>'","timeout":3}`（`HookIntegration.swift:374`）。
5. 在 `install.json` 中写入 `installedAt`，删除已废弃的产物，然后由 `prepareTransport()` 立即绑定套接字监听器，使设置完成后的第一个处理轮次无需等待下一次刷新。

在用户通过 `/hooks` 信任这些定义之前，Codex 仍然不会*运行*任何内容——安装成功时，`lastIntegrationMessage` 传达的就是这个信息。

## 2. 打开 Claude Code 开关

它使用相同的 Store 路径和收敛机制，但服务不同：`ClaudeCodeHookSetup.install()`（`ClaudeCodeHookSetup.swift:150`）。

- 首先写入辅助脚本；如果写入失败，**整个安装都会中止**（`verificationFailed`）——如果注册项指向不存在的脚本，每个事件都会输出一次 `ENOENT … posix_spawn`。
- 随后使用*同一个*严格编辑器处理 `~/.claude/settings.json`，备份规则（`settings.json.notchline-backup`）、字节相等保护和回读验证均与 Codex 相同。
- **十一项定义**：`UserPromptSubmit`、`PreToolUse`、`PostToolUse`、`PostToolUseFailure`、`PermissionRequest`、`PermissionDenied`、`Elicitation`、`ElicitationResult`、`MessageDisplay`、`Stop`、`StopFailure`。Handler 带有 `args: []`，用来选择 Claude Code 的 exec 形式（只启动一个进程；实测耗时 6.3 ms，而另一种形式为 10.9 ms）。即使是由本应用创建的文件，也不会写入 `description` 键，因为 Claude Code 会校验这些键。
- ADR-0013 之前的 `http` handler 会通过 `/codex-in-notch/hook` 标记被识别，并在写入当前版本 handler 的过程中被**移除**。
- 无需信任步骤。套接字会在下一次刷新调用 `prepareTransport()` 时绑定。

事件数量分别是五项和十一项——我已修正先前的记录；那份记录仍沿用移除 `Notification` 之前的数据，把 Claude Code 写成了十二项。

## 3. 关闭任一开关

收敛过程会依次调用 `removeIntegrationAndWait` → `service.removeHooks()`。

- **两个产品都会执行**：编辑器会从所有可解析的事件中移除属于对应产品的每个 handler（移除时没有任何事件采用“严格”模式，因此其他位置的异常事件不会阻止卸载）；先刷新备份；验证所有 handler 均已移除；如果文档任意位置仍残留标记，则抛出 `unremovableManagedCommand`。
- **Codex 还会执行**：重置 Hook 观察结果并清空处理轮次；停止监听器；删除辅助脚本、`install.json`、套接字和已废弃的产物；移除已经为空的目录；并清除已观察到的 Desktop pid、跟踪中的会话、刷新任务与门控，以及 `lastTrustedSnapshot`。
- **Claude Code 会有意保留**辅助脚本和套接字——注册项移除后不会再有任何内容运行它们，而刷新循环会在下一秒内重新写入两者。
- 随后，Store 会**只为该产品**记录一份合成快照：`.setupRequired`、无会话、额度不可用、`setupStatus: .notInstalled`，并保留在场状态。这里替换键而不是移除键，正是为了防止卸载一个产品的集成时，另一个产品的行也从刘海区域消失（`MonitorStore.swift:1636`）。
- 如果移除操作抛出错误，开关会弹回原位（`setSwitch(!desired)`），错误则写入 `lastIntegrationMessage`。操作期间开关处于禁用状态。

## 4. 如何判定 `Connected`

判定基于两个相互独立的事实。它们先由 `HookSetupStatus.card(registration:hasObservedEvent:)` 投影（`HookIntegration.swift:37`），再在 `ProductSettingsCopy` 中与集成可用性交叉判断。

- **注册状态**来自纯文件读取：`complete` / `mismatched` / `absent`。
- **事件送达**：Codex 会判断是否*曾经*有 Hook 事件进入 reducer，即 `hasObservedEvent`。应用启动时，它由 `install.json` 中的 `lastEventAt` 提供初始值；第一个 payload 成功进入 reducer 后，它会被设为 `true`。Claude Code 始终无条件传入 `hasObservedEvent: true`，因为它没有信任步骤，所以不可能出现“已经注册但从未信任”的状态。
- **Codex 行**：当设置状态为 `.active`（或 `.reviewRequired`），**并且**集成可用性为 `.ready` 时，显示 `Connected · compatible version`。`.ready` 要求设置门控通过、`codex app-server --listen stdio://` 子进程成功启动，并收到 `initialize` 握手响应；携带会话行的分支还要求观察到实时 Hook，而且其中的 Desktop pid 必须与当前正在运行的进程一致。
- **Claude Code 行**：只根据 `setup.status() == .active` 显示 `Connected · hooks installed`，也就是 `settings.json` 中每项定义都恰好有一个当前版本的 handler。如果设置状态为 `.active`，但集成可用性为 `.disconnected`，则改为显示 `Registered · the hook helper could not be set up`。

这段设置行逻辑中有两点值得特别注意：

- Codex 行读取的是 `store.availability`，即**合并后的**集成可用性；Claude Code 行读取的则是 `store.agentAvailability(for:)`（`SettingsWindow.swift:298` 与 `:304`）。合并逻辑是“只要*任一*产品为 ready，结果就是 ready”（`MonitorDomain.swift:837`）——因此，当 Claude Code 为 ready 时，Codex 行可能依据 Claude Code 的证据显示 `Connected · compatible version`。
- `.reviewRequired`（Codex Hook 已写入，但从未在 `/hooks` 中得到信任）不会在这一行中体现：它会通过 `notInstalled` / `repairRequired` 检查，并继续进入集成可用性分支，因此同样显示 `Connected · compatible version`。它自己的提示语 `Installed; trust it under /hooks in Codex` 只存在于 `HookSetupStatus.displayName`，供其他位置使用。

## 5. 如何判定 `compatible version`

它只是 `.ready` 对应的标签——并不存在单独的版本探测。真正承载版本含义的是它的反面：当 App Server 请求返回 JSON-RPC **-32601，method not found** 时，会设置 `.unsupportedVersion`（`Version unsupported`）（`LiveCodexMonitorService.swift:341`、`CodexAppServerClient.swift:131`）。因此，`compatible version` 的含义是：App Server 已启动、已响应 `initialize`，并且尚未拒绝本应用所需的方法。

`Update Codex Desktop`（`.updateAgent`）是无法触发的文案——没有任何实时服务会产生这个 case，只有消费方引用它。

## 6. 其他所有状态

| 显示内容                                                     | 设置条件                                                     |
| ------------------------------------------------------------ | ------------------------------------------------------------ |
| `Integration is off`（两个产品）                              | 注册状态 `.absent` → `.notInstalled`：整个文档中都不存在本应用的标记。文件缺失、为空、不可读或根节点不是对象时也属于此情况 |
| `Integration needs repair`（Codex）/ `Registration is out of date · turn the switch on to rewrite it`（Claude Code） | 注册状态 `.mismatched`：存在当前或旧版标记，但并非每个受管理事件都恰好有一个**当前版本**的 handler。“当前版本”要求整个字典与本构建写入的 handler 完全相等，因此过期的 `timeout`、多余或缺失的键、旧辅助脚本路径、重复的组或旧版 `http` handler 都会进入此状态（`ManagedHooksConfiguration.swift:260`） |
| `Connecting…`（Codex）                                       | `.connecting`：App Server 请求发生暂时性失败，而且没有可保留的最后可信快照；在任何产品作出响应之前，这也是合并后的默认状态 |
| `Disconnected`（Codex）                                      | 非暂时性失败——找不到可执行文件、启动失败、违反协议或连接中断；或者在服务器首次响应前发生暂时性失败 |
| `Registered · the hook helper could not be set up`（Claude Code） | `.active` + `.disconnected`；对于这个产品，这表示 `prepareTransport()` 返回 `false`：无法写入辅助脚本或绑定套接字——可能是文件夹不可写，也可能是应用的另一个实例已经占用它（`ClaudeCodeMonitorService.swift:1410`） |
| 状态下方额外显示的灰色文字                                  | `latestByAgent[agent]?.diagnostic`——该产品在本次刷新中产生的诊断信息；没有异常时不显示 |
| 开关自身的位置                                               | 每次刷新后，`applyIntegrationHealth` 都会根据 `setupStatus.isIntegrationEnabled` 重新推导开关状态——`active` / `reviewRequired` 时打开，`notInstalled` / `repairRequired` 时关闭；正在变更时除外。这使“打开开关以重写配置”在逻辑上成立：注册项过期时，开关确实显示为关闭 |
| `Recheck`                                                    | 调用 `store.refreshNow()`；Codex 路径会先丢弃缓存的注册状态读取结果，因为用户主动重新检查，是注册健康状态可能在非本应用操作下发生变化的两个时机之一 |
