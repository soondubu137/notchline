# Product connection checks

Products reports user choice, installation, setup, presence and observation separately. Not installing, not setting up, switching off or not opening a product is normal. A warning requires a confirmed problem with requested observation, or a failed operation the user just requested.

## Facts and ownership

Each Provider returns `AgentSnapshot` with `ProductConnectionFacts`. `ProductConnectionMonitor` is a shared policy owned by that Provider, not another product orchestrator. The shared runtime and Codex's Provider retain their existing lifecycle ownership. `ProductConnectionPresentation` is the single pure presentation rule. Settings renders its status, notice severity and action; it never checks files, processes or sockets. These checks never supply Thread or Turn evidence.

| Fact | Evidence and meaning |
| --- | --- |
| Monitoring intent | A successful legacy setup is adopted once; subsequent explicit on/off choices are stored independently. Absence without a recorded choice is not evidence of earlier removal. |
| Installation | Discovered application or executable instances, their locations and available versions; not found, unknown and not checked are separate. Bounded discovery does not prove uninstallation. |
| Setup integrity | Actual registration: absent, complete, mismatched or unreadable. A saved preference cannot establish registration. No-setup products retain `notRequired`. |
| Activation | Verified, unverified, reload required when explicitly known, or not required. Silence cannot prove that Hooks are untrusted or an extension is disabled. |
| Presence | Open, closed or unknown, independent of the observation channel. Trae's running application remains open even if its companion is unavailable. |
| Observation health | Available, checking, connecting, reconnecting, unavailable, partial or not applicable. Notices carry information/warning severity and setup/observation/capability scope. |

`checkedAt` is provenance, excluded from visual equality: a repeated check with the same result must not invalidate the overlay. Provider observation epochs still reject retired work; connection discovery has its own invalidation generation and single-flight read. A read retired by a newer check is never returned: its caller joins the newer read, up to three times, before falling back to unknown. A read retired by disconnect stops.

## Display rules

| Situation | Main status | Notice/action |
| --- | --- | --- |
| User switched monitoring off | `Off` | No connection warning; a failed removal remains a separate operation error |
| No product found, no running instance | `App not found` | Neutral; retained setup is explained only when intent is enabled; Recheck |
| No setup and no enabled intent | `Not set up` | Neutral; switch enables setup |
| Enabled intent but configuration absent or mismatched | `Setup needs repair` | Warning and Repair |
| Setup cannot be read or understood | `Unable to check setup` | Warning only for enabled observation; Recheck, never an automatic rewrite |
| Setup is valid; desktop product closed | `Not open` | Neutral, no instruction to open or reload |
| Setup is valid; Claude Code has no running session | `Not running` | Neutral |
| Explicitly incompatible version | `Version unsupported` | Actual reason; Recheck, not a generic upgrade instruction |
| Presence or installation cannot be determined | `Unable to check` | Neutral explanation; unknown is neither absence nor a connection |
| Activation has not been verified | `Set up · not yet verified` | Neutral; Codex suggests reviewing new definitions under `/hooks` conditionally |
| A reload is explicitly known to be needed | `Window reload required` | Information, not a warning; never inferred from a missing connection |
| An actual connection attempt is in progress | `Connecting…` | Neutral |
| A previous connection is recovering | `Reconnecting…` | Neutral recovery interval |
| Confirmed observation failure persists | `Connection unavailable` | Warning with the boundary's cause and Recheck |
| Some discovered Trae windows fail while another is healthy | `Partially connected` | Warning restricted to discovered peers |
| Product open and observable, activation satisfied | `Connected` | Healthy, including with zero Threads |
| Supplementary capability fails | `Connected` | Information scoped to that capability; does not manufacture a whole-product failure |
| Explicit setup/removal fails | `Setup failed` / `Removal failed` | Per-product warning and Repair / Retry removal |

Priority is intentional: explicit Off and a missing product suppress obsolete connection failures; a proven setup defect can still be reported while an installed product is closed. Normal closure suppresses transport warnings and reload advice. Successful recovery clears the observation notice. `AgentSnapshot.isConnected` excludes unverified activation and pending reloads, so the summary cannot call a product Connected while Products is still waiting for activation. Declared unsupported modes and optional absent entry points are support boundaries, not connection faults.

## Intent and operations

The switch now represents the user's requested monitoring choice. This replaces the former rule that `repairRequired` automatically switched it off. Both externally deleted configuration and failed setup retain enabled intent and offer repair. Refresh never uses that intent to reinstall or rewrite the product's files. The two actions are independent: check reads evidence; repair executes the existing product-specific installer and verifies its result. Owned helper maintenance and passive listeners remain part of the existing monitoring runtime.

Explicit Off stops observation, removes the product's rows and requests removal of the settings owned by Notchline. A removal failure retains Off and reports a retryable operation error. It cannot silently resume monitoring just because the external settings remain. Each product's existing convergence task preserves last-flip-wins ordering. Successful direct setup/removal records intent too; an older operation cannot overwrite a newer requested choice.

The keys `productMonitoringIntent.<product>` are stored in Notchline's existing preferences. They contain `enabled` or `disabled`, not an installation assertion. No marker file is introduced. A legacy complete setup is adopted on its first trustworthy refresh. Missing configuration without prior intent remains `Not set up`.

## Discovery and scheduling

The monitor single-flights discovery and caches it for at most 30 seconds. Presence changes invalidate it immediately. Passive workspace launch/exit/wake notifications and application/setup directory edges also invalidate and wake the owning Provider. Opening Products, each appearance of onboarding's connection page and explicit Recheck invalidate discovery and Codex's registration cache before a fresh refresh. A recheck may land on a check already in flight, as onboarding's does at launch: the retired caller joins the fresh check. It used to return unknown, which a store test measured drawing `Unable to check` before `Connected`; onboarding briefly skipped its launch recheck to avoid that. Existing runtime events and heartbeat provide the remaining refresh opportunities. Rechecks do not launch products, run shell commands or install packages. Disabled products have no observation deadlines or active refreshes.

Desktop discovery prefers running applications, then Launch Services and the conventional `/Applications` and `~/Applications` locations, validating the bundle identifier from fresh Info.plist bytes rather than a cached Bundle dictionary. An unreadable information file is an unknown check, not uninstallation. Claude Code reuses its existing executable locator, including its explicit path override and Desktop's downloaded executable. Antigravity discovers Desktop and `agy` independently; either entry point is sufficient. Trae setup uses a single discovered application; ambiguous installation refuses the write and asks the user to open the intended application.

A confirmed observation failure has a ten-second recovery interval before the shared presentation raises a warning. It books one deadline for the end of that interval and consumes it; expired deadlines cannot keep the refresh loop awake. This interval changes only presentation, never Turn state. A normal product exit clears it. A Trae companion that has never supplied a peer or explicit failure remains unverified even after that interval: lack of activity is not a failed check.

Existing connection retries and lifecycle evidence expiry remain product-owned. No additional continuous UI animation, whole-machine process polling or Turn reconstruction is introduced.

Codex's Provider owns `CodexHookActivation`. Changes to `hooks.json` or `config.toml` wake a fresh public API check; those files supply change signals, not trust semantics. An unverified or failed check retries after five seconds while Codex is open and the App Server is available. Verified readings are cached until a file edge, explicit Recheck, setup change or disconnect. Reads are single-flight with a three-second timeout; edits and invalidations retire a read, whose caller joins the newer read rather than reporting it unverified, and `stop` on disconnect ends it as unverified without reading again. No trust receipt or Turn is persisted by this check.

## Boundaries

- Application discovery is bounded. `App not found` is deliberately weaker than `Not installed`.
- Trae's registration reader covers the existing local default extension manifest. It checks both the manifest entry and the actual companion package's identity/version. Missing files, invalid JSON, unreadable files and version mismatch have different results. Other profiles, remote extension hosts and extensions disabled through unobserved private state are not guessed.
- Partial Trae coverage reports only peers discovered by the transport; it cannot promise an inventory of every native window. An undiscovered window is not invented as a failure.
- Codex activation uses the public `hooks/list` response, verified against CLI `0.154.0-alpha.6.2`. Every managed definition must match its source path, event, command, matcher and timeout, and be enabled and trusted. All definitions trusted means activation is verified without a Turn; Connected still requires presence and a working App Server. Missing, disabled, modified, malformed or failed readings remain unverified. Only an unsupported method retains the legacy delivery-based fallback. No private trust keys or hashes are read.
- Setup history is limited to user intent. Historical connection times and per-definition activation receipts are not fabricated where the underlying source cannot establish them. The public activation check creates no files; disconnect cancels its pending read and pauses its file watchers.

## Verification

`CodexHookActivationTests` covers trust without a Turn, atomic configuration replacement, off/on revalidation, exact definition matching, missing and malformed responses, unsupported servers, caching, late reads joining the newer read, no re-read after stop, and retry suspension after connection failure. `ProductConnectionTests` covers normal choices, absent versus unreadable setup, closure versus reload advice, missing products versus repair, presence requirements, silence, recovery, capability notice scope, discovery invalidation, retired checks joining the newer one without the store ever drawing `Unable to check`, no re-check after disconnect, onboarding's recheck on each appearance, persisted intent and timestamp equality. Existing setup, convergence, transport and product conformance tests exercise actual boundary behaviour. `TraeConformanceTests` verifies extension manifest and package absence/corruption/mismatch. The full `NotchlineTests` suite remains the commit gate.

### Release measurement

Measured on 2026-09-13 with Release optimisation (`-O`, single-file compilation, testability enabled for the isolated probe). Cumulative process CPU time (`getrusage`, user plus system) measured the burst itself; these are not `ps %cpu` estimates and do not represent the complete application's steady-state cost. Operating-system caches were warm. Four fresh real product discovery adapters were checked, followed by 1,000 cached four-product checks.

```text
Initial discovery for four fresh adapters: 5.37 ms CPU
1,000 cached four-product checks: 102.56 ms CPU
Mean cached four-product check: 0.103 ms CPU
```

The Products layout was rendered from the actual SwiftUI views in light and dark appearances. Normal closure has no warning line; an enabled product whose setup needs repair retains its switch. The temporary CPU probe and rendered images are removed after verification; the layout and state tests remain.

Original connection-check validation: 960 of 960 unit tests passed, with no skipped tests. The final application source also passed a Release build. Local Markdown links and diff whitespace checks passed.

Hook activation validation (2026-09-13): the full unit suite passed with 968 successful test executions and no failures. In an isolated `CODEX_HOME`, the installed CLI `0.154.0-alpha.6.2` returned `untrusted` before the trust fixture was saved and `trusted` afterwards through the same App Server, without creating a Thread or Turn. A separate read-only check of the current installation returned all seven Notchline definitions enabled and trusted. No production private trust-state parser was added. The final source passed a Release build; local Markdown links and diff whitespace checks passed.
