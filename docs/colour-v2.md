# Notchline — Colour V2: one hue, and it is the user's

| Field | Value |
| --- | --- |
| Status | **Decided by the board's owner, not implemented.** The decision is §1; everything after it is the consequence worked out. |
| Version | 1.0 |
| Date | 2026-09-04 |
| File | [Notchline V2](https://www.figma.com/design/c3CQBBk3Boiu0oM00Vvs9Y/Notchline-V2) — `09 — Identity without a palette` records the argument that led here. **It draws a weaker proposal than this document**: it kept `Name and colour` as the default and made the badge grey. The decision went further on both counts, so that page is the reasoning and this file is the contract. |
| Scope | Every surface that draws a product hue or a per-agent figure: the expanded header band, the session row's attribution, the quota footer's product names, and the Display settings that name them. The collapsed bar is already free of both and is untouched. |
| Supersedes | [`dual-agent-design.md`](dual-agent-design.md) §2 (the colour table) and §4 (the four attribution presentations and the setting behind them). [`expanded-header-v2.md`](expanded-header-v2.md) §4 entire, §4.4's inks, §5's per-agent states, §6.2's sizing by agent count, §7's new row, §9's first bullet, and §10 questions 02, 03 and 05. [`quota-footer-v2.md`](quota-footer-v2.md) §2's two heights and §4's product-in-its-lit-ink rule. [`expanded-panel-v2.md`](expanded-panel-v2.md) §2.3's product-in-caption-ink and the four presentations reaching the breadcrumb. [`figma-design.md`](figma-design.md) §3.2's colour tokens, §4.1's `Colour bar` gutter rule, §8.4's `Mark colour` label and §8.5's `Distinguish products` control. [`PRD.md`](PRD.md) §12's Display list, items 1 and 3. [`CONTEXT.md`](../CONTEXT.md)'s **Product** and **Disconnected**. |

## 1. The decision

**Colour is no longer an element of Notchline.** No product owns a hue, and no figure on any surface is drawn in one product's ink rather than another's. Two things follow, and they are the whole of this document:

1. **The expanded panel drops the decomposition.** The band draws the aggregate mark and the accumulated totals. It does not break those totals into one column per agent, in any channel.
2. **A product name is a badge, tinted by the theme colour.** Wherever a product is named on the notch surface, it is named inside a chip with a dark ground and bright text, taken from the ink the user picked. The name is never tinted, prefixed, barred or otherwise coloured to say which product it is — the name says which product it is, because it is the name.

What survives is one hue: the twelve-entry palette in [`aggregate-ink-palette.md`](aggregate-ink-palette.md), chosen once by the user, applied to the mark and now to every badge. It says *Notchline*, and it says nothing about which vendor.

## 2. Why this is the same argument the file has been making

Three documents already reached parts of it and stopped short of the whole:

| Where | What it settled | What it left standing |
| --- | --- | --- |
| [`compact-view-v2.md`](compact-view-v2.md) §1 | The collapsed bar's three per-product channels all answered *which product*, "and that question is not actionable at this size" | The band and the row went on asking it, on surfaces `46` pt and `80` pt tall |
| [`dual-agent-design.md`](dual-agent-design.md) §1 | Permanently dimming an unused product's matrix "amounts to advertising someone else's tool" | Drawing every vendor in its own brand colour, across a surface the user did not give them, is that objection one step milder |
| [`aggregate-ink-palette.md`](aggregate-ink-palette.md) §2 | "With one aggregate mark, hue stops meaning *which product* and becomes free" — and the file then gave it to the user | If hue is the user's, it is not also the vendors'. That second half was never said out loud |

The palette rule the file was holding in reserve — [`expanded-header-v2.md`](expanded-header-v2.md) §10 question 03, *each new product takes the hue farthest in OKLCH from every product already configured* — does not survive being run. With Codex at `258°` and Claude Code at `42°` the two maxima are `150°` and `330°`, and `150°` is the farther from both. **It is also Sage**, the palette's own default, chosen on that page for being equidistant from both products. The rule and the default were derived from the same geometry, so the first agent the rule places is guaranteed to collide with the mark it stands beside. After that the minimum separation falls `144° → 108° → 72° → 54° → 36°`, on numerals `6.6 × 7.75` pt whose coloured area is a digit stem under a point wide.

**Neither this rule nor that one can make eight agents distinguishable at that size.** The difference is what happens when they are not. Under the generated rule that is a defect, because the band has nothing else. Under this one it cannot arise, because nothing is asked of colour at all.

## 3. The band: the totals, and nothing under them

[`expanded-header-v2.md`](expanded-header-v2.md) §4.1 stands whole and is now the entire section. §4.2, §4.3 and §4.4 are void.

```
12 + 16.6 + 4 + 13.2 + 8   │   cut-out   │   8 + gear + 12
```

| Term | Value | Note |
| --- | --- | --- |
| Panel inset | `12` | `expandedHorizontalPadding`, unchanged |
| Aggregate matrix | `16.6` | `statusMatrixSize`, unchanged, one for every agent at once |
| Mark-to-counts gap | `4` | The collapsed bar's own |
| The totals | `13.2` | Reserved at two digits, in `#C7C7CC` over `#7C7C80`, drawn whatever is connected |
| Clearance | `8` | `expandedNotchClearance`, unchanged |

**The leading side is `53.8` at every agent count.** It was `98.2` at two, `136.6` at four and `213.4` at eight; §6.2's table of leading sides by working-agent count becomes one number. The panel is `520` at every cut-out this product meets and at every number of agents — including the five and six that used to push it to `532` and `571` — so `PanelMetrics.expandedWidth(centerOcclusionWidth:workingAgentCount:)` loses its second parameter and the branch that read it.

**The leading group is now identical collapsed and expanded**, mark at `12` and totals at `32.6`, with nothing appearing on hover and nothing moving. That was already half true; it is now true without qualification.

### 3.1 What the band stops being able to say

It can no longer say **how the work is split across agents**. That is a real loss and it is taken deliberately, on three grounds:

- **The decomposition is already drawn, in words, `46` pt below.** The band exists only while the panel below it is open, and that panel is the split — one row per session, each naming its own agent on its own caption line. The columns were a second copy in a channel that cannot hold a name.
- **The question is the one page 01 removed from the bar**, on a surface only `34` pt taller.
- **The band already could not say which agents are *connected*** ([`expanded-header-v2.md`](expanded-header-v2.md) §8.3) — an idle agent drew no column, and a dark one drained its rows and then drew none either. It was answering a narrower question than it appeared to.

**No hover replacement is specified.** §10 question 05's tooltip stays parked where it is: available if the loss is felt, and not part of this change. If it is ever built it names the agents in words and re-introduces no hue.

## 4. The badge

One presentation, everywhere, drawn from the existing `Badge` option's geometry:

| Property | Value |
| --- | --- |
| Height | `16` |
| Corner | `5` |
| Horizontal padding | `6` each side |
| Text | `10 pt` Medium, the theme ink's **lit** value |
| Ground | The theme ink's **unlit** value |
| Width | `6 + measured text + 6` — measured from real rendered text, never tabulated (constraint 4) |

At the default **Sage · hint** that is ground `#1B1F1C`, text `#DEE8E0`. Every one of the twelve entries in [`aggregate-ink-palette.md`](aggregate-ink-palette.md) §3 is already a dark/bright pair at one fixed pair of lightnesses, so the badge is legible at every setting by construction and no entry needs checking against this use.

**The badge is drawn only while more than one product is connected**, on `MonitorStore.showsProductAttribution` exactly as the attribution marker is today — presence, not "who has threads right now" ([`dual-agent-design.md`](dual-agent-design.md) §4). With one product there is nothing to tell apart, and this matters more than it did: the lit ink is the value the mark reaches when it wants a person, so drawing it at rest on every row is a real cost and is paid only where it buys something.

**Brightness order inside a row is unchanged.** Title white at 98% (`L 0.985`) → badge text (`L 0.921`) → caption and preview `#7C7C80` (`L 0.588`). The badge is the second-brightest thing in a row where it used to be third — the product inks it replaces sat at `L 0.754` and `L 0.672` — but the chip is `10 pt` of text on a near-black ground inside a `16` pt box, so the lit area is small and the row's ranking holds. §10 question 01 is where this is watched.

**The hue lives in the text, not in the ground, and that is by construction.** Every unlit value in the palette runs at `0.55 ×` the lit chroma at `L 0.235`, which is what makes the dark grid carry any hue at all on a `5 × 5` mark — at badge size it reads as near-black whichever entry is chosen. Sage's ground is `L 0.234` and Rose's `L 0.236`, and the twelve are indistinguishable from each other. So switching theme visibly changes the badge's **text** and barely touches its ground. This is the right way round: the ground's job is to be a boundary and the text's is to be the colour, and it means the chip's contrast is identical at every setting rather than something to check twelve times.

**The badge replaces the caption's product prefix and nothing else.** The Project after it stays `#7C7C80`. The caption line grows `14 → 16` and the row's content block `53 → 55`, with the row height still `80` — the same two points `Badge` already cost as one of four options.

## 5. Where a badge is drawn

| Surface | Today | Now |
| --- | --- | --- |
| Session row caption | `Codex ·` in the product's caption ink, or one of three other presentations | The badge, then the Project |
| A row's breadcrumb below the seam ([`expanded-panel-v2.md`](expanded-panel-v2.md)) | All four presentations reach it | The badge, in place of the prefix |
| Quota footer, opened table's outer row | `Codex ────── 310.1M today` | Badge, leader, spend |
| Quota footer, the spoken line | `Claude Code · 5 h · 8% left · 47m` | Badge, then `5 h · 8% left · 47m` |
| Expanded header band | One column per agent, in that agent's inks | Nothing — §3 |
| Collapsed bar and pill | Nothing already | Nothing |
| Settings, the Products list | Product name, with `product/codex` / `product/claude` tokens available | Product name in `text/primary`. **No badge, and both tokens retire** — §6 |

**The native windows do not take the badge.** Settings and Onboarding have light and dark modes (`Color / macOS Window`), and the theme ink is a single dark-ground/bright-text pair with no light-mode counterpart. They also do not need one: a settings list is one product per row and already labelled. What they lose is the two `product/*` colour tokens, which existed only to tint those names.

## 6. The setting

**`Mark colour` becomes `Theme colour`.** It now decides the mark's ink *and* every badge's pair, so a label naming only the mark understates it. Nothing else about the control changes: the same twelve entries at `hint`, the same ordering, the same default, the same stored value, and the same reference mark beside the popup. There is no migration — an install that has picked Steel gets Steel badges.

The caption gains what it now covers. Recommended text:

> Tints the mark on the bar, and the badge that names each product when more than one is connected. Every colour is the same brightness, so the choice never changes what the mark is saying.

**`Distinguish products` retires.** Its four values were `Name and colour`, `Name only`, `Badge` and `Colour bar`; three of them are gone and a one-value picker is not a control. The stored `ProductAttributionStyle` is ignored rather than migrated — every install lands on the badge, whichever of the four it had.

This is the one place the decision removes something a user could already choose. It is accepted: two of the four options were the ones that could not survive a third agent, one was `Badge` itself, and the fourth — `Name only` — is a request for less colour that is now the product's own default position, differing from the badge by a chip.

## 7. Widths

| | Before | Now |
| --- | --- | --- |
| Band leading side, 1 working agent | `53.8` | `53.8` |
| Band leading side, 2 | `98.2` | `53.8` |
| Band leading side, 4 | `136.6` | `53.8` |
| Band leading side, 8 | `213.4` | `53.8` |
| Expanded panel, `220 × 38` cut-out, 5 agents | `532` | `520` |
| Expanded panel, `220 × 38` cut-out, 6 agents | `571` | `520` |
| Row caption line | `14`, or `16` under `Badge` | `16` |
| Row content block | `53`, or `55` under `Badge` | `55` |
| Row height | `80` | `80` |
| Footer, spoken | `45` | `47` |
| Footer, opened table | `19W + 28P + 17` | `19W + 30P + 17` |

The two footer figures move for one reason: a caption line carrying a badge is `16` rather than `footerCaptionHeight`'s `14`, so a product group is `16 + 19w` and the spoken line is two taller. **No new constant is introduced anywhere** — the `16` is the badge height the `Badge` option already defined.

## 8. Accessibility

- **The band's accessible name loses its per-agent clause.** `Codex, 2 sessions, 1 subagent` was the whole justification for a colour-only channel ([`expanded-header-v2.md`](expanded-header-v2.md) §9); with no channel there is nothing to compensate for. The totals block is announced as its two figures and the aggregate status, as the collapsed bar's is.
- **A badge is spoken as its product name**, once, with no mention of the chip. A row reads `Codex, notchline, Run a command in ~/Projects/notchline`.
- **Nothing on the notch surface now depends on colour being seen.** That is a stronger statement than the file has ever been able to make: with the theme ink rendered as flat grey, every figure, name and state on the collapsed bar and the expanded panel still says what it says.

## 9. What each document loses

| Document | Change |
| --- | --- |
| [`dual-agent-design.md`](dual-agent-design.md) | §2's colour table is void — the four product inks and the `15%` derivation with them. §4's four presentations become §4 of this file; its constraint 1, "hue means product, brightness means whether the user is needed", loses its first half |
| [`expanded-header-v2.md`](expanded-header-v2.md) | §4 entire, §5's per-agent state rows, §6.2, §7's last row, §9's first bullet, §10 q02/q03/q05, §11's four column checks, §12's `AgentCountsColumns` and `countsInk(for:)` |
| [`quota-footer-v2.md`](quota-footer-v2.md) | §2's `45` and `19W + 28P + 17`; product names become badges in both the spoken line and the table |
| [`expanded-panel-v2.md`](expanded-panel-v2.md) | The breadcrumb's "all four presentations apply" becomes one |
| [`compact-view-v2.md`](compact-view-v2.md) | §2.2 is unchanged in substance and gains scope: the ink is the theme colour, not only the mark's. §12's `Mark colour` row is renamed |
| [`aggregate-ink-palette.md`](aggregate-ink-palette.md) | Nothing is void. The palette's reach widens from the mark to the mark and every badge, and §1's constraint — *the aggregate mark must never read as a dim version of a product mark* — is retired for want of a product mark to be dim against |
| [`figma-design.md`](figma-design.md) | §3.2's status-hue line (already void in code before this) and the two `product/*` tokens in `Color / macOS Window`; §4.1's `Colour bar` gutter rule and the two tests pinning it; §4.6's collapsed per-product badge inks (void since `compact-view-v2.md`, and now for a second reason); §8.4's label; §8.5's control |
| [`PRD.md`](PRD.md) | §12's Display list items 1 and 3 |
| [`CONTEXT.md`](../CONTEXT.md) | **Product** stops being "user-visible: matrix hue, row attribution…". **Disconnected** stops saying a matrix keeps its hue on the way down — there has been one mark since `compact-view-v2.md`, and now it has no product hue to keep |

## 10. Decisions this needs

| | Question | Where it stands |
| --- | --- | --- |
| 01 | Is the badge's lit text too loud on a real bar? | **Standing recommendation: ship it and look.** §4's ranking holds arithmetically, but the value is `L 0.922` where the product inks were `0.75` and `0.67`, and it is drawn at rest on every row of a mixed list. The fallback is a third value derived from the same pair rather than a new hue — the lit ink taken down to the caption's own lightness — which costs the palette nothing and the badge most of its tint. Worth judging on a list of eight rows, not on one |
| 02 | Does the badge ground need to change on a hovered or finished row? | **Standing recommendation: no.** `L 0.234` against the hover ground's `0.290` and a finished row's `0.260`, so the chip reads as an inset in every state, and every entry in the palette sits inside `0.003` of that figure — this is one check, not twelve. The old grounds `#101B26` / `#21120D` sat in the same relation and it was never raised |
| 03 | Does the footer's table need the badge on its outer row, or would the name alone do? | **Standing recommendation: the badge.** The outer row is the only place the footer names a product, and a name drawn one way in the list and another way ten points below it is the kind of inconsistency this decision exists to remove. It costs `2` pt per product group |
| 04 | Do the two `product/*` tokens go, or stay unused? | **Standing recommendation: go.** A token nothing binds to is a value the next person will bind something to. The Settings list needs no marker |
| 05 | Does Figma page `09` get redrawn to the decision? | **Open.** It currently draws the proposal that led here — grey badge, `Name and colour` kept as default — and the two differ in exactly the places the decision went further |

## 11. Implementation mapping

Nothing here is implemented.

| Symbol | Change |
| --- | --- |
| `NotchPalette.codex` / `.claudeCode` | **Retire.** With no per-product mark, no attribution ink and no counts column, the four values have no reader left |
| `NotchPalette.countsInk(for:)` | **Retire** with the columns it fed |
| `AgentCountsColumns` | **Retire.** `OverlayHeader` draws `CompactLeadingGroup` and stops |
| `PanelMetrics.expandedWidth(centerOcclusionWidth:workingAgentCount:)` | Loses its second parameter; `expandedLeadingSideWidth(workingAgentCount:)` becomes a constant `53.8` |
| `ProductAttributionStyle` | **Retire**, with `MonitorStore.productAttribution` and its defaults read. `showsProductAttribution` stays — it is what gates the badge |
| `MonitorStore.drawsColourBar` (`showsProductAttribution && productAttribution == .colourBar`) | **Retire** with the option |
| `MonitorStore.sessionRowGutter` / `sessionRowPadding` | Become constants at `6` + `6`. No form of the row gives up its gutter once the rail is gone ([`figma-design.md`](figma-design.md) §4.1) |
| `NotchPalette.aggregateInk(_:isConnected:)` | Unchanged. A second accessor returns the same pair for a badge, so the two can never drift |
| `AggregateInk` | Unchanged in values. Its documentation stops calling itself the mark's ink |
| `SettingsWindow` Display group | `Mark colour` → `Theme colour`, new caption; the `Distinguish products` row and its `ForEach(ProductAttributionStyle.allCases)` go |
| `MacOSWindowColor` | `product/codex` and `product/claude` retire |
| `theDisplayPreferencesReachTheSurfaceTheyDescribe` | Extend: the theme ink must reach the badge as well as the mark |
| `onlyTheTwoNamingStylesPutTheProductOnTheCaption` | **Retire** — there is one style and it puts a badge there |
| `theAttributionRailLandsOnThePanelsOwnMargin`, `theRowBlockOnlyGivesUpItsGutterWhileTheRailIsDrawn` | **Retire** with the rail they pin |
| `theExpandedWidthAnswersToWorkingAgentsAndNotToWords` | **Replace** with a test that the expanded width answers to neither: `520` at every cut-out and every agent count |

## 12. Verification

- [ ] No view reads a per-product colour. `NotchPalette` exposes no product ink and the two Figma tokens are gone.
- [ ] The band draws the mark and the totals at every agent count, and its leading side measures `53.8` at one, two, four and eight.
- [ ] The expanded panel is `520` at every cut-out this product meets, at every agent count, with no width term reading an agent count.
- [ ] A badge appears on a row's caption only while more than one product is connected, and disappears when the second disconnects — not when it merely runs out of threads.
- [ ] The badge's ground and text follow the `Theme colour` selection immediately, on every surface that draws one, and match the mark's two values exactly.
- [ ] Row height stays `80` with the badge, and the content block is `55`.
- [ ] The footer's spoken line is `47` and its opened table is `19W + 30P + 17`.
- [ ] With every colour rendered as flat grey, no figure, name or state on the collapsed bar or the expanded panel becomes ambiguous.
- [ ] Settings has `Theme colour` and no `Distinguish products`, and an install carrying a stored `Colour bar` opens on the badge without a migration step.
