# Android Herdr operational harness

## Purpose

This harness turns the Android Herdr migration into a repeatable evidence loop instead of a one-off terminal experiment. It owns migration maps, workflow specs, tracked upstream source bindings, local artifacts, validators, opt-in hooks, a scoped skill, status/report generation, installation and runtime-compatibility reviews, and the proof boundary. It does **not** own the canonical Android product runtime.

The fallback remains tmux. Missing Herdr, a BLOCKED install review, or a failed compatibility probe are classified states, not authority to improvise an installer.

## Fresh-agent entry

Read `AGENTS.md`, harness doctrine, the parent Android Termux manifest, `tooling/profiles/android/harness/herdr/manifest.json`, its codebase map, both tracked upstream source snapshots, `.ai/skills/android-herdr-migration/SKILL.md`, then select a workflow from `workflows/workflow-specs.json`.

## Workflow selection

- No phone evidence: run the readiness probe.
- `KEEP_TMUX_HERDR_NOT_INSTALLED` with no completed install review: build the source-bound install review.
- Completed v0.8.0 BLOCKED install review: build the source-bound runtime compatibility review.
- Compatibility review `EXECUTION_PROBE_APPROVED_NO_INSTALL`: the only authorized live action is the exact temporary prebuilt `--version` probe.
- Prebuilt execution PASS: stop before server startup and route to a separately reviewed bounded-server-start gate.
- Prebuilt execution failure: keep tmux and preserve the local evidence.
- Tracked harness change: run validate-before-commit.
- Completed gate or real blocker: render the handoff/status report.

## Operator commands

```sh
python tooling/profiles/android/harness/herdr/Get-HerdrHarnessStatus.py
python tooling/profiles/android/harness/herdr/Get-HerdrHarnessStatus.py --write
python tooling/profiles/android/harness/herdr/Build-HerdrInstallReview.py --write
python tooling/profiles/android/harness/herdr/Build-HerdrCompatibilityReview.py --write
python tooling/profiles/android/harness/herdr/Probe-HerdrPrebuiltCompatibility.py contract
python tooling/profiles/android/harness/herdr/Probe-HerdrPrebuiltCompatibility.py evidence
bash Test-AgentSwitchboard-Android-Herdr.sh evidence
```

## Runtime compatibility contract

At Herdr v0.8.0 commit `346411fa21afd297f5ed3b3fa56f9e3fbf7654b7`:

- the official ARM64 release asset is built as `aarch64-unknown-linux-musl`;
- the release matrix does not include an Android target;
- native `target_os=android` selects Herdr's unsupported fallback platform implementation rather than its Linux implementation;
- the fallback stubs critical process/daemon/platform operations;
- Linux source uses `/proc`, process groups/signals, PTYs, and Unix local sockets;
- official Android/Termux support remains unstated.

Therefore native Android builds remain blocked, while the exact Linux-musl asset is allowed only an ephemeral checksum-verified `--version` execution probe. That probe is not installation and does not authorize a server.

## Artifact policy

Generated evidence is local and untracked under `${XDG_STATE_HOME:-$HOME/.local/state}/agentswitchboard/android-herdr-migration`. `Get-HerdrHarnessStatus.py` follows that XDG-aware root for normal operator discovery and output. The synthetic fixture proves deterministic routing only; it is not phone runtime proof. Tracked upstream JSON files are source snapshots, not live evidence.

## Validator state isolation

Synthetic validators must not consume the operator's real local readiness/review history. A phone can legitimately contain `herdr-install-review-*.md` artifacts that advance the live state machine, while a completeness test may need to prove the earlier no-review state. Those are different inputs and must not collide.

`Get-HerdrHarnessStatus.py --state-root <dir>` provides an explicit discovery/output root for deterministic validation. `tests/test_android_herdr_status_state_isolation.py` is the regression contract: it creates an ambient XDG state root containing a valid BLOCKED install review, proves an explicitly isolated state root still classifies `blocked-herdr-not-installed`, proves normal XDG discovery sees the ambient review and advances to `blocked-herdr-runtime-compatibility-unproved`, and proves `--write` keeps synthetic output inside the isolated root.

Do not repair a device-only validator mismatch by weakening assertions or deleting real operator evidence. Isolate the synthetic state, then rerun the full focused floor.

## Validation

```sh
bash -n Test-AgentSwitchboard-Android-Herdr.sh
bash -n tooling/profiles/android/harness/herdr/Probe-Herdr-Migration.sh
bash -n tooling/profiles/android/harness/herdr/hooks/Invoke-HerdrHarnessPreCommit.sh
bash -n tooling/profiles/android/harness/herdr/hooks/Invoke-HerdrHarnessPrePush.sh
python tooling/profiles/android/harness/herdr/Probe-HerdrPrebuiltCompatibility.py contract
python tests/test_android_herdr_migration.py
python tests/test_android_herdr_install_review.py
python tests/test_android_herdr_compatibility_review.py
python tests/test_android_herdr_status_state_isolation.py
python tests/test_android_herdr_harness_completeness.py
python tests/test_android_termux_harness.py
python tests/test_android_termux_modal_state_harness.py
git diff --check
```

PowerShell-capable repo/CI also runs `pwsh -NoLogo -NoProfile -File scripts/Test-AndroidHerdrHarnessCompleteness.ps1`.

## Hooks

The Herdr pre-commit and pre-push hooks are opt-in validators. They never install themselves, install Herdr, fetch the release asset, run the live compatibility evidence mode, force-update refs, mutate Android policy, or remove tmux. CI runs the compatibility probe in `contract` mode only.

## Failure and rollback

Keep tmux when any gate is absent or fails. Never use Linux architecture alone as Android proof, command presence as persistence proof, detach/reattach as agent-state proof, or a fixture as live behavior. A clean-CI/operator-device validation disagreement is first treated as possible ambient state contamination; preserve operator artifacts and rerun with isolated validator state. The compatibility evidence probe leaves no persistent Herdr binary; its temporary sandbox is removed automatically. Harness rollback is a normal Git revert.

## Proof ceiling

Tracked files and hosted validation prove harness structure, deterministic state-isolated classification, XDG-aware artifact discovery, source binding, workflow selection, artifact ownership, report generation, hooks, skill, validators, CI wiring, and the exact no-install probe boundary. They do not prove Herdr server compatibility, persistence, detach/reattach, agent state, Android background survival, coding-sprint success, installation approval, or tmux retirement.
