# Android Herdr operational harness

## Purpose

This harness turns the Android Herdr migration into a source-bound, same-device evidence ladder. It owns maps, workflow specs, source snapshots, local artifact contracts, validators, opt-in hooks, scoped skill, operator reports, installation/runtime/server reviews, and bounded probe contracts. It does **not** own the canonical Android product runtime. tmux remains canonical.

## Fresh-agent entry

Read, in order: `AGENTS.md`, harness doctrine, parent Android Termux manifest, `tooling/profiles/android/harness/herdr/manifest.json`, codebase map, the three tracked upstream snapshots, `.ai/skills/android-herdr-migration/SKILL.md`, then select `workflows/workflow-specs.json`.

## Workflow selection

- No phone readiness evidence -> readiness probe.
- Missing Herdr with no completed install review -> source-bound install review.
- Completed BLOCKED install review -> runtime-compatibility review.
- Compatibility review approved for identity only -> ephemeral exact-asset `--version` probe.
- Exact same-device prebuilt execution PASS -> bounded server-start review.
- Server-start review approved -> foreground-only server start/status/stop probe.
- Foreground server lifecycle PASS -> **stop before client attach** and route to separately reviewed bounded-client-attach gate.
- Any failure -> keep tmux, preserve bounded local evidence, and route to failure recovery.
- Tracked harness change -> validate-before-commit.

## Operator commands

```sh
python tooling/profiles/android/harness/herdr/Get-HerdrHarnessStatus.py
python tooling/profiles/android/harness/herdr/Get-HerdrHarnessStatus.py --write
python tooling/profiles/android/harness/herdr/Build-HerdrInstallReview.py --write
python tooling/profiles/android/harness/herdr/Build-HerdrCompatibilityReview.py --write
python tooling/profiles/android/harness/herdr/Probe-HerdrPrebuiltCompatibility.py contract
python tooling/profiles/android/harness/herdr/Probe-HerdrPrebuiltCompatibility.py evidence
python tooling/profiles/android/harness/herdr/Build-HerdrServerStartReview.py --write
python tooling/profiles/android/harness/herdr/Probe-HerdrServerStart.py contract
python tooling/profiles/android/harness/herdr/Probe-HerdrServerStart.py evidence
```

## Bounded server lifecycle contract

Pinned Herdr v0.8.0 source makes an important distinction. Bare `herdr` uses auto-detect and can spawn a detached background server when no server exists. The explicit `herdr server` path dispatches directly to the headless foreground server. Therefore the Android bounded server probe **forbids bare `herdr`** and uses only explicit foreground `herdr server`.

The probe is allowed only after exact-device prebuilt execution identity has passed. It re-downloads the exact pinned `herdr-linux-aarch64` asset into a private temporary sandbox, verifies byte size and SHA-256, disables onboarding/background update checks in an ephemeral config, isolates HOME/XDG directories and `HERDR_SOCKET_PATH`, and starts the server in its own temporary process group solely so cleanup can be bounded.

Readiness is proved with `herdr status server --json`. Success requires running=true, Herdr 0.8.0, protocol compatibility, and the exact isolated socket. Shutdown uses `herdr server stop`; the foreground process must exit normally and a post-stop status must report not running. Any failure invokes bounded cleanup of the temporary process tree before the sandbox is removed.

This gate does not attach a client, create a workspace/session through CLI commands, test detach/reattach or Android background survival, install the binary, or mutate Android process policy.

## Artifact policy

Generated artifacts remain local and untracked under `${XDG_STATE_HOME:-$HOME/.local/state}/agentswitchboard/android-herdr-migration`. Current artifact classes include readiness, status, install review, compatibility review, prebuilt identity evidence, server-start review, server-start evidence, and validation receipts. Synthetic fixtures are never live proof.

## Validator state isolation

Synthetic routing tests use `Get-HerdrHarnessStatus.py --state-root <dir>` so real operator history cannot change deterministic assertions. `tests/test_android_herdr_status_state_isolation.py` proves this boundary. Never delete real evidence or weaken a validator simply because clean CI and the phone have different ambient state.

## Validation

```sh
bash -n Test-AgentSwitchboard-Android-Herdr.sh
bash -n tooling/profiles/android/harness/herdr/Probe-Herdr-Migration.sh
python tooling/profiles/android/harness/herdr/Probe-HerdrPrebuiltCompatibility.py contract
python tooling/profiles/android/harness/herdr/Probe-HerdrServerStart.py contract
python tests/test_android_herdr_migration.py
python tests/test_android_herdr_install_review.py
python tests/test_android_herdr_compatibility_review.py
python tests/test_android_herdr_server_start_review.py
python tests/test_android_herdr_status_state_isolation.py
python tests/test_android_herdr_harness_completeness.py
python tests/test_android_termux_harness.py
python tests/test_android_termux_modal_state_harness.py
git diff --check
```

PowerShell-capable CI also runs `scripts/Test-AndroidHerdrHarnessCompleteness.ps1`. Hosted CI runs both live probes in `contract` mode only; it never downloads the candidate asset or starts Herdr.

## Hooks

The Herdr pre-commit/pre-push hooks are opt-in. They validate contracts only. They never install Herdr, run live evidence modes, start a server, mutate Android policy, remove tmux, or force-update Git refs.

## Failure and rollback

Keep tmux after every missing or failed gate. The identity probe has no persistent binary. The server probe uses a temporary sandbox and includes forced process cleanup if graceful stop fails. Harness rollback is a normal Git revert; do not destructively clean operator artifacts.

## Proof ceiling

Tracked files and hosted validation prove harness completeness, state-isolated routing, XDG-aware artifact ownership, pinned upstream server semantics, and the bounded foreground server-start contract. A same-device PASS can additionally prove only foreground server start/status/stop and local IPC. It does not prove client attach, detach/reattach, persistent background survival, agent-state detection, coding-agent work, or tmux retirement.
