# Codex 的 hook 定义写下之后不再改写

`~/.codex/hooks.json` 里本应用注册的五条定义，**内容在首次安装之后永不改动**。需要改行为时改的是定义指向的脚本，不是定义本身。

## 为什么

Codex 在 `config.toml` 的 `[hooks.state."<hooks.json 路径>:<event>:<group>:<handler>"]` 下按定义内容哈希记录信任。定义内容一变，Codex 就**静默停止执行该定义**，直到用户重新 `/hooks` 信任；其余未改动的定义哈希不变，继续正常触发。

**这个失败形态是本应用看不见的。** 「是否收到过事件」这条证据会被仍在工作的那几条定义满足，UI 照常显示 Connected，用户不会收到任何提示。2026-08-15 实测：`PreToolUse` 因此连续两轮完全不触发，界面上没有任何异常。

所以版本化整个搬进**脚本**——脚本不参与哈希。定义只写一个稳定路径，除此之外不带任何东西：没有版本号、没有端口、没有 token、没有任何将来可能需要改的参数。

```json
{"type": "command", "command": "/bin/sh '<support>/agents/codex/hook.sh'", "timeout": 3}
```

升级路径因此是「把 `hook.sh` 覆盖成本版本的内容」，`hooks.json` 一个字节都不动，用户不需要重新信任。

## 实测：信任 key 的第三段是数组下标

2026-08-20 在本机 `config.toml` 读到的形状：

```toml
[hooks.state."/Users/…/.codex/hooks.json:pre_tool_use:0:0"]
trusted_hash = "sha256:e304ee0f…"
```

事件名是 snake case，第三段是 **group 在该事件数组里的下标**，第四段是 handler 在 group 内的下标。**这使两条合并规则从「整洁」变成对用户自己的定义有承载作用**：

1. **只在尾部追加，只从尾部移除。** 本应用的 group 永远排在每个事件的最后。从中间移除一个 group 会让它后面所有 group 重新编号，于是**用户自己的**定义静默失去信任。
2. **已经正确的安装不写文件。** `isFullyInstalled` 成立时 `install()` 直接返回。此前打开总开关会重写——并重排——一份本来就正确的文件。

两条都由测试钉住（`registrationMergesAtTheTailAndAnAlreadyCorrectInstallWritesNothing`）。

## 考虑过并否决的方案

**把 helper 直接内联进定义。** Codex 用 shell 解析 `command`，所以整个 helper 可以是一行：

```
/usr/bin/nc -U '<path>/hook.sock' >/dev/null 2>&1; echo '{}'
```

没有脚本文件要写、要升级、要校验；安装健康度塌成「这个确切的字符串在不在」；用户在 `/hooks` 里审阅信任时看到的就是将要运行的东西，而不是一个不透明文件的路径。

**否决，差距很小。** 脚本文件是唯一一层「行为可以变而定义不动」的间接。内联等于用本应用唯一一条免重新信任的升级路径换掉一个文件。只有当 helper 的行为被宣布为最终形态时才值得重新考虑。

**读 `config.toml` 的 `[hooks.state]`，直接报告每条定义的信任状态。** 这会把「靠沉默推断」换成精确答案。否决：它是一个私有 schema 依赖，要在 [`non-public-codex-integration-features.md`](../non-public-codex-integration-features.md) 里登记，且会随 Codex 更新失效，换来的只是改善一个本决策已经基本消除其必要性的诊断。如果 §7.1 的沉默探测被证明不够，这是下一步，并且它自己就是一个 ADR 级别的决定。

## 代价

**迁移时一次重新信任。** 定义从 Python 命令行变成 `/bin/sh '…/hook.sh'`，这一次不可避免——它正是通往「以后再也不变」的那一次。旧的 Python 命令行作为唯一一个 legacy identity marker 保留（匹配 `codex_in_notch_hook.py` 这个文件名，因此命名空间化前后的两种路径都认得），效果是既有安装被识别为 `mismatched` 而不是 `absent`：用户被要求修复，而不是被告知「你还没装」——后者会让他们在旧的旁边再贴一份。

**沉默探测保留。** 「自启动以来 ≥3 次 `PostToolUse` 而 0 次 `PreToolUse` ⇒ `PreToolUse` 已注册但不触发」仍然是运行期唯一能看见失信的证据。本决策堵住的是本应用自己造成该状态的路径；用户手改 `config.toml`、或 Codex 更新重新哈希，仍然可以到达它。只有「缺席确实构成证据」的蕴含式可以进这张表：`PermissionRequest` 只在有人被询问时触发，它的沉默什么也不证明，永远不得探测。

**这条探测此前算得对、也传得下去，但没有任何一个 view 读它**，因此它作为「运行期唯一能看见失信的证据」这句话，有一段时间只在代码里成立（CR-029）。它现在写在 Settings 里该产品那一行的说明行下方。同时那句话本身改了：它原先在一个两个产品共用的 reducer 里点名 Codex 和 `/hooks`，对 Claude Code 是错的建议——那边没有信任步骤，不会因为哈希变化而失信——所以修复方式由各自的 vocabulary 给出。Claude Code 那句此前写的是「去 `~/.claude/settings.json` 里检查 PreToolUse 还在不在」，[ADR 0016](0016-write-the-users-claude-code-settings-and-keep-a-copy.md) 之后改成「把那个开关拨一下」：修复从用户的编辑变成本应用的写入，句子跟着变。

## 状态

已实施。`CodexHookRegistrar` 写定义与脚本，`ManagedHooksFileEditor.install()` 带 no-op 守卫。测试：`theRegisteredDefinitionCarriesNothingThatCouldEverNeedToChange`、`registrationMergesAtTheTailAndAnAlreadyCorrectInstallWritesNothing`、`installingOverAnEarlierVersionsRegistrationReplacesIt`、`closesWithoutOpensReportTheUntrustedPreToolUseHook`。
