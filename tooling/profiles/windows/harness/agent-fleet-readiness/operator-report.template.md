# Agent Fleet Readiness Operator Report

## Identity

- Repository:
- Branch/worktree:
- Harness head:
- Target repository:

## Fleet state

- `state.json`: present / missing
- installed `agent-switchboard.cmd`: present / missing
- classification: not-bootstrapped / partial-or-inconsistent / installed-unclassified / adapter-ready / blocked
- setup action taken: none / bootstrap / repair

## Readiness

- requested agent:
- observed adapter status:
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
- Error/exit:
- Missing surface or state:

## Validation

- `scripts/Test-AgentFleetReadinessHarnessCompleteness.ps1`:
- `python -m unittest tests.test_agent_fleet_readiness_harness`:
- `tooling/gnhf/Test-GnhfFleetContracts.ps1`:
- `git diff --check`:

## Proof ceiling

State only what current artifacts prove. Fleet installation does not prove agent readiness; adapter readiness does not prove provider response; tmux readiness does not prove fleet installation; a local sprint commit does not prove merge or deployment.

## Next action

One exact executable command/action that advances the first unproved gate:
