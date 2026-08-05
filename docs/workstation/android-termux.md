# AgentSwitchboard Android Profile — Termux

## Purpose

The Android Profile keeps AgentSwitchboard usable when a Windows workstation is unavailable.

The phone frontend is **Termux**, not WezTerm. WezTerm remains the managed desktop frontend on supported desktop platforms. The shared continuity boundary is the named **tmux** workspace: the phone can open or activate it locally, or attach to the same workspace on an SSH host.

```text
Android phone: Termux -> agentswitchboard-phone -> local tmux
                                      \-> SSH host -> remote tmux

Desktop host: WezTerm -> WSL/Linux -> the same named tmux workspace
```

## Supported installation source

Use a supported Termux installation from F-Droid or the official Termux GitHub repository. Do not mix Termux and plugin APKs from different signing sources.

Official references:

- `https://github.com/termux/termux-app#installation`
- `https://github.com/termux/termux-packages/wiki/package-management`
- `https://wezterm.org/installation.html`

## Repository-owned bootstrap

The bootstrap:

1. installs `git`, `openssh`, `tmux`, and `curl` through `pkg`;
2. clones AgentSwitchboard when absent;
3. otherwise requires the expected origin, a clean checkout, the selected branch, and a fast-forward-only update;
4. validates the tracked Android launcher;
5. installs it as `$PREFIX/bin/agentswitchboard-phone`;
6. writes local bootstrap evidence under `${XDG_STATE_HOME:-$HOME/.local/state}/agentswitchboard/android`.

### Current branch certificate command

Run this inside Termux while PR development is in progress:

```bash
curl -fL https://raw.githubusercontent.com/EndeavorEverlasting/AgentSwitchboard/64701e82df2292fb30d2629c5e9020008dc8f41c/Bootstrap-AgentSwitchboard-Termux.sh \
  -o "$PREFIX/tmp/Bootstrap-AgentSwitchboard-Termux.sh" &&
bash "$PREFIX/tmp/Bootstrap-AgentSwitchboard-Termux.sh" \
  --ref feat/android-termux-profile-20260804
```

After the feature merges, use the same pinned bootstrap with `--ref main`.

## Operator commands

Readiness:

```bash
agentswitchboard-phone status
```

Local phone workspace:

```bash
agentswitchboard-phone local
```

Named local workspace:

```bash
agentswitchboard-phone local --session dev-1
```

Remote durable workspace through an SSH config alias:

```bash
agentswitchboard-phone ssh workbox
```

Remote named workspace:

```bash
agentswitchboard-phone ssh user@host --session dev
```

Plan without opening or attaching:

```bash
agentswitchboard-phone ssh workbox --session dev --plan
```

## SSH boundary

The bootstrap installs the SSH client but does **not** create keys, copy credentials, weaken host-key verification, edit remote hosts, or choose a target for the operator.

Use a reviewed SSH config entry when possible. The launcher accepts only a compact SSH alias or `user@host` target without spaces.

## Android persistence boundary

Android may terminate background Termux processes. Local tmux is useful for phone-side work, but a tmux session on an always-on SSH host is the stronger continuity path when the phone app is suspended or killed.

## Evidence

Local state is written to:

```text
${XDG_STATE_HOME:-$HOME/.local/state}/agentswitchboard/android/
```

Expected files:

- `bootstrap-result.env`
- `last-result.env`

## Validation

Repository checks:

```bash
bash -n Bootstrap-AgentSwitchboard-Termux.sh
bash -n tooling/profiles/android/Invoke-AgentSwitchboardOpenOrActivate.sh
python3 tests/test_android_termux_profile.py
python3 tests/test_device_profile_launcher_contract.py
```

## Proof ceiling

Tracked implementation, argument validation, offline plan behavior, Bash parsing, registry wiring, and hosted CI do not prove that Termux installed packages on a specific phone, SSH authentication succeeded, a remote host had tmux, Android preserved the process, the requested workspace attached, or the operator accepted the experience. Those require the exact phone-side bootstrap and observed local or remote attachment.
