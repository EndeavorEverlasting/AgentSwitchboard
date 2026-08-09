---
id: android-herdr-migration
version: 1.3.0
status: experimental
---

# Android Herdr migration

## Trigger

Use when Herdr is being evaluated, installed, repaired, validated, or considered as a replacement for tmux on AgentSwitchboard Android/Termux, including `KEEP_TMUX_HERDR_NOT_INSTALLED`, a BLOCKED source review, runtime compatibility review, an unhealthy Herdr binary, a device-only harness validation mismatch, or a request to prove persistence or agent-aware state.

## Inputs

- repository branch/PR identity;
- current phone readiness evidence when available;
- tracked `tooling/profiles/android/harness/herdr/upstream-installation-source.json`;
- tracked `tooling/profiles/android/harness/herdr/upstream-runtime-compatibility.json`;
- current official Herdr source/release/install documentation when refreshing either tracked source;
- first unproved migration gate;
- owned harness scope and forbidden product/runtime scope.

## Procedure

1. Read `AGENTS.md`, harness doctrine, the parent Android Termux manifest, and the Herdr manifest/codebase map.
2. Preserve tmux as the canonical Android multiplexer until installation review, runtime compatibility, and every live promotion gate are proven.
3. Run `python tooling/profiles/android/harness/herdr/Get-HerdrHarnessStatus.py` with known readiness/install-review evidence to select the first unproved gate.
4. For `KEEP_TMUX_HERDR_NOT_INSTALLED` without a completed review, read `upstream-installation-source.json`, then run `python tooling/profiles/android/harness/herdr/Build-HerdrInstallReview.py --write`.
5. Treat the install review builder's `DECISION` as authoritative for that source snapshot. `BLOCKED` means no installation command is authorized.
6. After a source-bound BLOCKED install review, read `upstream-runtime-compatibility.json` and run `python tooling/profiles/android/harness/herdr/Build-HerdrCompatibilityReview.py --write`; do not rebuild the completed install review as the next action.
7. At the pinned Herdr v0.8.0 source, keep native `aarch64-linux-android` source builds blocked because `target_os=android` selects Herdr's explicit unsupported fallback platform module.
8. The exact `herdr-linux-aarch64` release asset is built for `aarch64-unknown-linux-musl`. The compatibility review authorizes only `python tooling/profiles/android/harness/herdr/Probe-HerdrPrebuiltCompatibility.py evidence`: temporary download, exact size/SHA-256 verification, isolated `--version`, bounded timeout, sanitized local evidence, automatic temporary cleanup.
9. The prebuilt compatibility probe is not an installer. Do not persist the binary, start a Herdr server, create/attach a Herdr session, run updates, mutate Android process/battery policy, or remove tmux.
10. A successful prebuilt `--version` proves execution identity only. Route next to a separately reviewed bounded server-start probe; failure keeps tmux and preserves the local evidence.
11. Deterministic validators must never infer synthetic state from real operator artifacts. Use `Get-HerdrHarnessStatus.py --state-root <isolated-temp-dir>` or the dedicated `tests/test_android_herdr_status_state_isolation.py` contract when validating routing. If clean CI and the operator device disagree, inspect ambient state discovery before weakening assertions.
12. `Get-HerdrHarnessStatus.py` must honor `${XDG_STATE_HOME:-$HOME/.local/state}` for normal operator state and explicit `--state-root` for isolated validation/output.
13. Promote only same-device live gates: server start, detach/reattach, agent-state detection, Android background survival, bounded AgentSwitchboard sprint, then existing Android validator compatibility.
14. Keep generated evidence under the artifact registry state root and out of Git; never persist credentials/device codes/private keys.
15. Before commit/push, run the focused validators and opt-in hooks; repair correctable harness failures in the same branch.
16. Render the operator report and provide one exact next command that advances the first unproved gate rather than repeating completed proof.

## Outputs

- selected Herdr workflow and gate classification;
- tracked installation and runtime-compatibility source bindings;
- source-bound install-review artifact;
- source-bound compatibility-review artifact;
- optional local prebuilt execution-identity evidence;
- focused harness validation receipt;
- exact next action with honest proof ceiling.

## Deterministic validation

- `python tests/test_android_herdr_migration.py`
- `python tests/test_android_herdr_install_review.py`
- `python tests/test_android_herdr_compatibility_review.py`
- `python tests/test_android_herdr_status_state_isolation.py`
- `python tests/test_android_herdr_harness_completeness.py`
- `python tooling/profiles/android/harness/herdr/Probe-HerdrPrebuiltCompatibility.py contract`
- `pwsh -NoLogo -NoProfile -File scripts/Test-AndroidHerdrHarnessCompleteness.ps1`
- `bash tooling/profiles/android/harness/herdr/hooks/Invoke-HerdrHarnessPreCommit.sh`
- `bash tooling/profiles/android/harness/herdr/hooks/Invoke-HerdrHarnessPrePush.sh` before push
- existing Android Termux portable contracts
- `git diff --check`

## Forbidden scope

- do not modify `AGENTS.md` or governance policy from this harness skill;
- do not modify the canonical Android product launcher/runtime from a harness-only sprint;
- do not install while the source-bound installation review is `BLOCKED`;
- do not treat the no-install compatibility probe as installation approval;
- do not start a Herdr server from the prebuilt execution-identity probe;
- do not weaken deterministic assertions merely because real local evidence changed a test result; isolate validator state first;
- do not uninstall tmux or promote Herdr before all live gates pass;
- do not invent an install method from package-name guesses or Linux architecture alone;
- do not mutate Android process/battery policy automatically;
- do not persist secrets, device codes, credentials, private hostnames, customer evidence, or raw machine-local junk;
- do not force-push, destructively clean, or write the default branch.

## Stop and escalate

Stop when the source-bound installation review is `BLOCKED` and runtime compatibility has not yet been reviewed, when the compatibility probe fails, when a server/live gate requires authority not granted by this harness lane, validation fails outside owned scope after state isolation, evidence contains sensitive material, or another writer owns the necessary paths. Preserve tmux fallback and the smallest safe evidence, then name the owner, dependency, artifact and executable action that advances the gate.
