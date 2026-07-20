---
id: project-end-to-end-testing
version: 1.0.0
status: canonical
---

# Project End-to-End Testing

## Trigger

Use for an explicit end-to-end, E2E, system, integration, full-project, aggregate-harness, or exact-head validation request; for a change that crosses more than one registered harness node; or when a runtime event cascade, platform profile, launcher, installer, or repository integration needs a complete proof ladder.

This skill orchestrates the project-wide validation sequence. Use `evidence-validation` to repair individual failed findings and `runtime-proof` for any authorized live execution stage.

## Inputs

- repository, branch or worktree, PR or sprint, and exact head SHA;
- owned scope, forbidden scope, dependencies, and collision boundaries;
- changed files, affected contracts, and expected observable behavior;
- required proof level and explicit proof ceiling;
- repository-native validators, aggregate harness entrypoints, and CI workflows;
- available operating systems, tools, capabilities, runtime authority, rollback, and cleanup rules;
- approved artifact root and secret, personal-data, customer-data, and generated-output policy.

## Procedure

1. **Establish the floor.** Verify repository identity, current branch or worktree, base and head commits, ownership, and preservation of unrelated work. Read `AGENTS.md`, the nearest nested contract, `CODEBASE_MAP.md`, `SKILLS.md`, `TRIGGERS.md`, the affected implementation, and applicable governance or product law.
2. **Freeze the acceptance contract.** State the expected behavior, affected boundaries, required proof level, proof ceiling, validation order, stop conditions, and authorized runtime or target scope before testing. A builder may not weaken or replace a failing gate to manufacture a pass.
3. **Map the validation surface.** Resolve changed paths to their focused parsers, schema checks, unit or contract tests, integration validators, aggregate observers, runtime workflows, and exact-head CI jobs. Reuse registered validators and workflows before creating another test runner.
4. **Build the proof ladder.** Unless the task supplies a stricter order, run:
   1. parser, formatting, schema, and static checks;
   2. focused unit, fixture, or contract tests for the changed surface;
   3. integration checks across directly affected components and handoffs;
   4. the registered offline aggregate harness, including `Test-AppHarness.cmd` when the affected nodes are part of its composition graph;
   5. one explicitly authorized, bounded runtime pass through `runtime-proof` when static, integration, or synthetic evidence cannot prove the requested behavior;
   6. full PR-range hygiene and exact-head CI.
5. **Run focused checks before broader safe validation.** Do not spend runtime, provider, target, or expensive integration capacity while a lower deterministic floor is failing, unless the owner supplied a different validation order.
6. **Fail closed and repair in context.** Stop at the first blocking contradiction, preserve the exact command and evidence, classify the failure, and use `evidence-validation` for the smallest corrective guard. Re-run the failed stage and all dependent later stages; do not blindly restart the whole workflow or discard the branch context.
7. **Capture evidence.** Record every command, environment, commit SHA, exit result, pass, skip, failure, duration when available, generated artifact path, and cleanup result. Keep large or sensitive runtime output outside Git and publish only minimized, reviewable evidence.
8. **Promote proof honestly.** Static or synthetic proof does not establish runtime or live-target behavior. Process exit code zero alone is not delivery proof. Exact-head CI proves only the behavior observed in that workflow environment. Promote a runtime claim only when the expected behavior, resulting artifacts, and final state were directly observed under the authorized run contract.
9. **Close out the branch and PR.** Report changed files, validators actually run, skipped checks with reasons, artifacts and tracking policy, repairs, commit and push state, PR and CI state, final Git state, proof level, proof ceiling, gaps, risks, and one exact next command.

## Outputs

- an ordered validation matrix covering each affected component and handoff;
- exact command and result evidence for every executed stage;
- focused regression guards or repairs when a stage exposed a defect;
- machine-readable artifacts and concise English reports when the selected validators emit them;
- exact-head CI and PR evidence;
- an honest proof-level and proof-ceiling statement with blockers, skips, cleanup, and remaining risks.

## Deterministic validation

The skill contract is validated by `scripts/Test-AgentDocumentationContract.ps1`.

For an implementation sprint, the selected project checks must include the repository-native focused validators, applicable integration checks, `Test-AppHarness.cmd` when the changed nodes are registered in the aggregate graph, full PR-range `git diff --check`, and exact-head CI. Runtime validation is delegated to `runtime-proof` and must compare expected behavior and artifacts with the authorized run contract.

## Forbidden scope

- Do not invent a new runner when a healthy registered validator, workflow, or aggregate harness already owns the behavior.
- Do not reorder or skip an owner-supplied validation sequence without recording the conflict.
- Do not weaken tests, fixtures, schemas, acceptance criteria, or proof requirements merely to obtain a pass.
- Do not infer runtime, provider, integration, deployment, or live-target success from static inspection, synthetic fixtures, process startup, or exit code alone.
- Do not execute live targets, deployments, provider calls, installers, account or save mutation, secret access, destructive cleanup, merge, or release without explicit authority.
- Do not commit raw credentials, private identities, customer evidence, machine-local paths, huge logs, dumps, or generated runtime junk.
- Do not use blind retries, unbounded loops, concurrent writers on one branch, or cleanup outside owned temporary assets.

## Stop and escalate

Stop when repository state is unsafe or ambiguous; a required validator or capability is missing or unverified; a lower proof stage fails; expected and observed behavior conflict; an unexpected mutation occurs; rollback or cleanup is unavailable; runtime authority is absent; sensitive data cannot be minimized; exact-head CI contradicts local evidence; or the requested proof exceeds the approved environment.

Preserve the branch, commands, artifacts, failure classification, proof ceiling, and smallest safe next action. Do not promote completion while a required stage is failed, skipped without authorization, or unobserved.
