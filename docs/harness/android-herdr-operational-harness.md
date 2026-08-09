# Android Herdr operational harness

## Purpose

This harness turns the Android Herdr migration into a repeatable evidence loop instead of a one-off terminal experiment. It owns migration maps, workflow specs, tracked upstream source binding, artifacts, validators, opt-in hooks, a scoped skill, status/report generation, and the proof boundary. It does **not** own the canonical Android product runtime.

The fallback remains tmux. A missing Herdr executable is a classified state, not authority to improvise an installer.

## Fresh-agent entry

Read `AGENTS.md`, harness doctrine, the parent Android Termux manifest, `tooling/profiles/android/harness/herdr/manifest.json`, its codebase map, `.ai/skills/android-herdr-migration/SKILL.md`, and `tooling/profiles/android/harness/herdr/upstream-installation-source.json`, then select a workflow from `workflows/workflow-specs.json`.

## Workflow selection

- No phone evidence: run the readiness probe.
- `KEEP_TMUX_HERDR_NOT_INSTALLED`: build the source-bound installation review. If it is `BLOCKED`, do not install; advance to Android compatibility or explicit upstream-support proof.
- `KEEP_TMUX_HERDR_BINARY_NOT_HEALTHY`: repair binary compatibility before server testing.
- `HERDR_BINARY_CANDIDATE_ONLY`: stop harness-only work at the runtime authority boundary and open a separately authorized live proof.
- Tracked harness change: run validate-before-commit.
- Completed gate or real blocker: render the handoff/status report.

## Source binding

`upstream-installation-source.json` is a tracked, reviewable snapshot of official upstream facts. It pins the release/tag/commit and candidate asset identity used by the installation review. It is deliberately separate from generated phone evidence.

A source snapshot can prove what upstream published and documented at its verification time. It cannot prove that a Linux asset runs under Android/Termux. If Android/Termux support is not explicitly established, the builder must emit `DECISION=BLOCKED` and no install command.

## Operator commands

```sh
python tooling/profiles/android/harness/herdr/Get-HerdrHarnessStatus.py
python tooling/profiles/android/harness/herdr/Get-HerdrHarnessStatus.py --write
python tooling/profiles/android/harness/herdr/Build-HerdrInstallReview.py --write
bash Test-AgentSwitchboard-Android-Herdr.sh evidence
```

## Artifact policy

Generated evidence is local and untracked under `${XDG_STATE_HOME:-$HOME/.local/state}/agentswitchboard/android-herdr-migration`. The synthetic `fixtures/herdr-not-installed.fixture.env` proves deterministic routing only; it is not phone runtime proof. The upstream source snapshot is tracked configuration, not generated phone evidence.

## Validation

```sh
bash -n Test-AgentSwitchboard-Android-Herdr.sh
bash -n tooling/profiles/android/harness/herdr/Probe-Herdr-Migration.sh
bash -n tooling/profiles/android/harness/herdr/hooks/Invoke-HerdrHarnessPreCommit.sh
bash -n tooling/profiles/android/harness/herdr/hooks/Invoke-HerdrHarnessPrePush.sh
python tests/test_android_herdr_migration.py
python tests/test_android_herdr_install_review.py
python tests/test_android_herdr_harness_completeness.py
python tests/test_android_termux_harness.py
python tests/test_android_termux_modal_state_harness.py
git diff --check
```

PowerShell-capable repo/CI also runs `pwsh -NoLogo -NoProfile -File scripts/Test-AndroidHerdrHarnessCompleteness.ps1`.

## Hooks

The Herdr pre-commit and pre-push hooks are opt-in validators. They never install themselves, install Herdr, fetch, force-update refs, mutate Android policy, or remove tmux.

## Failure and rollback

Keep tmux when any gate is absent or fails. Never use Linux `aarch64` as Android compatibility proof, a tracked source snapshot as runtime proof, command presence as persistence proof, detach/reattach as agent-state proof, or a fixture as live behavior. Harness rollback is a normal Git revert; generated local artifacts can be removed independently because this lane does not alter the product runtime.

## Proof ceiling

Tracked files and hosted validation prove harness structure, deterministic classification, source-bound installation decision, workflow selection, artifact ownership, report generation, hooks, skill, validators, and CI wiring. They do not prove Herdr runs on Termux, a server survives Android backgrounding, agent state is correct, a coding sprint succeeds, or tmux can be retired.
