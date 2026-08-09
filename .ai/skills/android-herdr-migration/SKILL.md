---
id: android-herdr-migration
version: 1.4.0
status: experimental
---

# Android Herdr migration

## Trigger

Use when Herdr is being evaluated, installed, repaired, validated, or considered as a replacement for tmux on AgentSwitchboard Android/Termux, including installation review, runtime compatibility, exact prebuilt execution identity, bounded server-start review, a device-only harness validation mismatch, or later persistence/agent-aware proof.

## Inputs

- repository branch/PR identity;
- current sanitized same-device phone evidence when available;
- tracked `upstream-installation-source.json`;
- tracked `upstream-runtime-compatibility.json`;
- tracked `upstream-server-start-source.json`;
- first unproved migration gate;
- owned harness scope and forbidden product/runtime scope.

## Procedure

1. Read `AGENTS.md`, harness doctrine, parent Android Termux manifest, Herdr manifest/codebase map, tracked source snapshots, and selected workflow.
2. Preserve tmux as canonical until every migration gate has same-device proof and the canonical runtime is changed by a separately authorized product sprint.
3. Run `Get-HerdrHarnessStatus.py` with known evidence to select the first unproved gate; deterministic tests use an isolated `--state-root`.
4. Missing Herdr with no install review: build `Build-HerdrInstallReview.py --write`. Current source-bound decision remains BLOCKED and emits no install command.
5. Completed BLOCKED install review: build `Build-HerdrCompatibilityReview.py --write`. Native Android source builds remain blocked because the pinned source selects the unsupported fallback module.
6. Compatibility decision `EXECUTION_PROBE_APPROVED_NO_INSTALL`: run only `Probe-HerdrPrebuiltCompatibility.py evidence`. It may temporarily download/verify the exact asset and execute only `--version`.
7. Exact same-device prebuilt PASS (`herdr 0.8.0`, exact release commit/artifact/digest) advances to `Build-HerdrServerStartReview.py --write`; do not repeat the identity gate.
8. The bounded server review authorizes only `Probe-HerdrServerStart.py evidence`. The probe may re-download and verify the exact asset, then run explicit foreground `herdr server` under isolated HOME/XDG paths and `HERDR_SOCKET_PATH`.
9. Never run bare `herdr` from the server-start probe: pinned upstream auto-detect may spawn a detached daemon. Readiness is observed only with `herdr status server --json`; shutdown uses only `herdr server stop`.
10. The server-start probe must enforce bounded start/command timeouts, verify version/protocol/socket identity, require a clean foreground exit and not-running post-state, and force-clean the temporary process tree on failure.
11. Server-start PASS proves only foreground headless lifecycle plus local status/stop IPC. It does not authorize installation, client attach, detach/reattach, background survival, workspace/session use, agent-state proof, Android policy changes, or tmux removal. Route next to a separately reviewed bounded-client-attach gate.
12. If clean CI and an operator device disagree, isolate synthetic state before changing assertions; preserve real operator evidence.
13. Keep generated evidence under the XDG-aware artifact registry root and out of Git. Never persist credentials, device codes, private keys, customer data, or private hostnames.
14. Before commit/push, run focused contracts, completeness validators, existing Android floor, hooks, and `git diff --check`; repair owned failures in the same context.
15. Report working/blocked/missing/proof ceiling and one exact executable next action.

## Outputs

- selected Herdr gate/workflow;
- tracked source-bound install, compatibility, and server-start reviews;
- optional local prebuilt identity and bounded server lifecycle evidence;
- focused validation receipt;
- exact next action with honest proof ceiling.

## Deterministic validation

- `python tests/test_android_herdr_migration.py`
- `python tests/test_android_herdr_install_review.py`
- `python tests/test_android_herdr_compatibility_review.py`
- `python tests/test_android_herdr_server_start_review.py`
- `python tests/test_android_herdr_status_state_isolation.py`
- `python tests/test_android_herdr_harness_completeness.py`
- `python tooling/profiles/android/harness/herdr/Probe-HerdrPrebuiltCompatibility.py contract`
- `python tooling/profiles/android/harness/herdr/Probe-HerdrServerStart.py contract`
- `pwsh -NoLogo -NoProfile -File scripts/Test-AndroidHerdrHarnessCompleteness.ps1`
- `bash tooling/profiles/android/harness/herdr/hooks/Invoke-HerdrHarnessPreCommit.sh`
- `bash tooling/profiles/android/harness/herdr/hooks/Invoke-HerdrHarnessPrePush.sh` before push
- existing Android Termux portable contracts
- `git diff --check`

## Forbidden scope

- do not modify `AGENTS.md` or governance policy from this harness skill;
- do not modify the canonical Android product launcher/runtime from a harness-only sprint;
- do not install Herdr while the installation review remains BLOCKED;
- do not treat the no-install identity or server probes as installation approval;
- do not run bare `herdr` auto-detect from the bounded server probe;
- do not attach a Herdr client, create workspaces/sessions, test detach/reattach, or claim persistence from the server-start probe;
- do not weaken deterministic assertions to accommodate ambient operator state;
- do not uninstall tmux or promote Herdr before every live gate passes;
- do not mutate Android `device_config`, phantom-process limits, or battery policy automatically;
- do not persist secrets or raw phone evidence in Git;
- do not force-push, destructively clean, or write the default branch.

## Stop and escalate

Stop when a bounded live probe fails, when the next live gate requires authority not granted by this harness lane, validation fails outside owned scope after state isolation, evidence contains sensitive material, or another writer owns the necessary paths. Preserve tmux and the smallest safe evidence, then name the owner, dependency, artifact, and exact action that advances the gate.
