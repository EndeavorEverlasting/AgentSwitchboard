# Repository work ledger contract

Contract ID: `agentswitchboard.repository-work-ledger.v1`
Version: `1.0.0`
Canonical owner: `EndeavorEverlasting/AgentSwitchboard`

## Purpose

A repository work ledger is the durable coordination surface for unfinished work across users, agents, chats, machines, and branches. It implements the continuous-execution and transport-independent coordination principles already owned by `AGENTS.md`; it does not replace repository law, source code, tests, runbooks, issues, pull requests, CI, provider state, or runtime evidence.

This contract was factored from the AxTask shared queue implementation at donor commit `9351c952b057ae4520b1ea0d388e1d8908f4c093`, especially `.ai/WORK_QUEUE.md`, `scripts/ai-harness/validate-work-queue.mjs`, and `server/ai-harness/work-queue-contract.test.ts`. AxTask remains authoritative for AxTask domain behavior and `AXQ-*` task contents. No AxTask-specific recovery, deployment, database, or product logic is portable authority here.

## Ownership boundary

- AgentSwitchboard owns this portable contract, policy vocabulary, compatibility rules, and family-level proof semantics.
- Each consumer repository owns its ledger instance, task identifiers, domain references, acceptance gates, local validator implementation, CI/hook integration, and runtime truth.
- A consumer may strengthen this contract but may not silently weaken required fields, terminal-state proof, collision handling, or executable-next-action rules while claiming v1 compatibility.
- A contribution/adoption manifest is evidence of intended compatibility only. It is not runtime proof and does not make AgentSwitchboard authoritative for consumer product behavior.

## Required intake loop

1. Read repository governance first.
2. Read the repository ledger before substantial mutation.
3. Reconcile the candidate task against current default-branch state, open PRs, CI, referenced source, and runtime/provider evidence when applicable.
4. Claim the item before substantial mutation and re-read the latest ledger immediately before editing it.
5. Execute through every safe, authorized continuation boundary available to the current agent.
6. Update the ledger before stopping with strongest proof, exact gate, and first executable next action.

## Status vocabulary

Consumers must support these statuses with these semantics:

- `READY`: unclaimed and executable now.
- `CLAIMED`: one identified writer/session is actively executing the item.
- `VERIFY`: implementation exists and validation remains; continue when the required tools are available.
- `REVIEW`: PR/review repair remains; continue when access exists.
- `MERGE`: convergence/merge remains; continue when authorized and gates pass.
- `OPERATOR`: progress requires human-controlled credentials, protected runtime access, explicit approval, physical action, or provider inspection.
- `BLOCKED`: a concrete dependency, collision, failing external service, forbidden-scope boundary, or separately owned writer prevents progress.
- `DONE`: the acceptance gate is satisfied and no safe actionable work remains in scope.

`READY`, `CLAIMED`, `VERIFY`, `REVIEW`, and `MERGE` are continuation states, not stopping states.

A `CLAIMED` item must name a real writer or session. Sentinel owner values such as `unclaimed`, `none`, `unknown`, `tbd`, or `n/a` are not ownership evidence.

## Required task fields

Every task block must contain exactly one non-blank value for each of:

- `Status`
- `Priority` (`P0` through `P3`)
- `Owner`
- `Branch / PR`
- `Scope`
- `Forbidden`
- `Dependencies`
- `References`
- `Acceptance gate`
- `Gate`
- `Last proof`
- `Next action`
- `Updated`

Duplicate field names are invalid; a later field may never overwrite or reinterpret an earlier value.

Each repository owns its task-prefix namespace. AgentSwitchboard uses `ASQ-*`; AxTask keeps `AXQ-*`; consumer repositories must choose an unambiguous local prefix rather than copying `AXQ-*`. Every task-like heading using the local prefix must match the repository's canonical heading format; malformed prefixed headings must fail validation rather than disappear from the parser.

## Proof and terminal-state rules

A `DONE` item must include at least one durable evidence token in `Last proof`:

- `commit:<git-sha>`
- `merge:<git-sha>`
- `workflow:<run-id>` or `run:<run-id>`
- `artifact:<durable-path-or-reference>`
- `operator-proof:<durable-external-reference>`

A PR number by itself is not terminal proof. Plain prose such as `completed successfully` is not durable proof.

For `DONE`:

- `Gate` must be exactly `none`.
- `Next action` must be exactly `none; no safe actionable work remains`.

For `BLOCKED` or `OPERATOR`, `Gate` must name the exact blocking condition.

For continuation states, `Next action` must be a concrete executable progression. It must begin with an action such as run, execute, create, update, repair, resolve, merge, fetch, inspect, open, verify, validate, test, commit, push, rebase, retarget, compare, generate, record, obtain, install, apply, build, launch, deploy, restore, export, import, review, reconcile, invoke, edit, write, move, copy, sync, or check. Status-only phrases such as `PR opened`, `CI green`, `status unchanged`, `wait`, or `merge later` are invalid next actions.

## Collision and freshness rules

- One writer per branch remains mandatory.
- Ledger claims do not override branch/worktree ownership.
- Before writing the ledger, re-read the latest revision and preserve concurrent task blocks.
- Never delete, rewrite, renumber, or mark another active item complete merely to simplify a merge.
- A collision is recorded as `BLOCKED` with the conflicting branch, PR, owner, or task named.
- Stale references must fail validation or be repaired before the ledger can be treated as current evidence.

## Consumer compatibility contract

A v1 consumer must provide:

1. one tracked repository-local ledger;
2. one local deterministic validator owned by the consumer;
3. positive and negative contract tests or equivalent fixtures;
4. CI and/or an existing opt-in hook path that runs the local validator;
5. one adoption manifest containing the canonical contract ID/version, canonical source paths, donor provenance, proof ceiling, and forbidden-copy boundary.

Consumers must not fetch or execute validators from AgentSwitchboard at validation time. The portable contract is shared; execution remains repository-local.

## Proof ceiling

This contract and its deterministic validators can prove ledger structure, status semantics, durable-proof syntax, continuation/terminal-state rules, compatibility metadata, and selected local reference existence. They cannot prove that referenced implementation is correct, CI actually passed, a PR merged, a provider changed state, an operator performed a protected action, or a runtime behaved as claimed. Those require their owning evidence surfaces.
