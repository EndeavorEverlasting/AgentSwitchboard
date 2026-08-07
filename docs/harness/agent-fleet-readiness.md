# Agent fleet readiness harness

## Why this harness exists

AgentSwitchboard has two separate operator floors:

1. terminal/runtime readiness such as PowerShell, WezTerm, WSL, and tmux;
2. installed agent-fleet readiness under `%LOCALAPPDATA%\AgentSwitchboard\GnhfFleet`.

A successful terminal/tmux proof does not install the reusable GNHF fleet. The installed post-setup launcher must not be recommended until its installed state has been observed.

The regression that created this harness was a post-setup `agent-switchboard.cmd -ListAgents` command being recommended before `%LOCALAPPDATA%\AgentSwitchboard\GnhfFleet\agent-switchboard.cmd` existed. The correct classification is `not-bootstrapped` or `partial-or-inconsistent`, not an agent failure.

## Canonical state gate

Inspect both files before any installed-launcher command:

- `%LOCALAPPDATA%\AgentSwitchboard\GnhfFleet\state.json`
- `%LOCALAPPDATA%\AgentSwitchboard\GnhfFleet\agent-switchboard.cmd`

Classification:

| state.json | launcher | classification | next action |
|---|---|---|---|
| missing | missing | `not-bootstrapped` | repository-owned setup/bootstrap |
| present | missing | `partial-or-inconsistent` | setup/repair; do not fabricate launcher |
| missing | present | `partial-or-inconsistent` | setup/repair; do not fabricate state |
| present | present | `installed-unclassified` | list current agent readiness |

Only after current readiness is observed should an adapter be selected for work.

## Repository-owned setup path

Source authority:

- `Setup-AgentSwitchboard.cmd`
- `tooling/gnhf/Setup-AgentSwitchboard.cmd`
- `tooling/gnhf/Setup-AgentSwitchboard.ps1`

The setup path is idempotent by contract: healthy components are reused and failures are recorded. Resolve its result from the artifact registry rather than treating process acceptance as completion.

Canonical setup evidence:

- `%LOCALAPPDATA%\AgentSwitchboard\setup-logs\<timestamp>\setup-summary.json`
- `%LOCALAPPDATA%\AgentSwitchboard\setup-logs\<timestamp>\setup-transcript.txt`

After successful setup, require both installed surfaces to exist before proceeding.

## Readiness path

Installed readiness surface:

`%LOCALAPPDATA%\AgentSwitchboard\GnhfFleet\agent-switchboard.cmd -ListAgents`

Repository orientation surface:

`AgentSwitchboard.cmd`

Readiness output can establish local adapter state. It does not establish provider authentication, exact model availability, quota, hosted response, repository completion, merge, or deployment.

## Picking up real work

Before launching a bounded sprint:

1. verify target repository identity and nearest rules;
2. verify the target checkout satisfies the GNHF clean-checkout requirement;
3. preserve unrelated dirty work instead of resetting/stashing automatically;
4. choose only an adapter reported by current readiness;
5. for non-AgentSwitchboard repositories, supply an explicit `-Prompt` or `-PromptPath`;
6. include owned scope, forbidden scope, validation, iteration/token limits, observable `StopWhen`, and push intent;
7. preserve launch-time provider verification where required;
8. resolve the generated worktree/branch, commit, validation, and route artifacts before completion claims.

Push is off by default. Local worktree/commit proof is not merge or deployment proof.

## Failure classification

- missing installed launcher before readiness -> bootstrap/readiness-state failure;
- missing state with launcher present -> partial/inconsistent installation;
- blocked adapter after current readiness -> adapter readiness failure;
- authentication/model/quota failure after adapter readiness -> provider-verification failure;
- dirty target checkout -> target-repository launch gate;
- failure after all prior gates pass and sprint starts -> sprint runtime failure.

Do not collapse these into a generic “agent failed.”

## Validation

Run focused harness checks:

```powershell
pwsh -NoLogo -NoProfile -File scripts/Test-AgentFleetReadinessHarnessCompleteness.ps1
python -m unittest tests.test_agent_fleet_readiness_harness
```

Then run the existing product contract without changing it:

```powershell
pwsh -NoLogo -NoProfile -File tooling/gnhf/Test-GnhfFleetContracts.ps1
```

Finally run diff hygiene:

```text
git --no-pager diff --check
```

## Proof ceiling

This harness proves tracked lifecycle routing, state-gate semantics, artifact ownership, and deterministic validation. It does not prove any particular workstation is bootstrapped or provider-authenticated until runtime artifacts from that workstation are observed.
