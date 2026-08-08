---
id: operational-harness-routing
version: 1.1.0
status: canonical
---

# Operational Harness Routing

## Trigger

Use when an agent or operator enters AgentSwitchboard, must recover repository/harness context, choose the correct workflow or validator, prepare a commit or push gate, diagnose a failed gate, verify an isolated PR worktree, or hand work to another chat/agent.

Do not use this skill to replace a specialized environment, runtime, profile, Pi, GNHF, public-plan, or product-domain skill.

## Inputs

- task request;
- repository identity or candidate path;
- current branch, HEAD, dirty state, and PR relationship when available;
- logical branch label and exact expected HEAD when operating from a detached verification worktree;
- changed paths or planned owned paths;
- relevant `AGENTS.md`, `HARNESS.md`, operational registries, domain registries, and validator evidence;
- commands actually executed successfully when the handoff must carry validation receipts.

## Procedure

1. Resolve repository identity safely. Do not assume the current shell directory is a checkout.
2. Read `AGENTS.md`, then `HARNESS.md`, `tooling/harness/operational/manifest.json`, and `tooling/harness/operational/codebase-map.json`.
3. Run or inspect `tooling/harness/operational/Get-OperationalHarnessStatus.py`.
4. Load `workflow-registry.json` and choose one primary lifecycle workflow.
5. If the task matches a specialized routing condition, load that named skill and domain workflow before mutation.
6. Declare branch ownership, owned and forbidden scope, artifact expectations, validation order, proof ceiling, and PR/base relationship.
7. Implement only the selected owned layer.
8. Before commit, run owning validators first, then required foundation/domain checks and `git diff --check`.
9. Before push, use the opt-in `Invoke-OperationalHarnessPrePush.ps1`; if the branch has no upstream, pass the exact stacked `-BaseRef` rather than assuming `main`.
10. If any check fails, keep the first failure evidence and route through `failure-recovery`; never weaken the gate to manufacture a pass.
11. For detached exact-head verification, pass `--branch-label`, `--expected-head`, and, when available, `--branch-ref` plus `--pr-number` to the reporter.
12. Never infer completed validation from file presence. Supply each already-successful command explicitly with `--validated-command`; use `--gate-complete` only after those commands have actually succeeded.
13. Generate/refresh the operational report and handoff before transferring work. The next action must name its owner, dependency, executable command, and proof. A generated merge command remains blocked on explicit owner merge authorization/review and must pin the exact head.

## Outputs

- selected lifecycle workflow and specialized skill if applicable;
- bounded sprint declaration;
- validator selection;
- generated operational status/report/validation-ledger/handoff artifacts outside the repository;
- preserved logical branch plus exact HEAD for detached verification worktrees;
- exact executable next action with owner, dependency, and expected proof.

## Deterministic validation

Run:

```text
python3 tests/test_operational_harness.py
pwsh -NoLogo -NoProfile -File scripts/Test-OperationalHarness.ps1
git diff --check
```

Optional pre-push gate:

```text
pwsh -NoLogo -NoProfile -File tooling/harness/operational/hooks/Invoke-OperationalHarnessPrePush.ps1 -BaseRef <exact-base-ref>
```

Then run the owning domain validators selected from `tooling/harness/operational/validator-registry.json`.

## Forbidden scope

- editing `AGENTS.md` or governance policy without a separate governance lane;
- product code changes justified only by harness convenience;
- implicit Git-hook installation;
- secrets or private machine data in tracked artifacts;
- destructive cleanup, reset, history rewrite, force-push, merge, deployment, provider invocation, or live-target mutation without separate authority;
- promoting repository, CI, package, process, SSH, tmux-name, caller-attested command receipt, or command-ack evidence into runtime proof.

## Stop and escalate

Stop the dependent action when repository identity, branch ownership, specialized owner, environment topology, validator authority, credentials, protected runtime, review/merge authorization, or live-target authority is unresolved. Produce a handoff with the exact blocker and executable gate that advances it. Do not replace a blocked gate with a status-only command or a validator that has already passed.
