# Agent fleet readiness harness

## Why this harness exists

AgentSwitchboard has two separate operator floors:

1. terminal/runtime readiness such as PowerShell, WezTerm, WSL, and tmux;
2. installed agent-fleet readiness under `%LOCALAPPDATA%\AgentSwitchboard\GnhfFleet`.

A successful terminal/tmux proof does not install the reusable GNHF fleet. The installed post-setup launcher must not be recommended until its installed state has been observed.

The original regression was a post-setup `agent-switchboard.cmd -ListAgents` command being recommended before `%LOCALAPPDATA%\AgentSwitchboard\GnhfFleet\agent-switchboard.cmd` existed. A later operator failure exposed two more recurring traps: a stale hard-coded repository path and a PowerShell-only `irm ... | iex` installer command pasted into CMD. Neither is an agent/provider failure.

Hermes is also explicitly **optional for core autoconfig**. The repository-owned setup already supports `-SkipHermesInstall` and records Hermes unavailable/skipped/blocked while continuing the core fleet. The harness therefore routes Hermes trouble to `TBD/deferred`, not to a blocking setup loop.

## Canonical state gate

Inspect both files before any installed-launcher command:

- `%LOCALAPPDATA%\AgentSwitchboard\GnhfFleet\state.json`
- `%LOCALAPPDATA%\AgentSwitchboard\GnhfFleet\agent-switchboard.cmd`

| state.json | launcher | classification | next action |
|---|---|---|---|
| missing | missing | `not-bootstrapped` | repository-owned setup/bootstrap |
| present | missing | `partial-or-inconsistent` | setup/repair; do not fabricate launcher |
| missing | present | `partial-or-inconsistent` | setup/repair; do not fabricate state |
| present | present | `installed-unclassified` | list current agent readiness |

When both core surfaces exist and Hermes alone is unavailable/skipped/blocked, classify the outcome as `core-ready-hermes-deferred`: Hermes is `TBD`, and non-Hermes READY adapters may continue.

## Repository and shell gates

Before Git or setup:

- resolve the actual repository root from the current machine; do not trust a remembered user-profile path;
- require `.git` and `tooling/gnhf/Setup-AgentSwitchboard.ps1` under that root;
- run the core setup command from PowerShell 7;
- do not paste PowerShell aliases such as `irm` into CMD. A CMD message like `'irm' is not recognized` is a shell-command mismatch, not proof that Hermes itself failed.

## Non-blocking core autoconfig

When Hermes is unavailable, slow, hanging, or simply not the current priority, use the repository-owned fast path:

```powershell
pwsh -NoLogo -NoProfile -File tooling/gnhf/Setup-AgentSwitchboard.ps1 -InstallOpenCodeAndCopilot -SkipHermesInstall
```

This is not a product bypass invented by the harness. `-SkipHermesInstall` is an existing setup parameter. The setup summary/transcript remain canonical evidence. A `partial` setup status is acceptable only when the core fleet succeeded and Hermes is the deferred dependency.

After setup, require both installed surfaces, then run:

```powershell
& "$env:LOCALAPPDATA\AgentSwitchboard\GnhfFleet\agent-switchboard.cmd" -ListAgents
```

Do not retry or manually install Hermes before proving core readiness. Repair Hermes later in its own bounded lane if it becomes useful.

## Canonical setup evidence

- `%LOCALAPPDATA%\AgentSwitchboard\setup-logs\<timestamp>\setup-summary.json`
- `%LOCALAPPDATA%\AgentSwitchboard\setup-logs\<timestamp>\setup-transcript.txt`
- `%LOCALAPPDATA%\AgentSwitchboard\GnhfFleet\reports\startup\agent-startup-readiness-<timestamp>.json`
- `%LOCALAPPDATA%\AgentSwitchboard\GnhfFleet\reports\startup\agent-startup-readiness-<timestamp>.md`

Generated evidence is local and untracked.

## Failure classification

- stale/missing selected repo root -> `repository-path-invalid`;
- PowerShell-only command submitted to CMD -> `shell-command-mismatch`;
- Hermes unavailable/hanging while core setup is desired -> `hermes-deferred`; use `-SkipHermesInstall`, record `TBD`, continue core proof;
- missing installed launcher before readiness -> bootstrap/readiness-state failure;
- missing state with launcher present -> partial/inconsistent installation;
- blocked non-Hermes adapter after current readiness -> adapter readiness failure;
- authentication/model/quota failure after adapter readiness -> provider-verification failure;
- dirty target checkout -> target-repository launch gate;
- failure after all prior gates pass and sprint starts -> sprint runtime failure.

Do not collapse these into a generic “agent failed.”

## Picking up real work

Before launching a bounded sprint:

1. verify target repository identity and nearest rules;
2. preserve unrelated dirty work through isolation rather than destructive cleanup;
3. choose only an adapter reported by current readiness;
4. Hermes may remain `TBD/deferred` if another READY adapter can own the requested lane;
5. for non-AgentSwitchboard repositories, supply explicit `-Prompt` or `-PromptPath`;
6. include owned scope, forbidden scope, validation, iteration/token limits, observable `StopWhen`, and push intent;
7. preserve launch-time provider verification where required;
8. resolve generated worktree/branch, commit, validation, and route artifacts before completion claims.

Push is off by default. Local worktree/commit proof is not merge or deployment proof.

## Validation

```powershell
pwsh -NoLogo -NoProfile -File scripts/Test-AgentFleetReadinessHarnessCompleteness.ps1
python -m unittest tests.test_agent_fleet_readiness_harness
pwsh -NoLogo -NoProfile -File tooling/gnhf/Test-GnhfFleetContracts.ps1
pwsh -NoLogo -NoProfile -File tooling/gnhf/Test-HermesSetupContracts.ps1
git --no-pager diff --check
```

## Proof ceiling

This harness proves tracked lifecycle routing, state-gate semantics, repository/shell boundary classification, Hermes deferral policy, artifact ownership, and deterministic validation. It does not prove any particular workstation is bootstrapped, Hermes-ready, provider-authenticated, or capable of completing hosted work until runtime artifacts from that workstation are observed.
