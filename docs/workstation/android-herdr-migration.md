# Android Herdr migration

## Status

Herdr is an **experimental candidate** for the AgentSwitchboard Android orchestration layer. The canonical Android runtime remains Pi + tmux until the installation review, runtime-compatibility review, and live same-device Android/Termux proof clear the migration gates.

Upstream currently documents stable Linux and macOS binaries, including Linux `aarch64`, plus preview Windows builds. Upstream installation documentation does **not** currently claim Android/Termux support, so this repository does not treat Linux `aarch64` availability as Android compatibility proof. The tracked installation decision remains **BLOCKED**.

The repository also does not use `cargo install herdr` as an installation contract unless the pinned upstream source documents that path.

## Source-bound installation gate

Installation evidence is pinned in:

```text
tooling/profiles/android/harness/herdr/upstream-installation-source.json
```

Generate the install review with:

```sh
python tooling/profiles/android/harness/herdr/Build-HerdrInstallReview.py --write
```

The current review must report `DECISION=BLOCKED`. A BLOCKED review deliberately contains **no installation command**.

## Source-bound runtime compatibility gate

The next gate is separate from installation. Exact Herdr v0.8.0 source/build evidence is pinned in:

```text
tooling/profiles/android/harness/herdr/upstream-runtime-compatibility.json
```

The pinned release workflow builds `herdr-linux-aarch64` for Rust target `aarch64-unknown-linux-musl`; it is not an Android-targeted artifact. The same pinned source has explicit Linux/macOS/Windows platform modules, while `target_os=android` selects Herdr's unsupported fallback platform implementation. That fallback stubs daemon detachment, process discovery, process signalling/existence checks, and other platform functions.

Therefore two routes are intentionally distinguished:

1. **Native Android source build (`aarch64-linux-android`)** — `BLOCKED_UNSUPPORTED_PLATFORM_FALLBACK` at this source commit. Do not treat successful compilation as migration readiness.
2. **Exact Linux-musl ARM64 release asset** — `EXECUTION_PROBE_APPROVED_NO_INSTALL`. Only an ephemeral identity probe is authorized.

Render the compatibility review:

```sh
python tooling/profiles/android/harness/herdr/Build-HerdrCompatibilityReview.py --write
```

Expected result:

```text
DECISION=EXECUTION_PROBE_APPROVED_NO_INSTALL
MIGRATION_DECISION=KEEP_TMUX
NEXT_GATE=exact-device-prebuilt-execution-identity
```

## Exact no-install phone probe

Only after the compatibility review above, run:

```sh
python tooling/profiles/android/harness/herdr/Probe-HerdrPrebuiltCompatibility.py evidence
```

The probe:

- downloads only the pinned v0.8.0 `herdr-linux-aarch64` release asset into a private temporary directory;
- requires exact size `19960864` bytes;
- requires SHA-256 `f647ac66468d9efbc642fe534fb284468f0aea60641606fc008dfc0d82a3ca87` before execution;
- gives the verified file owner-only executable permission;
- runs only `--version` with a 10-second timeout;
- isolates HOME and all XDG state/cache/config/data paths inside the temporary sandbox;
- writes bounded sanitized evidence under `~/.local/state/agentswitchboard/android-herdr-migration/`;
- removes the temporary binary/sandbox automatically.

It does **not** copy the binary into a persistent executable path, install Herdr, run an installer/update, start a server, create or attach a Herdr session, change Android policy, or remove tmux.

A result of `EXEC_COMPATIBILITY=PASS` proves only that the exact Linux-musl ARM64 asset can execute its version command on this phone. It does not prove PTY behavior, IPC, process detection, server persistence, detach/reattach, or agent state. The next gate after PASS is a separately reviewed bounded server-start test.

## Why evaluate Herdr

Herdr adds agent-aware pane state, persistent background sessions, tmux-style `Ctrl+B` prefix behavior, detach/reattach, workspaces/tabs/panes, and a CLI/socket control surface. These capabilities match the AgentSwitchboard workload if they remain reliable under Android/Termux constraints.

## Safety rule

Do **not** install Herdr while the tracked install review is `BLOCKED`. Do **not** uninstall tmux, rewrite the canonical Android launcher, or mutate Android `device_config` / battery policy as part of the compatibility probe. Background-process survival must be observed on the actual phone rather than assumed or forced by an undocumented workaround.

## Phone readiness command

The original readiness classifier remains:

```sh
bash Test-AgentSwitchboard-Android-Herdr.sh evidence
```

Expected installed-state outcomes remain `KEEP_TMUX_HERDR_NOT_INSTALLED`, `KEEP_TMUX_HERDR_BINARY_NOT_HEALTHY`, or `HERDR_BINARY_CANDIDATE_ONLY`. Generated evidence stays local and untracked.

When a source-bound BLOCKED install-review artifact is present, `Get-HerdrHarnessStatus.py` now advances `KEEP_TMUX_HERDR_NOT_INSTALLED` to the compatibility-review command instead of repeating the completed install review.

## Promotion gates

Herdr becomes eligible to replace tmux only after:

1. Termux environment and architecture are observed.
2. A source-bound installation method is reviewed.
3. Runtime compatibility is source-reviewed.
4. Exact-device executable identity is observed with same-device evidence.
5. A separately authorized background Herdr server starts successfully.
6. Detach and reattach restore the same session.
7. A supported coding agent is correctly classified as working / blocked / idle or done.
8. The session survives the Android background/app-switch condition relevant to the operator workflow.
9. A bounded AgentSwitchboard sprint completes with durable evidence, commit, push, and PR behavior at least as strong as the current tmux path.
10. Existing Android runtime and harness validators remain green.

Failure at any gate means **keep tmux** and preserve bounded evidence for the next repair sprint.

## Validation

```sh
bash -n tooling/profiles/android/harness/herdr/Probe-Herdr-Migration.sh
bash Test-AgentSwitchboard-Android-Herdr.sh contract
python tooling/profiles/android/harness/herdr/Probe-HerdrPrebuiltCompatibility.py contract
python tests/test_android_herdr_migration.py
python tests/test_android_herdr_install_review.py
python tests/test_android_herdr_compatibility_review.py
python tests/test_android_herdr_harness_completeness.py
python tests/test_android_termux_harness.py
python tests/test_android_termux_modal_state_harness.py
git diff --check
```

## Proof ceiling

These tracked files prove migration policy, exact upstream source/build binding, deterministic installation and compatibility decisions, safe no-install probe boundaries, and CI validation. They do not prove Herdr server/runtime behavior on Android/Termux or permit tmux retirement.
