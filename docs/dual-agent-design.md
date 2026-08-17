# 双产品设计 — Codex 与 Claude Code

| 字段 | 内容 |
| --- | --- |
| 文档状态 | 视觉与数据口径已定；域层与合并层已落地（`claude-code-integration` 分支），UI 尚未开始 |
| 版本 | 1.0 |
| 日期 | 2026-08-16 |
| Figma | [`10 — Double Apps`](https://www.figma.com/design/B9qIi46zhdjbQYbjZo3AnM/Codex-in-Notch-%E2%80%94-V1?node-id=540-2)；设置项在 [`09 — Settings`](https://www.figma.com/design/B9qIi46zhdjbQYbjZo3AnM/Codex-in-Notch-%E2%80%94-V1?node-id=609-2) |
| 相关 ADR | [0007](adr/0007-read-claude-code-quota-from-the-cli.md)、[0008](adr/0008-count-today-tokens-cache-inclusive.md)、[0009](adr/0009-resolve-project-per-product.md) |

## 1. 范围

本文只描述同时监视 Codex 与 Claude Code 时的界面与数据口径。集成可行性、Hook 事件映射与降级导航见 [`technical-explorations/claude-code-support`](technical-explorations/claude-code-support/README.md)；单产品的既有契约仍以 [`figma-design.md`](figma-design.md) 为准，本文只记录相对它的差异。

**只有一个产品有会话时，界面与今天完全一致。** 收起态宽度、展开态高度、行内标记、额度行数都不变，只有色调不同。所有新增元素都以"两个产品都有会话"为出现条件，这与既有的尾翼规则一致：没有内容可说的翼被移除，而不是留空。

判断每个方案时使用的既有约束，均来自当前已发布的界面：

1. 色相表示产品，亮度表示是否需要用户处理。两个通道不得互换。
2. 无内容可说的区域被移除，不是变暗。
3. 未完成的行只有一个标记。
4. 宽度由真实渲染文本测量得到，不写死。
5. 取不到的数据显式降级，不用近似值填补。

## 2. 颜色

| 用途 | Codex | Claude Code |
| --- | --- | --- |
| 点亮格（`matrixOn`） | `#6CB4FF` | `#D97757` |
| 熄灭格（`matrixOff`） | `#101B26` | `#21120D` |
| 行内归属文字（caption 亮度） | `#4D81B7` | `#9C553E` |

熄灭色是点亮色的 `15%` 亮度，两组都满足该关系，因此新增产品只增加两个变量。Figma 组件集 `Status Matrix / Claude Code` 由 Codex 版克隆后改色得到，几何与四条逐格透明度曲线完全一致。

## 3. 收起态

### 3.1 状态矩阵成对出现

两个矩阵并排位于前导翼，`16.6` 见方，间距 `6`。间距取 `6` 是因为它落在矩阵自身 `5.84` 的格距上，读起来像缺了一列而不是随意的空隙；`4` 会与格内 `0.9` 的间距混同为一个 3×6 网格，`8` 则不再成对。

**顺序固定：Codex 在前，Claude Code 在后，与各自状态无关。** 认出两种颜色之后，位置是唯一的身份线索；按紧急度排序会让两个标记在用户正要读取的瞬间互换位置。前导翼从左边缘紧凑排布，因此只有 Claude Code 有会话时，它的矩阵出现在 Codex 矩阵原来的位置。

### 3.2 几何

| 项目 | 双产品 | 单产品 |
| --- | --- | --- |
| 前导翼 | `24 + 16.6 + 6 + 16.6 + 8 = 71.2` | `24 + 16.6 + 8 = 48.6` |
| 刘海形态总宽 | `331.6 × 46` | `309 × 46` |
| 无刘海形态 | `24 + 矩阵 + 12 + 状态名 + 32 + 计时 + 24` | 同左，少一个矩阵与一个间距 |

无刘海形态在状态名为 `Approval` 时实测 `215.6 × 46`。所有宽度仍按真实文本测量，上表只记录组成关系。

### 3.3 计时与状态名

尾翼仍然只有一个计时，取两个产品中最长的未完成处理轮次。两个独立计时并列会被读成故障而不是功能；面板本来就在挑选最早的未完成轮次，只是不再按产品过滤。

无刘海形态的状态名仍然只有一个，**保持灰色**，取两个产品中最紧急的状态，顺序沿用 `Input needed > Approval needed > Running > Completed`。

状态名不着色，有两条独立的理由。其一，矩阵各自运行自己的动画曲线，状态在状态名被读到之前已经由图形表达过了，再给文字上色等于对同一件事做第三次编码。其二，被否决的着色方案编码的其实不是状态而是产品；即便按这个读法它同样冗余——正在闪烁的那个矩阵就是需要用户处理的那个——而且它会把色相和亮度压在同一段短文本上，而亮度是这个界面的注意力通道，也是两者中更重要的一个。着色方案已在 Figma §04 绘出并否决，不作为备选保留。

## 4. 展开态：行归属

处理轮次的排序不变，因此两个产品的行是交错的，每一行都必须说明自己属于谁。**该标记只在两个产品都有会话时绘制。**

三种呈现方式，由设置项选择，全部落在行首的 `11 pt` 说明行上，因此都不向面板增加任何笔画：

| 选项 | 呈现 | 说明 |
| --- | --- | --- |
| `Name and colour`（默认） | 说明行前缀 `Codex ·` / `Claude Code ·`，取该产品的 caption 亮度色 | 不新增元素、不新增线条；去掉色相后文字仍然成立 |
| `Name only` | 同上，颜色为 `#7C7C80` | 几何完全相同，切换不改变任何宽度；完全不依赖颜色 |
| `Badge` | 小徽章：暗底亮字 | 高 `16`、圆角 `5`、左右内边距 `6`、`10 pt` Medium；底色 `#101B26` / `#21120D`，文字 `#6CB4FF` / `#D97757` |

`Badge` 使矩阵的熄灭色与点亮色分别成为底与字，说明行高度由 `14` 变为 `16`，行内容块由 `53` 变为 `55`，行高仍为 `80`。

默认取 `Name and colour` 的理由：它是唯一什么都不增加的方案，也是唯一色相只作为强化而非全部信号的方案。代价是横向空间——`Claude Code ·` 约占 `394` 宽说明行中的 `73`，被挤压的是 Project 文本本身；说明行是一行里最不重要的一条，且以渐隐而非省略号收尾，因此可以接受。

已评估但不提供的三种：行首色条（向已有四条横线再加三条竖线）、每行小矩阵（一行出现第二个标记，必须让计时退回中性来抵偿）、给计时上色（同一段文本同时承担色相与亮度两个通道）。三者的完整推理与图见 Figma §06。

## 5. 展开态：额度与当日用量

### 5.1 结构

每个产品一行规则，每条规则下方紧跟自己的说明；两个当日用量合并为最下面一行。

```
════════════════════════════════════════════  Codex，整宽
72% left · Resets in 3 days 12 hours
═══════════════────  ═══════════════════────  Claude Code，两个半宽
5 h · 59% left · Resets in 2 hours    7 d · 85% left · Resets Friday
Codex 310.1M · Claude Code 208.6M today
```

| 项目 | 值 |
| --- | --- |
| Codex 规则 | `472 × 3`，`y = 0` |
| Codex 说明 | `y = 8` |
| Claude Code 规则 | `232 + 8 + 232`，`y = 30` |
| Claude Code 说明 | `y = 38`，左半 `x = 0`，右半 `x = 240` |
| 当日用量行 | `y = 58` |
| 页脚总高 | `84`（今天为 `43`） |
| 展开面板 | `520 × 370`（双产品）／`520 × 326`（单产品） |

Codex 占满整宽是因为它只有一个窗口；Claude Code 被平分是因为它有两个。半宽等分不是为了塞下，而是因为那一侧确实有两个窗口——这是这个结构成立的全部理由。

单产品时页脚形态不同：只有 Codex 时保持今天的一行内联形态（页脚 `40`）；只有 Claude Code 时两个窗口已占满说明行，当日用量仍需单独一行（页脚 `54`）。这一处不对称落在两种单产品形态之间，是本方案已知且已接受的代价。

### 5.2 显示哪些窗口

`/usage` 报告三个窗口：`Current session`（5 小时）、`Current week (all models)`、`Current week (<模型>)`。**只画前两个，且固定不变**：左半永远是 5 小时全模型窗口，右半永远是 7 天全模型窗口。

按模型的周上限本期忽略。它对不使用该模型的用户恒为零；让某一半在不同时刻报告不同窗口，会让一条本来只用于扫一眼的规则变得必须先读说明才能理解。已知风险照实记录：用完按模型上限的用户会看到两条健康的规则却仍被拒绝。如果实际发生，正确的修法是增加第三个窗口，而不是让第二个窗口变形。

百分比按"已用"报告，规则绘制 `100 − used`；重置时间为本地绝对时间戳，按既有风格渲染为相对时间。

### 5.3 设置按钮移入顶栏

页脚四条说明已占满 `472`，设置齿轮移到面板右上角：`46 pt` 菜单栏下为 `32 × 32`，`x = 440`；`24 pt` 菜单栏下缩为 `20 × 20`，`x = 452`。展开态顶栏的尾侧本来就是空的（计时尾翼只在收起态出现），而右上角本就是 macOS 面板放置设置的位置。页脚说明文本因此收回完整的 `472`。

**该改动对单产品同样生效**，已应用到 `Expanded Footer` 组件与 `Panel` 的三个 Expanded 变体，Figma 中所有展开面板已随之更新。两种模式下位置一致，避免第二个产品出现时齿轮跳位。

## 6. 设置项

设置窗口是单面板，没有侧边栏（见 [`figma-design.md`](figma-design.md) §8.0）。`Session list` 是其中第二个分组，位于 `Products` 与 `Privacy` 之间，只含一个弹出菜单：

| 标签 | `Distinguish products` |
| --- | --- |
| 说明 | `How a row shows which product it came from.` |
| 选项 | `Name and colour`（默认）／`Name only`／`Badge` |
| 脚注 | `Only applies when both products are running — with one product there is nothing to tell apart.` |

单产品运行时该项仍然可见但无效果。隐藏它会让用户恰好在准备接入第二个产品时找不到它。

两个产品的集成开关不再各占一个分组：`Codex Desktop` 与 `Claude Code` 是 `Products` 卡片里的两行，各带一个 switch，共用一条脚注和一个 `Recheck` 按钮。第三个产品的代价因此是一行。

## 7. 数据来源与口径

### 7.1 额度

见 [ADR 0007](adr/0007-read-claude-code-quota-from-the-cli.md)。要点：`claude -p "/usage" --output-format json`，不经过模型，实测约 `4.3` 秒、`total_cost_usd` 为 `0`。**这是后台定时刷新的数据源，不能在展开面板时同步调用。** 每次调用写入一个约 `3 KB` 的 transcript，把工作目录固定下来可以把这些文件收敛到一个目录以便清理。解析失败必须降级为不可用的完整轨道，不得沿用旧值。

`~/Library/Application Support/Claude/plan-usage-history.json` 不再使用。

### 7.2 当日 token

见 [ADR 0008](adr/0008-count-today-tokens-cache-inclusive.md)。口径为"全部被处理的输入（含缓存读取）加输出"：

- Codex — `dailyUsageBuckets[].tokens`，按本地日历日键入。
- Claude Code — `~/.claude/projects/**/*.jsonl` 中每条 assistant 记录的 `message.usage`，取 `input_tokens + cache_creation_input_tokens + cache_read_input_tokens + output_tokens`，按 `timestamp` 前十位分日累加。

该来源由 CLI 自己写入，因此对每一个 Claude Code 用户都成立，包括没有 Claude Desktop 的用户。

### 7.3 Project

见 [ADR 0009](adr/0009-resolve-project-per-product.md)。Project 按产品解析：Codex 行是 Desktop 中用户创建的 Project 或 `Chats`；Claude Code 行是会话的工作目录（`cwd`），行内显示路径最后一段，完整 `cwd` 作为无障碍名称。[ADR 0003](adr/0003-use-codex-desktop-project-identity.md) 的路径推断禁令自此仅约束 Codex 一侧——它的理由是路径与 Desktop Project 不是一一对应，而 Claude Code 的 `cwd` 本身就是该产品的分组单位。

## 8. 未决事项

| 事项 | 状态 |
| --- | --- |
| 展开态顶栏状态名是否附带产品名 | 待定，构建前重新评估 |
| 是否超出四个状态（`StopFailure` 带 `error`） | **已定：保持四态。** 只有 Claude Code 能观察到的状态会让这套共享词汇在 Codex 上说谎——用户无法区分「没有失败」与「无法观察到失败」。失败作为终态原因随行，行上的标记不变。字段名是 `error` 而非 `error_type`（CLI 2.1.233 实测） |
| `dailyUsageBuckets.tokens` 与 CLI `total_tokens` 是否同口径 | 待验证，低优先级；不阻塞任何布局 |
| 同名目录的两个检出如何消歧 | 未定 |
| Claude Code hook 注册由谁写入 | **已定：用户自己写。** 本应用只读 `~/.claude/settings.json`、显示待粘贴内容、报告注册是否完整，永不写入。Codex 侧维持自动写入 `~/.codex/hooks.json`。见 [ADR 0010](adr/0010-never-write-the-users-claude-code-settings.md) |
| 产品改名 | 候选见 Figma §07；`Baton` 为推荐项 |
| 双产品无刘海紧凑标签由哪一状态定宽 | **新增，待定。** 见下 |

降级导航已确认并接受：Claude Code 行只能唤起 Claude Desktop 或聚焦终端，行内不为此增加任何标记。

**紧凑标签定宽状态在双产品下换人。** 单 Codex 时最宽的紧凑状态是 `Approval`，它靠同时占用标签与计时槽取胜，任何不计时的状态都追不上它。加入 Claude Code 后冠军变成一个**不计时**的状态：`Update Claude Code` 比 `Approval` 加计时槽更长。本机实测 13pt Light：`Approval` + 12 + `1:02:03` = 112.3，`Update Claude Code` = 124.8，无刘海药丸宽度因此从 189 变为 202。

这不是缺陷，是一个产品问题。紧凑状态名只有一个，且命名的是跨两个产品最紧急的状态（§3.3），所以它不能像其他紧凑标签那样把产品名省掉——省掉之后「Update」不说明该更新哪一个。可选项：接受 202；或者接受该标签在双产品下不指名产品；或者为 `updateAgent` 设计一个更短的紧凑形式。在此之前，`PanelMetrics.fixedCompactWidth(for:)` 按用户实际配置的产品集合折叠，单 Codex 用户的宽度与今天逐点一致，由 `aCodexOnlyConfigurationHasTodaysExactPanelGeometry` 固定。

## 9. 与既有文档的关系

[`figma-design.md`](figma-design.md) 描述单产品契约，其中两处已被本文取代：设置齿轮的位置（§4.5，现为顶栏右上角）与页脚额度行的构成（§4.3，双产品时为两行规则加当日用量行）。其余部分不受影响。

例外是设置窗口：`figma-design.md` §8 已按 macOS 26 重写，其中 `Products` 分组直接容纳两个产品，`Session list` 分组来自本文 §6。设置窗口的结构、几何与颜色以 §8 为准，本文只保留 `Distinguish products` 的语义。
