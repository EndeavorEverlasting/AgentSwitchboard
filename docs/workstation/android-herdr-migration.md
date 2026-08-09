# Android Herdr migration

## Status

Herdr is an **experimental candidate** for the AgentSwitchboard Android orchestration layer. The canonical Android runtime remains Pi + tmux until every source review and live **same-device** gate is proven.

Upstream documents stable Linux and macOS binaries, including Linux `aarch64`, plus preview Windows builds. Upstream installation documentation does **not** currently claim Android/Termux support, so Linux architecture alone is not migration proof. The tracked installation decision remains BLOCKED and emits no install command.

## Source-bound installation gate

Tracked source: `tooling/profiles/android/harness/herdr/upstream-installation-source.json`.

```sh
python tooling/profiles/android/harness/herdr/Build-HerdrInstallReview.py --write
```

Current expected decision: `DECISION=BLOCKED`. Do not use undocumented `cargo install herdr` or infer an installer from the Linux artifact.

## Runtime compatibility gate

Tracked source: `tooling/profiles/android/harness/herdr/upstream-runtime-compatibility.json`.

The v0.8.0 `herdr-linux-aarch64` asset is built for `aarch64-unknown-linux-musl`; native `aarch64-linux-android` selects Herdr's unsupported platform fallback at the pinned source. The exact Linux-musl asset therefore receives only a no-install execution-identity experiment.

```sh
python tooling/profiles/android/harness/herdr/Build-HerdrCompatibilityReview.py --write
python tooling/profiles/android/harness/herdr/Probe-HerdrPrebuiltCompatibility.py evidence
```

A PASS proves only exact size/digest plus `herdr 0.8.0` execution on that phone. It does not install Herdr or prove server behavior.

## Bounded foreground server-start gate

After exact same-device prebuilt execution PASS, read `tooling/profiles/android/harness/herdr/upstream-server-start-source.json` and build:

```sh
python tooling/profiles/android/harness/herdr/Build-HerdrServerStartReview.py --write
```

Expected decision:

```text
DECISION=BOUNDED_FOREGROUND_SERVER_PROBE_APPROVED_NO_INSTALL
MIGRATION_DECISION=KEEP_TMUX
NEXT_GATE=exact-device-foreground-server-start-stop
```

Pinned upstream source distinguishes two launch paths:

- bare `herdr` uses auto-detect and may create a **detached background daemon**;
- explicit `herdr server` dispatches directly to the **headless foreground server**.

The bounded phone test therefore never runs bare `herdr`. It uses:

```sh
python tooling/profiles/android/harness/herdr/Probe-HerdrServerStart.py evidence
```

The probe re-downloads and verifies only the pinned v0.8.0 asset, creates an ephemeral config with onboarding/version/manifest checks disabled, isolates HOME/XDG paths and `HERDR_SOCKET_PATH`, starts only `herdr server`, polls only `herdr status server --json`, and stops only with `herdr server stop`.

A PASS requires: running=true, version 0.8.0, compatible protocol, exact isolated socket, stop exit 0, clean foreground process exit, and not-running afterward. The temporary binary, sockets/config/logs and sandbox are removed. Failed graceful shutdown triggers bounded process-tree cleanup before evidence is written.

This gate does **not** install Herdr, attach a client, create a workspace through CLI commands, test detach/reattach, test Android background survival, mutate `device_config`/battery policy, or replace tmux. A PASS advances only to `bounded-client-attach-review`.

## Why evaluate Herdr

Herdr offers agent-aware panes, persistent sessions, tmux-style prefix behavior, workspaces/tabs/panes and a CLI/socket control surface. Those capabilities are relevant only if the Linux-musl binary remains reliable across Android/Termux lifecycle gates.

## Safety rule

**Do not uninstall tmux** or rewrite the canonical Android launcher while this harness is experimental. Do not run bare Herdr daemon auto-launch from the bounded server probe. Do not mutate Android phantom-process or battery policy to manufacture a PASS.

## Phone readiness command

```sh
bash Test-AgentSwitchboard-Android-Herdr.sh evidence
```

Generated phone evidence remains local/untracked under the XDG-aware AgentSwitchboard state root.

## Promotion gates

1. Termux environment/architecture observed.
2. Source-bound installation review.
3. Source-bound runtime compatibility review.
4. Exact-device prebuilt execution identity observed.
5. Source-bound foreground server-start review.
6. Foreground server start/status/stop observed.
7. Separately reviewed client attach.
8. Detach/reattach restores the same session.
9. Supported coding agent state is correctly detected.
10. Android background/app-switch survival is observed.
11. A bounded AgentSwitchboard sprint completes with durable commit/push/PR evidence.
12. Existing Android runtime/harness validators remain green.

Failure at any gate means **keep tmux** and preserve bounded evidence.

## Validation

```sh
bash -n tooling/profiles/android/harness/herdr/Probe-Herdr-Migration.sh
bash Test-AgentSwitchboard-Android-Herdr.sh contract
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

## Proof ceiling

Tracked harness files prove source binding, deterministic review/routing contracts, bounded live-probe authority and validation wiring. Same-device prebuilt PASS proves executable identity; same-device server-start PASS can prove only foreground headless start/status/stop and local IPC. Neither proves client attach, detach/reattach, persistence, agent state, background survival, coding-agent success, or permission to retire tmux.
