# Skills Catalog

Skills are versioned procedural knowledge for agents. They describe **when** and **how** to perform work. Executable behavior belongs in deterministic code.

Canonical and experimental skills live under `.ai/skills/<skill-id>/SKILL.md`.

## Skill contract

Every skill must define skill ID/version/status, trigger conditions, required inputs, bounded procedure, outputs/artifacts, deterministic validation, stop/escalation conditions, forbidden scope, and an honest proof ceiling where applicable.

## Lifecycle

- `proposed` — design exists but is not approved for routine use.
- `experimental` — bounded use is allowed with explicit evidence/review; live claims require their own proof.
- `canonical` — approved baseline workflow.
- `deprecated` — retained for migration only.
- `retired` — must not be selected.

## Resolution order

1. A task explicitly names a valid skill.
2. A new, repaired, relocated, or differently named Windows box whose repository path, username, company convention, hostname, redirected folders, or OneDrive layout is uncertain selects `machine-profile-bootstrap` before path selection or workstation setup.
3. A destination that is too large/ambiguous for one bounded session **and whose route still contains unresolved decision fog** selects `wayfinder`. Wayfinder charts tracker-backed decision tickets; it does not pre-slice destination implementation.
4. Multi-agent, multi-session, multi-wave, or cross-PR work whose route is already known selects `public-plan-coordination`; use `plans/plan-registry.json` rather than leaving coordination only in chat or a PR description. A public plan may mirror a Wayfinder map, but it is not the decision-ticket store.
5. A literal request for a **Good Night, Have Fun prompt**, **GNHF prompt**, or to **compile a sprint for Good Night, Have Fun** selects `gnhf-prompt-compilation`. It must not fall through to generic sprint prose.
6. Interactive PowerShell selects `powershell-interactive-execution`. Continuation keywords must remain in the same submitted statement as the block they continue.
7. A copy-paste operator command that downloads, resolves, launches, installs, repairs, or crosses a child-process boundary selects `operator-command-delivery` before publication. The exact candidate command must be validated, not only a canned fixture.
8. Supplied application, validator, agent, or tool output that must be compared with a prompt kit selects `app-output-contextualization`. It reads provided output only and preserves execution-surface separation.
9. An operator-facing result that crosses shells, child processes, WSL, tmux, WezTerm, a TUI, a GUI, or another runtime boundary selects `end-to-end-runtime-validation`. Use `runtime-proof` for a bounded observation that does not require the complete operator path.
10. A Windows Profile request that distinguishes default open-or-activate from an explicit separate instance, or evidence of duplicate WezTerm windows, selects `windows-profile-launch-mode-validation` before implementation/runtime claims.
11. A request for a desktop shortcut or CMD installer that must create one genuinely separate tmux/WezTerm instance selects `tmux-new-instance-shortcut`.
12. An Android/Termux repository bootstrap, mobile command-delivery recovery, multi-pane native-selection problem, or unclear tmux scrollback selects `android-termux-repo-bootstrap`; selection/scrollback recovery additionally selects `android-termux-terminal-recovery`.
13. `TRIGGERS.md` and the operational workflow registry map repository evidence to a skill.
14. The nearest nested `SKILLS.md` may specialize the catalog for a subtree.
15. When no skill fits, use `repo-intake` to collect evidence and propose a bounded skill rather than improvising unlimited authority.

## Wayfinder ticket routing

A Wayfinder ticket's type is a workflow gate, not a suggestion:

| Ticket type | Interaction | Required ASB skill(s) | Resolution floor |
|---|---|---|---|
| `research` | AFK | `research` | primary-source research artifact + tracker resolution |
| `prototype` | HITL | `prototype` | runnable throwaway artifact + observed human verdict |
| `grilling` | HITL | `grilling`, `domain-modeling` | live human answers + domain updates where needed |
| `task` | AFK or HITL | Wayfinder task gate | prerequisite action actually completed |

When the map is clear, `to-spec` may synthesize a **temporary** implementation specification. `to-tickets` may then produce tracer-bullet **implementation** tickets. Decision tickets and implementation tickets are different artifact classes and must not be conflated.

## Skills

| Skill | Status | Purpose | Primary triggers |
|---|---|---|---|
| [`repo-intake`](.ai/skills/repo-intake/SKILL.md) | canonical | Recover repository truth and select safe work | new repository, stale context, unknown branch state |
| [`bounded-sprint`](.ai/skills/bounded-sprint/SKILL.md) | canonical | Execute one scoped tracked change through commit/PR | explicit implementation request, ranked sprint selected |
| [`wayfinder`](.ai/skills/wayfinder/SKILL.md) | experimental | Chart and resolve a tracker-backed map of typed decision tickets until a multi-session route is clear | large ambiguous destination, fog of war, explicit `/wayfinder` |
| [`research`](.ai/skills/research/SKILL.md) | canonical | Resolve external facts from primary sources into one evidence artifact | Wayfinder research ticket, docs/API fact investigation |
| [`prototype`](.ai/skills/prototype/SKILL.md) | experimental | Build a cheap throwaway artifact to raise decision fidelity and obtain a human verdict | Wayfinder prototype ticket, unclear look/behavior |
| [`grilling`](.ai/skills/grilling/SKILL.md) | canonical | Work a dependency-aware human decision frontier without self-answering | Wayfinder grilling ticket, decision stress test |
| [`domain-modeling`](.ai/skills/domain-modeling/SKILL.md) | canonical | Sharpen ubiquitous language and durable trade-offs as decisions settle | Wayfinder grilling, domain terminology/ADR change |
| [`to-spec`](.ai/skills/to-spec/SKILL.md) | experimental | Synthesize already-settled decisions into a temporary implementation spec | clear Wayfinder map, implementation-ready synthesis |
| [`to-tickets`](.ai/skills/to-tickets/SKILL.md) | experimental | Decompose a clear spec/route into tracer-bullet implementation tickets | post-spec implementation planning |
| [`machine-profile-bootstrap`](.ai/skills/machine-profile-bootstrap/SKILL.md) | canonical | Detect Windows identity/path conventions and deterministically acquire AgentSwitchboard | new box, new username, missing repo, redirected folders |
| [`public-plan-coordination`](.ai/skills/public-plan-coordination/SKILL.md) | canonical | Coordinate repository work across sessions/branches/PRs without replacing tracker decision authority | plan request, sprint map, ownership/dependency/handoff change |
| [`gnhf-prompt-compilation`](.ai/skills/gnhf-prompt-compilation/SKILL.md) | canonical | Compile one copy-ready bounded `gnhf` launch command | GNHF prompt request |
| [`powershell-interactive-execution`](.ai/skills/powershell-interactive-execution/SKILL.md) | canonical | Produce directory-first PowerShell safe for interactive submission | PowerShell snippet, console steps |
| [`operator-command-delivery`](.ai/skills/operator-command-delivery/SKILL.md) | canonical | Verify source identity, candidate command, child launchability, parent-shell safety, and evidence routing | copy-paste command, 404, malformed transport, lost diagnostics |
| [`evidence-validation`](.ai/skills/evidence-validation/SKILL.md) | canonical | Build honest proof and repair validation gaps | failing checks, review findings, proof request |
| [`pr-integration`](.ai/skills/pr-integration/SKILL.md) | canonical | Reconcile stacked or parallel branches safely | merge request, stacked PRs, consumed upstream work |
| [`runtime-proof`](.ai/skills/runtime-proof/SKILL.md) | canonical | Move from static confidence to observed behavior | launcher, installer, harness, live-runtime request |
| [`end-to-end-runtime-validation`](.ai/skills/end-to-end-runtime-validation/SKILL.md) | canonical | Prove the exact operator command across every runtime boundary | workstation repair, WSL/tmux/WezTerm chain, opaque child failure |
| [`windows-profile-launch-mode-validation`](.ai/skills/windows-profile-launch-mode-validation/SKILL.md) | canonical | Distinguish default convergence, explicit instances, and accidental duplicate windows | launch-mode/duplicate-window request |
| [`tmux-new-instance-shortcut`](.ai/skills/tmux-new-instance-shortcut/SKILL.md) | canonical | Install/validate one owned shortcut allocating a unique tmux session and WezTerm process | desktop shortcut, separate tmux instance |
| [`app-output-contextualization`](.ai/skills/app-output-contextualization/SKILL.md) | canonical | Parse supplied output, redact it, rank same-surface prompt candidates, emit compact instructions | logs/JSON/validator output, minimal-token routing |
| [`android-termux-repo-bootstrap`](.ai/skills/android-termux-repo-bootstrap/SKILL.md) | canonical | Turn Termux into a bounded AgentSwitchboard repository workspace | Android/Termux bootstrap, phone-local repo setup |
| [`android-termux-terminal-recovery`](.ai/skills/android-termux-terminal-recovery/SKILL.md) | canonical | Recover exact non-sensitive tmux pane evidence without Android selection dependence | selection spans panes, scrollback unclear, prior output needed |

## Wayfinder distinction

Wayfinder exists specifically to reduce dependence on model memory/judgment across long ambiguous efforts.

- **Map**: low-resolution tracker index. It contains Destination, Notes, linked gists of closed decisions, Not yet specified, and Out of scope.
- **Decision ticket**: primary source for one precise question and its resolution. Claim before work. Native blockers define eligibility. Prototype/grilling cannot close without actual human input.
- **Public plan**: repository coordination mirror. It may point at the map and mirror fog/spec state; it must not copy decision bodies into `tasks[]`.
- **Specification**: temporary synthesis after all required decisions/fog clear. It links decision sources and is retired after implementation acceptance.
- **Implementation ticket / bounded sprint**: execution work after the route is clear. These are tracer-bullet build slices, not Wayfinder decisions.

The exact donor sources used to define these semantics are pinned and retained under `third_party/mattpocock-skills/<commit>/` as non-executable provenance. ASB's `.ai/skills/*` and `tooling/harness/wayfinder/*` are the executable/validated consumer authority.

## Public plan distinction

A public plan is a repository-owned coordination contract. It records ownership, dependencies, collision boundaries, tasks, artifacts, validation, proof, and handoff. A branch or pull request is the delivery/review vehicle. A plan may predate, span, or outlive one PR, and PR prose must not be the only durable coordination record.

## GNHF artifact distinction

A GNHF prompt is an executable launch command beginning with `gnhf`, including a verified agent, one Git execution mode, iteration/token caps, sleep prevention, a positive observable stop condition, and one bounded objective block. It is not a sprint map, plan-only response, ordinary repo-agent prompt, or description of GNHF.

## App-output distinction

An app-output context packet is a minimized interpretation artifact, not the original log and not an executed prompt. Ranking a prompt does not authorize running it.

## End-to-end distinction

`runtime-proof` may establish one observed behavior. `end-to-end-runtime-validation` is required when the claim depends on the exact operator command across shells/processes/platforms/terminal/TUI/GUI/provider/application boundaries. A parent exit code alone is not end-to-end proof.

## Android Termux distinction

`android-termux-repo-bootstrap` owns repository/workspace preparation and routes terminal-evidence failures to `android-termux-terminal-recovery`. Android native selection/touch scrolling are never proof dependencies; exact tmux pane identity plus bounded capture is preferred, and credential/device-code panes are not persisted.

## Windows launch-mode distinction

Default Windows Profile operation is `open-or-activate`: one logical workspace identity converges to one visible window. Explicit `new-instance` requires a distinct identity, frontend process, and tmux session. Two windows on one tmux session are duplicate views, not independent instances.

## PowerShell interactive distinction

Once an interactive compound statement is submitted, a later standalone continuation keyword is invalid. Prefer guard clauses; when compound syntax is required, submit the complete syntax unit together.

## Authoring rules

- Skills must be small enough to select unambiguously.
- Skills may reference scripts/validators but must not paste deterministic implementation logic.
- Inputs/outputs should be machine-readable where practical.
- A skill must state what it cannot prove.
- HITL skills must identify evidence that the human actually participated; model recommendations cannot satisfy that gate.
- A skill that can mutate live targets, deploy, merge, access secrets, or alter tracker state requires the appropriate explicit authority/evidence boundary.
- Changes to canonical skills require a version change and validation through `scripts/Test-AgentDocumentationContract.ps1`.
