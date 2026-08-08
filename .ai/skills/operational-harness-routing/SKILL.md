---
id: operational-harness-routing
version: 1.2.0
status: canonical
---

# Operational Harness Routing

## Trigger

Use when an agent or operator enters AgentSwitchboard, must recover repository/harness context, choose the correct workflow or validator, prepare a commit or push gate, diagnose a failed gate, verify an isolated PR worktree, integrate validated work, or hand work to another chat/agent.

Do not use this skill to replace a specialized environment, runtime, profile, Pi, GNHF, public-plan, or product-domain skill.

## Inputs

- task request;
- repository identity or candidate path;
- current branch, HEAD, dirty state, and PR relationship when available;
- logical branch label and exact expected HEAD when operating from a detached verification worktree;
- changed paths or planned owned paths;
- relevant `AGENTS.md`, `HARNESS.md`, operational registries, domain registries, and validator evidence;
- commands actually executed successfully when the handoff must carry validation receipts;
- merge authority already granted by the current task or an explicit standing repository-owner directive, including the authority source.

## Procedure

1. Resolve repository identity safely. Do not assume the current shell directory is a checkout.
2. Read `AGENTS.md`, then `HARNESS.md`, `tooling/harness/operational/manifest.json`, and `tooling/harness/operational/codebase-map.json`.
3. Run or inspect `tooling/harness/operational/Get-OperationalHarnessStatus.py`.
4. Load `workflow-registry.json` and choose one primary lifecycle workflow.
5. If the task matches a specialized routing condition, load that named skill and domain workflow before mutation.
6. Declare branch ownership, owned and forbidden scope, artifact expectations, validation order, proof ceiling, PR/base relationship, and whether merge authority is already granted.
7. Implement only the selected owned layer.
8. Before commit, run owning validators first, then required foundation/domain checks and `git diff --check`.
9. Before push, use the opt-in `Invoke-OperationalHarnessPrePush.ps1`; pass the exact `-BaseRef` rather than inferring a push range from an upstream.
10. If any check fails, keep the first failure evidence and route through `failure-recovery`; never weaken the gate to manufacture a pass.
11. For detached exact-head verification, pass `--branch-label`, `--expected-head`, and, when available, `--branch-ref` plus `--pr-number` to the reporter.
12. Never infer completed validation from file presence. Supply each already-successful command explicitly with `--validated-command`; use `--gate-complete` only after those commands have actually succeeded.
13. Preserve merge authority instead of asking for it twice. If the current task or a standing repository-owner directive already authorizes merging validated in-scope work, pass `--merge-authorized --merge-authority-source <source>` to the reporter. Do not manufacture authority when it was not granted.
14. After a complete PR gate, inspect the reporter's next action. If its owner is `current harness agent`, execute that exact-head-pinned merge in the same work cycle after confirming checks/reviews and mergeability still hold. Opening a PR or emitting the merge command is not completion when authorized safe integration remains.
15. Use handoff only when work truly transfers or a real blocker remains. Do not convert an already-authorized merge into an owner handoff.

## Outputs

- selected lifecycle workflow and specialized skill if applicable;
- bounded sprint declaration;
- validator selection;
- generated operational status/report/validation-ledger/handoff artifacts outside the repository;
- preserved logical branch plus exact HEAD for detached verification worktrees;
- recorded merge-authority source when supplied;
- exact executable next action with owner, dependency, and expected proof;
- merge proof when validated in-scope integration is already authorized and succeeds.

## Deterministic validation

Run:

```text
python3 tests/test_operational_harness.py
python3 tests/test_operational_merge_authority.py
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
- destructive cleanup, reset, history rewrite, force-push, deployment, provider invocation, or live-target mutation without separate authority;
- merge when neither the current task nor an explicit standing repository-owner directive grants it;
- promoting repository, CI, package, process, SSH, tmux-name, caller-attested command receipt, authority receipt, or command-ack evidence into runtime proof.

## Stop and escalate

Stop the dependent action when repository identity, branch ownership, specialized owner, environment topology, validator authority, credentials, protected runtime, required review, merge authority, or live-target authority is genuinely unresolved. Do **not** stop for merge authorization when the current task or a standing repository-owner directive has already granted it. Produce a handoff only for the remaining real blocker and include the executable gate that advances it.
