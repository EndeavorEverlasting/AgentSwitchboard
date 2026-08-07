# AgentSwitchboard Android Terminal Client — Termux Operator Guide

This is the practical first-run guide for an Android operator. It starts at the F-Droid screen and ends with a working Termux terminal-client installation, a phone-local tmux workflow, and a clear handoff to the SSH/tmux live-certificate guide.

For the cross-device procedure, continue with [`android-ssh-tmux-live-cert.md`](android-ssh-tmux-live-cert.md).

## Audience and outcome

Use this guide when you want to:

- install Termux through F-Droid without assuming prior Android terminal knowledge;
- prepare the phone-side Git, SSH, tmux, and curl package floor used by AgentSwitchboard;
- understand where files live inside Termux;
- install the tracked `agentswitchboard-phone` launcher from a reviewed AgentSwitchboard checkout;
- use phone-local tmux for local shell/code work;
- make local Git commits on the phone when the repository and credentials are already appropriate;
- use the phone as a terminal client for a separately classified remote workspace.

This guide does **not** claim that the Windows-first AgentSwitchboard orchestration runtime runs natively on Android.

## Current classification

The Android implementation is **`terminal-client-implemented`**.

The current role ceiling is:

- `local-shell-only` for phone-local tmux;
- `terminal-client` when attaching to a separately classified remote workspace host;
- native Android AgentSwitchboard orchestration: `unimplemented`;
- native Android agent/provider runtime: `unproved`.

Read `docs/governance/environment-capability-contract.md` before changing this classification or presenting Android as “AgentSwitchboard running on the phone.”

## Mental model: phone, transport, workspace

Keep these layers separate:

```text
phone screen + Termux
        |
        +-- phone-local shell/tmux ----> phone files only
        |
        +-- SSH -----------------------> remote workspace host
                                             |
                                             +-- remote tmux server/session
                                             +-- remote repository
                                             +-- separately proved orchestration/agents
```

A tmux session named `dev` on the phone and a tmux session named `dev` in WSL or on a server are **not the same session**. Cross-device continuity exists only when both clients attach to the same workspace host and the same tmux server/session identity.

---

# Part 1 — Install Termux from the F-Droid app

You already have F-Droid installed. Do the following on the **Android phone**, not on the laptop.

## 1. Open F-Droid and let its catalogue load

1. Tap the **F-Droid** app icon.
2. On a first launch, F-Droid may spend several minutes downloading its repository catalogue. Let that finish before assuming search is broken.
3. If the catalogue looks empty or stale, use F-Droid's refresh/update action and let it finish.
4. Tap the search control and search for **Termux**.

Official F-Droid documentation says the client downloads its repository on first launch. Termux's own installation documentation supports F-Droid as an installation source.

## 2. Choose the main Termux app

Open the app named **Termux** with package identity `com.termux` from the official F-Droid repository.

For this first setup, do **not** install Termux:API, Termux:Boot, Termux:Widget, Termux:Float, or other add-ons just because they appear in search. They solve different problems and are not required by the current AgentSwitchboard Android terminal-client profile.

If F-Droid shows more than one repository source for the app, use the official F-Droid source unless you deliberately maintain another trusted source. Do not mix Termux and its add-ons from incompatible signing sources.

## 3. Tap Install

1. Tap **Install** in F-Droid.
2. Android may ask whether F-Droid is allowed to install unknown apps. This is Android's sideloading permission for the F-Droid client.
3. If prompted, open that setting, allow **F-Droid** to install apps, then return to F-Droid.
4. Complete the Termux installation.
5. Tap **Open**.

You do not need to grant shared-storage access merely to keep source code under Termux's private `$HOME` directory.

## Expected first screen

Termux should open to a terminal prompt. The exact prompt text can vary. The important test is that you can type a command.

Run:

```bash
printf 'HOME=%s\nPREFIX=%s\n' "$HOME" "$PREFIX"
command -v pkg
```

Expected shape:

```text
HOME=/data/data/com.termux/files/home
PREFIX=/data/data/com.termux/files/usr
/data/data/com.termux/files/usr/bin/pkg
```

Exact Android app paths may vary by packaging details, so treat those lines as an example shape, not a machine-independent hardcoded path. The proof you care about is that `HOME` and `PREFIX` are populated and `pkg` resolves.

If `pkg` is not available, stop. You are either not in the expected Termux environment or the installation is incomplete.

---

# Part 2 — Learn the three Termux locations you actually need

Inside Termux:

- `$HOME` is your private user home. Keep repositories here by default.
- `$PREFIX` is the Termux-managed package prefix. The AgentSwitchboard bootstrap installs `agentswitchboard-phone` into `$PREFIX/bin`.
- `${XDG_STATE_HOME:-$HOME/.local/state}/agentswitchboard/android/` is where the Android profile writes untracked evidence and logs.

Useful commands:

```bash
pwd
printf '%s\n' "$HOME"
printf '%s\n' "$PREFIX"
ls -la "$HOME"
```

Do not copy Windows paths such as `C:\...` into Termux commands. Do not assume `/mnt/c/...` exists on Android; that is a WSL convention, not a Termux convention.

---

# Part 3 — Acquire the reviewed repository checkout

## Why there is a small bootstrap-acquisition step

The repo-owned bootstrap installs `git`, but the bootstrap script itself must first exist on the phone. AgentSwitchboard intentionally does not use an opaque `curl | sh` installer for this lane.

The safe acquisition pattern is:

1. install only the Git dependency needed to obtain the tracked source;
2. clone a reviewed AgentSwitchboard ref into Termux `$HOME`;
3. inspect and plan the repo-owned bootstrap from that checkout;
4. execute the bootstrap only when the reviewed ref is authorized for live-device use.

On the phone:

```bash
pkg install -y git
mkdir -p "$HOME/dev"
git clone https://github.com/EndeavorEverlasting/AgentSwitchboard.git "$HOME/dev/AgentSwitchboard"
cd "$HOME/dev/AgentSwitchboard"
git status --short --branch
```

Expected result: a clean checkout with an `origin` pointing at the canonical AgentSwitchboard repository.

Check the origin explicitly:

```bash
git remote get-url origin
```

Expected canonical HTTPS origin:

```text
https://github.com/EndeavorEverlasting/AgentSwitchboard.git
```

### Unmerged-PR warning

The Android terminal-client implementation may exist on a pull-request branch before it exists on `main`. Do not improvise a branch name or run arbitrary remote content. For PR evaluation, use the exact ref authorized by the review/live-cert lane. For normal operator installation after merge, use `main`.

---

# Part 4 — Plan the repo-owned bootstrap before mutating

From the reviewed checkout:

```bash
cd "$HOME/dev/AgentSwitchboard"
bash Bootstrap-AgentSwitchboard-Termux.sh \
  --repo "$HOME/dev/AgentSwitchboard" \
  --ref main \
  --plan
```

Expected shape:

```text
PLAN profile=android capability_status=terminal-client-implemented role=terminal-client ... packages=git,openssh,tmux,curl ... native_orchestration_runtime=unimplemented
```

The plan is intentionally non-mutating.

## Execution hold

Static validation or CI is not live-phone proof. Before running the mutating bootstrap against an unmerged PR, the operator must have an explicitly reviewed ref and must intentionally begin the live-device certification lane.

After the implementation is merged to the ref you are installing, the actual bootstrap command is:

```bash
cd "$HOME/dev/AgentSwitchboard"
bash Bootstrap-AgentSwitchboard-Termux.sh \
  --repo "$HOME/dev/AgentSwitchboard" \
  --ref main
```

The current bootstrap performs these bounded actions:

- installs `git`, `openssh`, `tmux`, and `curl` with `pkg`;
- clones the repository if absent, or fetches and fast-forwards an existing clean checkout;
- refuses an unexpected origin;
- refuses a dirty checkout;
- refuses a checkout on a different branch than `--ref`;
- syntax-checks the tracked Android launcher;
- installs it as `$PREFIX/bin/agentswitchboard-phone`;
- runs non-mutating command probes;
- writes `bootstrap-result.env` and bounded step logs.

Stable bootstrap failure exits are:

| Exit | Stage | Meaning |
|---:|---|---|
| 61 | package install | Termux package installation failed |
| 62 | repository clone | initial clone failed |
| 63 | repository fetch | fetch failed |
| 64 | fast-forward | existing checkout could not fast-forward cleanly |

On failure, inspect the log path printed by the bootstrap. The script prints the last 20 log lines rather than dumping unbounded output.

---

# Part 5 — Prove the installed phone-side capability ceiling

Run:

```bash
agentswitchboard-phone status
```

Expected fields include:

```text
profile=android
capability_status=terminal-client-implemented
role=terminal-client
frontend=termux
transport=ssh
local_tmux_role=local-shell-only
continuity_scope=device-local-only
cross_device_continuity=requires-remote-workspace-host
native_orchestration_runtime=unimplemented
native_agent_runtime=unproved
```

The status command also reports whether `bash`, `tmux`, `ssh`, and `git` are available. `available-unverified` means the command exists; it is not a live-runtime certificate.

Inspect bootstrap evidence:

```bash
cat "${XDG_STATE_HOME:-$HOME/.local/state}/agentswitchboard/android/bootstrap-result.env"
```

Important proof field:

```text
repo_purpose=source-and-terminal-client-files-not-runtime-proof
```

---

# Part 6 — Phone-local tmux: code locally without calling it remote continuity

Plan first:

```bash
agentswitchboard-phone local-shell --session phone-code --plan
```

Expected shape:

```text
PLAN ... role=local-shell-only mode=local-shell continuity_scope=device-local-only session=phone-code
```

Open or activate the session:

```bash
agentswitchboard-phone local-shell --session phone-code
```

Inside tmux, confirm the session identity:

```bash
tmux display-message -p 'session=#S socket=#{socket_path}'
```

Then enter the repository:

```bash
cd "$HOME/dev/AgentSwitchboard"
git status --short --branch
```

## Editing on the phone

AgentSwitchboard does not install a text editor on Android. If you want a simple optional editor, that is an operator-selected Termux package, not AgentSwitchboard runtime proof. For example:

```bash
pkg install -y nano
```

Then:

```bash
nano path/to/file
```

You may use another editor if you prefer. Keep editor choice separate from AgentSwitchboard capability claims.

## Local Git commit workflow

A phone-local Git checkout can make ordinary Git commits. Before committing:

```bash
git status --short
git diff --check
git diff
```

Stage only files you intend to own:

```bash
git add path/to/file
git diff --cached --check
git diff --cached
```

Commit:

```bash
git commit -m "docs: describe the change"
```

If Git says your author identity is missing, configure the identity you actually intend to use. Do not copy an example email address from documentation.

### Push boundary

The Android bootstrap does **not** create SSH keys, personal access tokens, credential helpers, or GitHub authentication. A local commit does not require network credentials. `git push` does.

If `git push` already works with credentials you deliberately configured, use the repository's normal branch/PR workflow. If authentication is not configured, stop at the local commit rather than pasting secrets into commands or logs.

---

# Part 7 — tmux basics you need on a phone

The tmux prefix is normally **Ctrl-b**.

Common actions:

- detach: press `Ctrl-b`, release, then `d`;
- list phone-local sessions: `tmux list-sessions`;
- reattach manually: `tmux attach-session -t phone-code`;
- show current session identity: `tmux display-message -p '#S'`.

A detached tmux session can keep processes alive while the Termux terminal view is detached, but Android can still impose application/process-lifetime limits. Do not treat a phone-local tmux server as the strongest always-on continuity boundary.

---

# Part 8 — Choose the next workflow

## Goal A: edit and commit locally on the phone

You can continue using:

```bash
agentswitchboard-phone local-shell --session phone-code
cd "$HOME/dev/AgentSwitchboard"
```

That proves a phone-local shell and repository workflow only. It does not prove native AgentSwitchboard orchestration or coding-agent/provider readiness.

## Goal B: continue the same durable workspace from laptop and phone

Use a **remote workspace host** and attach both devices to the same tmux server/session.

Continue with:

```text
docs/workstation/android-ssh-tmux-live-cert.md
```

The current repo-owned remote launcher supports only an explicitly selected POSIX/tmux SSH endpoint:

```bash
agentswitchboard-phone remote HOST \
  --host-profile posix-tmux \
  --repo /absolute/path/to/AgentSwitchboard \
  --expected-origin https://github.com/EndeavorEverlasting/AgentSwitchboard.git \
  --session dev \
  --plan
```

A Windows OpenSSH endpoint is **not** the same thing as this POSIX adapter. The live-certificate guide explains the supported path and the manual Windows-to-WSL transport check separately.

---

# Troubleshooting

## F-Droid opens but Termux does not appear

- Let the first repository refresh finish.
- Refresh F-Droid's catalogue.
- Search for the exact app name `Termux`.
- Confirm you are looking at the main `com.termux` app rather than an add-on.

## Android refuses the F-Droid install action

Android may require an “install unknown apps” permission for F-Droid. Grant that permission to F-Droid only if you intentionally use F-Droid as the installer. You do not need to grant the same permission to unrelated apps.

## `pkg` is missing

Stop. The commands in this guide assume the Termux package environment. Reopen the Termux app installed from the intended source and rerun:

```bash
printf 'HOME=%s\nPREFIX=%s\n' "$HOME" "$PREFIX"
command -v pkg
```

## Bootstrap says the checkout is dirty

Do not delete changes to make the bootstrap happy. Inspect them:

```bash
cd "$HOME/dev/AgentSwitchboard"
git status --short
git diff
```

Commit, stash, move to an isolated worktree, or otherwise preserve separately owned work before rerunning the bootstrap.

## Bootstrap says the origin is unexpected

Inspect it:

```bash
git remote -v
```

Do not automatically rewrite an unfamiliar origin. Confirm which repository you actually cloned.

## Phone-local tmux will not open

Check:

```bash
command -v tmux
tmux list-sessions 2>&1 || true
cat "${XDG_STATE_HOME:-$HOME/.local/state}/agentswitchboard/android/last-result.env" 2>/dev/null || true
```

If session creation failed, inspect:

```bash
cat "${XDG_STATE_HOME:-$HOME/.local/state}/agentswitchboard/android/local-session-create.log"
```

## SSH reports a host-key change

Stop and verify the remote host. The AgentSwitchboard launcher intentionally does not disable SSH host-key checking and does not contain `StrictHostKeyChecking=no`.

---

# Rollback

## Remove only the installed AgentSwitchboard phone launcher

```bash
rm -f "$PREFIX/bin/agentswitchboard-phone"
```

This does not remove the repository checkout or your Git history.

## Preserve the checkout while taking it out of the active path

From outside the repository:

```bash
mkdir -p "$HOME/dev/rollback"
mv "$HOME/dev/AgentSwitchboard" \
  "$HOME/dev/rollback/AgentSwitchboard-$(date -u +%Y%m%dT%H%M%SZ)"
```

This is safer than deleting a checkout whose local commits or untracked files you have not audited.

## Remove a phone-local tmux session

Only after confirming no needed work is running:

```bash
tmux kill-session -t phone-code
```

Uninstalling the Termux Android app is an Android-level action and can remove app-private data. Preserve repositories or commits you care about before doing that.

---

# Evidence and proof ceiling

Local untracked Android evidence lives under:

```text
${XDG_STATE_HOME:-$HOME/.local/state}/agentswitchboard/android/
```

Current artifacts:

- `bootstrap-result.env` — phone terminal-client installation evidence;
- `last-result.env` — last local or remote request boundary;
- `remote-preflight.env` — remote OS/shell, tmux, repository, origin, cleanliness, and session observations;
- `bootstrap-logs/` — bounded package/Git bootstrap logs.

Tracked code and CI can prove terminal-client contracts, argument validation, offline plans, fail-closed preflight logic, registry wiring, and forbidden proof promotion. They cannot prove that a particular phone installed Termux, that Android preserves a process indefinitely, that SSH authentication succeeds, that a particular remote host is ready, that both clients visibly attached to the same tmux session, that AgentSwitchboard orchestration runs on that host, or that an agent/provider route works.

---

# Repository validation

Static Android contracts:

```bash
bash -n Bootstrap-AgentSwitchboard-Termux.sh
bash -n tooling/profiles/android/Invoke-AgentSwitchboardOpenOrActivate.sh
bash tests/test_android_termux_profile.sh
python3 tests/test_android_termux_profile.py
python3 tests/test_android_termux_docs.py
```

Wider PowerShell gates where PowerShell is available:

```powershell
pwsh -NoLogo -NoProfile -File scripts/Test-EnvironmentCapabilityHarness.ps1
pwsh -NoLogo -NoProfile -File scripts/Test-DeviceProfileLauncherContract.ps1
pwsh -NoLogo -NoProfile -File scripts/Test-AgentDocumentationContract.ps1
```

Passing those validators proves the tracked contract. It does not replace the live-device certificate.

---

# External installation references

- F-Droid newcomer installation guide: <https://f-droid.org/en/docs/Get_F-Droid/>
- F-Droid Termux package page: <https://f-droid.org/en/packages/com.termux/>
- Termux upstream installation/readme: <https://github.com/termux/termux-app/blob/master/README.md>
