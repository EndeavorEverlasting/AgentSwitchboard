# Skills Catalog

Skills are versioned procedural knowledge for agents. They describe **when** and **how** to perform work. Executable behavior belongs in deterministic code.

Canonical skills live under `.ai/skills/<skill-id>/SKILL.md`.

## Skill contract

Every canonical skill must define:

- skill ID, version, and status;
- trigger conditions;
- required inputs;
- bounded procedure;
- expected outputs and artifacts;
- deterministic validation;
- stop and escalation conditions;
- forbidden scope.

## Lifecycle

- `proposed` — design exists but is not approved for routine use;
- `experimental` — bounded use is allowed with explicit review;
- `canonical` — approved baseline workflow;
- `deprecated` — retained for migration only;
- `retired` — must not be selected.

## Resolution order

1. A task explicitly names a valid skill.
2. A new, repaired, relocated, or differently named Windows box whose repository path, username, company convention, hostname, redirected folders, or OneDrive layout is uncertain selects `machine-profile-bootstrap` before path selection or workstation setup.
3. Multi-agent, multi-session, multi-wave, or cross-PR coordination selects `public-plan-coordination`; use `plans/plan-registry.json` rather than leaving the coordination state only in chat or a PR description.
4. A literal request for a **Good Night, Have Fun prompt**, **GNHF prompt**, or to **compile a sprint for Good Night, Have Fun** selects `gnhf-prompt-compilation`. It must not fall through to generic sprint prose.
5. Interactive PowerShell selects `powershell-interactive-execution`. Continuation keywords must remain in the same submitted statement as the block they continue.
6. A copy-paste operator command that downloads, resolves, launches, installs, repairs, or crosses a child-process boundary selects `operator-command-delivery` before publication. The exact candidate command must be validated, not only a canned fixture.
7. Supplied application, validator, agent, or tool output that must be compared with a prompt kit selects `app-output-contextualization`. It reads provided output only and preserves execution-surface separation.
8. An operator-facing result that crosses shells, child processes, WSL, tmux, WezTerm, a TUI, a GUI, or another runtime boundary selects `end-to-end-runtime-validation`. Use `runtime-proof` for a bounded observation that does not require the complete operator path.
9. A Windows Profile request that distinguishes default open-or-activate from an explicit separate instance, or evidence of duplicate WezTerm windows, selects `windows-profile-launch-mode-validation` before any launcher implementation or runtime claim.
10. A request for a desktop shortcut or CMD installer that must create one genuinely separate tmux/WezTerm instance selects `tmux-new-instance-shortcut`. It preserves the one-launcher boundary and routes live acceptance through `end-to-end-runtime-validation`.
11. An Android/Termux repository bootstrap, mobile command-delivery recovery, multi-pane native-selection problem, or unclear tmux scrollback selects `android-termux-repo-bootstrap`; terminal selection/scrollback recovery additionally selects `android-termux-terminal-recovery` before asking the operator to fight native selection or provide screenshots.
12. `TRIGGERS.md` maps repository evidence to a skill.
13. The nearest nested `SKILLS.md` may specialize the catalog for a subtree.
14. When no skill fits, use `repo-intake` to collect evidence and propose a new bounded skill rather than improvising unlimited authority.

## Canonical skills

| Skill | Purpose | Primary triggers |
|---|---|---|
| [`repo-intake`](.ai/skills/repo-intake/SKILL.md) | Recover repository truth and select safe work | new repository, stale context, unknown branch state |
| [`bounded-sprint`](.ai/skills/bounded-sprint/SKILL.md) | Execute one scoped tracked change through commit/PR | explicit implementation request, ranked sprint selected |
| [`machine-profile-bootstrap`](.ai/skills/machine-profile-bootstrap/SKILL.md) | Detect Windows identity/path conventions and deterministically acquire AgentSwitchboard at an inferred or explicitly chosen root | new box, new username, missing repo, corporate hostname, redirected Desktop/Documents, OneDrive variation, explicit Dev directory |
| [`public-plan-coordination`](.ai/skills/public-plan-coordination/SKILL.md) | Coordinate public machine-readable work across agents, sessions, waves, branches, and PRs | plan request, sprint map, material ownership/dependency/handoff change |
| [`gnhf-prompt-compilation`](.ai/skills/gnhf-prompt-compilation/SKILL.md) | Compile one copy-ready bounded `gnhf` PowerShell launch command | “GNHF prompt,” “Good Night, Have Fun prompt,” compile sprint for GNHF |
| [`powershell-interactive-execution`](.ai/skills/powershell-interactive-execution/SKILL.md) | Produce directory-first PowerShell safe for interactive submission | PowerShell snippet, console steps, interactive command |
| [`operator-command-delivery`](.ai/skills/operator-command-delivery/SKILL.md) | Verify exact source identity, candidate command text, child executable launchability, parent-shell safety, and evidence routing before publishing operator commands | copy-paste command, HTTP 404, malformed PowerShell transport, blocked child launch, lost diagnostics |
| [`evidence-validation`](.ai/skills/evidence-validation/SKILL.md) | Build honest proof and repair validation gaps | failing checks, review findings, proof request |
| [`pr-integration`](.ai/skills/pr-integration/SKILL.md) | Reconcile stacked or parallel branches safely | merge request, stacked PRs, consumed upstream work |
| [`runtime-proof`](.ai/skills/runtime-proof/SKILL.md) | Move from static confidence to observed behavior | launcher, installer, harness, or live-runtime request |
| [`end-to-end-runtime-validation`](.ai/skills/end-to-end-runtime-validation/SKILL.md) | Prove the exact operator command across every runtime boundary through effective-state and user-experience readback | workstation repair, Windows-to-WSL chain, tmux/WezTerm configuration, cross-process installer or launcher, opaque child failure |
| [`windows-profile-launch-mode-validation`](.ai/skills/windows-profile-launch-mode-validation/SKILL.md) | Distinguish default workspace convergence, explicit named new instances, and accidental duplicate WezTerm windows | launch-mode request, separate-instance request, duplicate-window evidence, tmux-session identity ambiguity |
| [`tmux-new-instance-shortcut`](.ai/skills/tmux-new-instance-shortcut/SKILL.md) | Install and validate one owned desktop shortcut that allocates a unique tmux session and separate WezTerm process | desktop shortcut request, clickable CMD installer, one-click separate tmux instance |
| [`app-output-contextualization`](.ai/skills/app-output-contextualization/SKILL.md) | Parse supplied output, redact it, compare it with a prompt registry, and emit compact agent instructions | app output, logs, JSON, JSONL, validator output, minimal-token routing |
| [`android-termux-repo-bootstrap`](.ai/skills/android-termux-repo-bootstrap/SKILL.md) | Turn Termux into a bounded AgentSwitchboard repository workspace with clone, persistence, family-routing and validation gates | Android/Termux bootstrap, phone-local repo setup, mobile command-delivery recovery |
| [`android-termux-terminal-recovery`](.ai/skills/android-termux-terminal-recovery/SKILL.md) | Recover exact non-sensitive tmux pane evidence without depending on Android long-press selection or touch scrolling | selection spans panes, scrollback unclear, clipboard unreliable, prior terminal output required |

## Machine-profile distinction

A machine profile is a local observation and path-selection artifact, not a workstation success claim. It detects username, user profile, hostname, domain or Azure AD join signals, tenant name, known-folder redirection, OneDrive roots, tool availability, existing checkout candidates, and a recommended repository root. An explicit operator path always wins. Real machine-profile output stays under `%LOCALAPPDATA%` and is never committed.

`Bootstrap-AgentSwitchboard-In-Directory.cmd` is the reusable chosen-directory front door. It computes `<workspace>\AgentSwitchBoard-Live` and delegates to the canonical technician bootstrap; it does not duplicate Git, WSL, setup, or live-certification logic.

## Public plan distinction

A public plan is a repository-owned coordination contract. It records ownership, dependencies, collision boundaries, tasks, artifacts, validation, proof, and handoff. A branch or pull request is the delivery and review vehicle for tracked changes. A plan may predate, span, or outlive one PR, and a PR description must not be the only place agents can discover coordination state.

The canonical format and lifecycle live under `plans/` and are validated by `scripts/Test-PublicPlanContracts.ps1`.

## GNHF artifact distinction

A GNHF prompt is an executable launch command beginning with `gnhf`, including a verified agent, one Git execution mode, iteration and token caps, sleep prevention, a positive observable stop condition, and one quoted bounded objective block.

It is not:

- a sprint map;
- a multi-chat launch pack;
- a plan-only response;
- a generic repo-agent prompt;
- a description of how GNHF works.

The detailed canonical format and validation rules live in `.ai/skills/gnhf-prompt-compilation/SKILL.md`.

## App-output distinction

An app-output context packet is a minimized interpretation artifact, not the original log and not an executed prompt. It records the source hash, redacted excerpts, signals, same-surface prompt candidates, required variables, and proof ceiling. Ranking a prompt does not authorize running it.

## End-to-end distinction

`runtime-proof` can establish one observed behavior in an authorized environment. `end-to-end-runtime-validation` is required when the claim depends on the exact command an operator runs and a chain of shell, process, platform, terminal, TUI, GUI, provider, or application boundaries. The end-to-end skill requires per-stage stdout, stderr, exit identity, effective-state readback, user-visible observation, and idempotence or rollback proof when applicable. A parent exception containing only an exit code is not a complete end-to-end failure report.

## Android Termux distinction

`android-termux-repo-bootstrap` owns repository/workspace preparation and routes mobile terminal-evidence failures to `android-termux-terminal-recovery`. Android native selection and touch scrolling are never proof dependencies: exact tmux pane identity plus bounded `capture-pane` is preferred, and panes containing device codes or credentials are not persisted. The harness may install its own Python validation prerequisite, but it does not silently expand the separate Android runtime installer or promote hosted checks into phone runtime proof.

## Windows launch-mode distinction

The default Windows Profile operation remains `open-or-activate`: one logical workspace identity converges to one visible window. An explicit `new-instance` request is a separate named identity that requires exactly one additional top-level window, a distinct frontend process, and a unique tmux session. Two windows attached to the same tmux session are duplicate views of one workspace, not independent instances. Contract validation uses `windows-profile-launch-mode-validation`; workstation claims additionally use `end-to-end-runtime-validation`.

## tmux shortcut distinction

`tmux-new-instance-shortcut` owns the user-facing installer and explicit separate-instance shortcut. The CMD and `.lnk` are presentation surfaces only: they delegate to `tooling/profiles/windows/Invoke-AgentSwitchboardOpenOrActivate.ps1`. Automatic allocation reserves `dev` and selects `dev-1`, `dev-2`, and later unused positive suffixes. The shortcut installer proves installation and readback; a double-click result requires end-to-end runtime validation.

## PowerShell interactive distinction

Once an interactive `if` statement is submitted, a later standalone continuation keyword is invalid. Prefer guard clauses. When a compound statement is required, submit the whole statement together and keep each continuation keyword attached to the preceding closing brace.

## Authoring rules

- Skills must be small enough to select unambiguously.
- Skills may reference scripts and validators but must not paste their logic.
- Inputs and outputs should be machine-readable where practical.
- A skill must state what it cannot prove.
- A skill that can mutate live targets, deploy, merge, or access secrets requires an explicit escalation boundary.
- Changes to canonical skills require a version change and validation through `scripts/Test-AgentDocumentationContract.ps1`.
