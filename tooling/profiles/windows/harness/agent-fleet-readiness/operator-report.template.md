# Agent Fleet Readiness Operator Report

## Identity

- Repository:
- Resolved repository root:
- Branch/worktree:
- Harness head:
- Active shell:
- Target repository:

## Fleet state

- `state.json`: present / missing
- installed `Start-AgentSwitchboard.ps1`: present / missing
- installed `agent-switchboard.cmd` compatibility shim: present / missing / access-denied
- classification: not-bootstrapped / partial-or-inconsistent / installed-unclassified / cmd-shim-blocked / core-ready-hermes-deferred / adapter-ready / blocked
- setup action taken: none / bootstrap / repair / core-autoconfig-with-Hermes-deferred
- Hermes: ready / TBD-deferred / blocked-but-nonblocking / not inspected

## Runtime boundary

- exact readiness command:
- PowerShell launcher exit:
- PowerShell launcher stdout/stderr:
- CMD shim attempted: yes / no
- CMD shim exit:
- CMD shim evidence:
- CMD shim recovery: not applicable / prove-readiness-through-powershell

## Readiness

- requested agent:
- observed adapter status:
- READY non-Hermes adapters:
- provider verification: proved / required / blocked / not applicable
- target repository cleanliness/isolation:

## Artifacts

- setup summary:
- setup transcript:
- startup readiness JSON:
- startup readiness Markdown:
- provider route proof:
- sprint/worktree/commit evidence:

## Working

- What is proved working:

## Broken / missing

- Exact failed boundary:
- repository path state:
- shell/command family:
- Error/exit:
- Missing authority surface or state:
- optional CMD shim state:
- Hermes follow-up if deferred: TBD / none

## Validation

- `scripts/Test-AgentFleetReadinessHarnessCompleteness.ps1`:
- `python -m unittest tests.test_agent_fleet_readiness_harness`:
- `tooling/gnhf/Test-GnhfFleetContracts.ps1`:
- `tooling/gnhf/Test-HermesSetupContracts.ps1`:
- `git diff --check`:

## Proof ceiling

State only what current artifacts prove. Fleet installation does not prove agent readiness; adapter readiness does not prove provider response; tmux readiness does not prove fleet installation; a blocked CMD compatibility shim does not prove the PowerShell fleet is blocked; Hermes deferred does not prove Hermes is repaired; a local sprint commit does not prove merge or deployment.

## Next action

One exact executable command/action that advances the first unproved gate. When the CMD shim is blocked but the PowerShell readiness authority exists, the next action is the PowerShell readiness workflow—not another setup run or another CMD-shim retry. A Hermes-only problem must not be chosen as the next gate while core readiness remains unproved and Hermes is not required.
