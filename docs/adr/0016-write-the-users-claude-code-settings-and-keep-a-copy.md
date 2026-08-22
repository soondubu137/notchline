# 写用户的 Claude Code 设置，写之前先留一份

本应用直接把自己的 hook 注册写进 `~/.claude/settings.json`，并在需要时把它取出来。设置窗口与首次运行里 Claude Code 那一行因此拿到一个开关，和 Codex 那一行一模一样。

**每一次写入之前**，先把该文件当前的样子原样复制到同目录的 `settings.json.notchline-backup`。

这条**取代 [ADR 0010](0010-never-write-the-users-claude-code-settings.md)**。那一条说本应用永不写这个文件，用户自己粘贴；实现里的粘贴卡片、`AgentManualSetup`、`configurationSnippet()` 与 `manualSetup()` 随本决定一起删除。

## 为什么翻过来

ADR 0010 的论证从来不是「做不到」——它自己就写着写入版本已经实现并通过测试，缺的是产品决策。它权衡的是一次错误编辑的影响范围：`~/.codex/hooks.json` 除 hooks 外几乎不含别的东西，`~/.claude/settings.json` 装着用户整个 Claude Code 安装。

那个权衡里被低估的是它自己记下的代价：**这是唯一一处 Claude Code 比 Codex 更难上手的地方**。它当时被写成「开发者工具，其用户本来就在编辑这个文件，可以接受」。实际形态不是这样：

- 用户要从一张卡片里复制一段十几个事件的 JSON，自己合并进一个已经有内容的文件。
- **粘贴不完整会静默失灵。** ADR 0010 自己列了这一条，并要求 `status()` 单独报 `repairRequired`——但本应用只能看出来、说出来，改不动。
- **形状过时同样是用户的活。** [ADR 0013](0013-claude-code-hooks-run-a-helper-not-a-port.md) 把 handler 从 `type: "http"` 换成 `command` 之后，所有已安装的用户必须回去重贴一次，而本应用连那段死掉的 `http` handler 都删不掉——只能认出来，然后请用户自己动手。
- 每次词表新增一个事件（`MessageDisplay` 就是一次）都要用户重贴一遍。

也就是说，ADR 0010 把「本应用有能力修好、且知道该怎么修」的一整类问题，全部转成了用户手工劳动，而这些问题**每一个都不报错**。用一次坏编辑的风险，换掉了一条持续存在的静默失效通道。

## 是什么让写入可以接受

不是信心，是三件已经在代码里的事，加上一件新的。

1. **只碰自己的键。** `ManagedHooksConfiguration` 只增删本应用 identity marker 认得的 handler，用户在同一个事件下的 group 原样保留、位置不动（只在尾部追加）。
2. **看不懂就拒绝，绝不强转。** root 不是对象、`hooks` 不是对象、某个事件不是 group 数组——一律在写之前抛错停下。ADR 0010 之前的实现正是因为把看不懂的东西强转成空字典，才会把一个 root 是数组的合法 JSON 整个覆盖掉。
3. **写前比对字节、写后回读校验。** 读改写期间文件被别人动过就放弃本次写入并报 `changedWhileEditing`；写完重新读一遍确认注册确实完整，否则报错。
4. **新增：每次写入前留一份副本。**

## 副本为什么是「每次刷新」而不是「只留第一份」——**两个产品同一条规则**

`ManagedHooksFileEditor` 原本的语义是**只写一次、永不刷新**，理由是「它先于我们所有编辑，用后来的状态覆盖它就毁掉了唯一值得留的版本」。

本条最初写成「这条对 `~/.codex/hooks.json` 成立，对 `~/.claude/settings.json` 正好反过来」，并据此把刷新说成是 Claude Code 这一侧的特例。**那句话是错的**，而且代码从来没有按它实现过——`preserveRecoveryCopy(of:)` 在共享的编辑器里，两个产品一直走的是同一条路径。回头把两边都算一遍，结论是刷新对两个文件都成立，而 Codex 那一侧的理由更硬：

- **`~/.claude/settings.json`**：它装着用户整个 Claude Code 安装。一个半年前打开开关、此后一直在里面改主题、权限、环境变量和 MCP server 的用户，看到 `settings.json.notchline-backup` 会以为它是「出事之前的我的文件」；只留第一份的语义下它是半年前那一份，还原它就是一次由本应用造成的数据丢失。
- **`~/.codex/hooks.json`**：Codex 按 `<path>:<event>:<group index>:<handler index>` 记信任（2026-08-20 实测，也正是 append-at-tail 规则的由来）。还原一份「本应用第一次编辑之前」的副本，**不只是丢掉用户此后新增的定义，还会把剩下那些的 group 序号整体挪位，于是他们自己定义上的信任静默失效**——Codex 不再跑它们，而任何地方都不报错。这正是 append-at-tail 拼命要避免的那个失效，只是换了个入口走进来。**一份过时的 `hooks.json` 副本比一份过时的 `settings.json` 副本更危险，不是更安全。**
- 而且只留第一份的语义在**本应用自己创建的文件**上根本不自洽：创建那次没有副本可留，于是它冻结在本应用**第二次**编辑之前——一个谁也叫不出名字的版本。

方向因此对两个文件都一样：**我们写进去的东西，关掉开关就能干净取出来；用户自己那些编辑，任何地方都找不回来。** 副本刷新，语义固定为一句话——

> 本应用最近一次改动它之前，你的文件的样子。

实现上写的是 `write(_:replacing:)` 刚刚读出来并比对过的那份字节，不是再 `copyItem` 一次：少一次读，也没有「副本抓到的版本和被替换的版本不是同一个」的窗口。用 `.atomic` 写，中途崩溃留下的是上一份副本而不是没有副本。写副本失败会让整次写入失败——先有副本，才动用户的文件。

**本应用创建的文件不留副本。** 之前不存在的东西没有更早的版本，留一份空的只会误导。

**升级行为，照实记：** 老版本在 `~/.codex/hooks.json` 旁留下的那份「只写一次」的副本，会在下一次写入时被新语义替换掉。这是有意的——按上面第二条，那份更旧的副本正是最不该被还原的那一份。

**但改名留下了一份孤儿。** 副本名由应用名派生（`hooksConfiguration + ".notchline-backup"`），[改名之前](../../AGENTS.md)它叫 `hooks.json.codex-in-notch-backup`。本机 `~/.codex/` 里就有这么一份 2026-08-12 的文件，代码里现在没有任何地方引用那个名字：它不会被刷新，也不会被读。**本应用不删它**——那是用户文件里的一份恢复副本，删不删由用户决定。代价是这个目录里可能同时躺着两份语义不同的副本，只有新的那份是活的。

## 代价，照实记

- **本应用现在会写用户 Claude Code 安装的中心文件。** 上面四条是全部的保障，没有别的。已知会被拒绝而不是被写坏的情况有测试覆盖（root 不是对象、`hooks` 不是对象、事件形状不认识），每一种都要求文件字节不变且不留副本。
- **`~/.claude/` 与 `~/.codex/` 目录里各多一个文件。** 用户没要过它们。它们是这个决定的价格，设置窗口与首次运行的脚注写明了**两个**文件的名字——此前脚注只写了 Claude Code 那一个，而 Codex 那份副本一直在写，这是一处该说没说。两个开关的 tooltip 也各自写明自己那一份。安装完成的提示里只有 Claude Code 那条点名副本：Codex 那条要带一个必做的下一步（去 `/hooks` 信任），再加一句会和它抢。真正必须落在用户眼前的是**拨开关之前**那一次告知，而那是脚注。
- **不写 `description` 键。** Codex 侧在自己新建的文件根上盖一个 `description` 作为给打开它的人的说明；这里不盖。Claude Code 会校验这个文件的键，而本应用给用户新建这个文件时的第一件事，不该是往里放一个它不认识的键。`descriptionForNewFiles` 因此改成可选，Claude Code 传 `nil`。
- **`repairRequired` 这一态留着。** 本应用现在修得动它了，但一份来自旧版本、事件不全的注册在用户去拨那个开关之前仍然是「notch 一直空着而任何地方都不报错」。所以它继续单独报，不与「关着」合并。这一态下开关本来就显示为关（`isIntegrationEnabled` 对 `repairRequired` 为假），所以说明句写的是「把开关打开」；而「注册齐全却不触发」那条诊断（`restoreDefinitionAdvice`）下开关是开着的，写的是「拨一下」——`install()` 在注册已经正确时什么都不写。
- **Codex 侧不需要新的安全机制，需要的是把它已有的说清楚并钉住。** 这一条最初把副本写成 Claude Code 的新增项，实际它落在共享的 `ManagedHooksFileEditor` 上，两个产品同时拿到了它——而 Codex 那条路径当时**一个测试都没有**。补上 `theUsersCodexHooksAreCopiedBesideThemselvesBeforeEveryChange` 与 `aRefusedCodexInstallLeavesNeitherAnEditNorACopy`。除此之外核对过：本应用写用户文件的路径只有这一个编辑器（其余写入全在自己的 support 目录内），Codex 卸载删掉 helper 与 socket 看着与 ADR 0016 给 Claude Code 的结论相反，但 `AgentHookListener.start` 用 inode 比对判断是否已绑定，socket 文件被删后下一轮 `prepareTransport()` 会重新绑定，所以那是无害的多余动作，不是安全缺口。

- **卸载仍然只取注册。** helper 与 socket 留在本应用自己的 support 目录里——注册没了就没有东西会去跑它，而刷新循环的 `prepareTransport()` 一秒内就会把两者写回来。在这里删它们是自称整洁而实际做不到。

## 影响到的位置

`ClaudeCodeHookSetup.install()` / `uninstall()`、`ManagedHooksFileEditor.preserveRecoveryCopy(of:)`、`ClaudeCodeMonitorService.installHooks()` / `removeHooks()`、`MonitorStore` 的按产品开关（`integrationSwitchIsOnByAgent`、`setupStatusByAgent`、`integrationBusyAgents`、每产品一个 convergence task）、`ProductConnectionRows` 两行两个开关。

测试：`bothProductsInstallTheirOwnRegistration`、`theUsersSettingsAreCopiedBesideThemselvesBeforeEveryChange`、`theUsersCodexHooksAreCopiedBesideThemselvesBeforeEveryChange`、`aRefusedCodexInstallLeavesNeitherAnEditNorACopy`、`installingTouchesOnlyThisAppsOwnKeysInTheUsersSettings`、`aSettingsShapeThisAppCannotReadIsRefusedRatherThanOverwritten`、`aPartialRegistrationReportsThatItNeedsRepair`、`eachProductsIntegrationSwitchMovesOnlyItsOwnProduct`。
