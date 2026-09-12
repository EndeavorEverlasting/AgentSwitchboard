# Android On-the-Move Runtime

AgentSwitchboard's Android profile is a **Termux + tmux + OpenAI Codex CLI implementation** for repository work from a phone. Codex is the coding agent; tmux remains the current session backend. The separate Herdr migration may later replace the session backend, but it does not select or replace the coding agent.

## Supported coding agent

The Android profile pins:

- coding agent: OpenAI Codex CLI
- version: `0.147.0`
- source/release tag: `openai/codex` `rust-v0.147.0`
- target: `aarch64-unknown-linux-musl`
- release asset: `codex-aarch64-unknown-linux-musl.tar.gz`
- exact asset size: `91607658`
- exact SHA-256: `eb677c80f666b1ab8b4b1d083b66e8d614b1281d960bb6f9fd8ca98f58b38b90`
- managed binary: `$PREFIX/lib/agentswitchboard/codex/0.147.0/codex`
- frontend: Termux
- persistence/session backend: tmux

The pin is tracked in `tooling/profiles/android/codex-runtime.json`.

The official Codex npm launcher explicitly recognizes Android ARM64 and maps it to the same `aarch64-unknown-linux-musl` native target. The corresponding optional native npm package is distributed with Linux OS metadata, however, so AgentSwitchboard does not make Termux installation depend on npm platform matching. Instead, the Android profile downloads the exact official OpenAI release asset, verifies its pinned byte size and SHA-256, rejects unsafe archive paths, verifies the extracted binary reports version `0.147.0`, and then installs that binary under an AgentSwitchboard-owned versioned path.

The installer does **not** overwrite an unrelated global `codex` command.

Android/Termux is still a **runtime-proof boundary**. Source and release compatibility do not prove that the Linux-musl binary, native sandbox, authentication, model calls, or tool execution work on this physical phone until the phone runs the corresponding gates.

## Entry point

From the repository root:

```bash
./Start-AgentSwitchboard-Android.sh status
./Start-AgentSwitchboard-Android.sh install
./Start-AgentSwitchboard-Android.sh login
./Start-AgentSwitchboard-Android.sh smoke
./Start-AgentSwitchboard-Android.sh proof-sprint
```

`install` installs the required Termux floor, downloads and verifies the exact pinned Codex release artifact, installs the managed binary, and creates `$PREFIX/bin/agentswitchboard-android` pointing back to the verified repository checkout.

With the wrapper installed:

```bash
agentswitchboard-android
```

opens or activates one tmux session named `agentswitchboard-android` and launches the profile-managed Codex binary from the AgentSwitchboard repository. Repeating the command converges on the same phone workspace instead of creating duplicate coding-agent sessions.

If an older `agentswitchboard-android` tmux session already exists but its foreground pane is not Codex, the launcher fails closed. Preserve any work in that old session and close it explicitly before starting the Codex-backed profile. The launcher never kills that session automatically.

## Login

Run:

```bash
agentswitchboard-android login
```

The launcher uses Codex's official device flow:

```bash
codex login --device-auth
```

The actual command is executed through the profile-managed Codex binary. Complete the browser authorization yourself. The device code is displayed only by Codex in the interactive terminal; AgentSwitchboard does not redirect it into runtime evidence. Do not put device codes, access tokens, API keys, passwords, recovery codes, or Codex credential files into Git, chat, QR payloads, shared documents, or evidence logs.

Read-only authentication/profile state is available through:

```bash
agentswitchboard-android status
```

## Read-only live smoke

After login, run the smoke from a tmux shell:

```bash
agentswitchboard-android smoke
```

The smoke command:

1. requires the exact managed Codex `0.147.0` binary;
2. requires Codex authentication;
3. requires a clean AgentSwitchboard checkout and a tmux shell;
4. runs the managed binary with `codex exec --json --ephemeral -s read-only`;
5. asks Codex to read `AGENTS.md` without modifying files;
6. stores stdout JSONL and stderr outside the repository.

A PASS requires all of these from the same run:

1. Codex exits zero;
2. `turn.completed` exists;
3. a completed zero-exit `command_execution` references `AGENTS.md`;
4. the final `agent_message` contains `ANDROID_RUNTIME_SMOKE=PASS`.

This reaches **live-agent-tool-behavior** proof only. It does not prove repository mutation or Herdr.

## Bounded writing sprint

For writing work, the launcher uses:

```text
codex exec --json --ephemeral --approve-for-me
```

`--approve-for-me` is the bounded automation surface chosen for Android: Codex keeps a `workspace-write` sandbox and routes approval requests through its automatic reviewer. AgentSwitchboard deliberately forbids the unsandboxed `--dangerously-bypass-approvals-and-sandbox` / `--yolo` path.

Run a repository-owned first certificate with:

```bash
agentswitchboard-android proof-sprint
```

The command:

1. requires clean `main`;
2. fetches and fast-forwards to `origin/main`;
3. creates a unique `feat/android-command-transport-<timestamp>` branch;
4. invokes Codex with the repository-owned bounded task in `tooling/profiles/android/runtime-proof-sprint.prompt.md`;
5. requires same-run `AGENTS.md` command evidence, a successful Codex `file_change`, a successful command execution, and the final completion marker;
6. independently requires a new clean commit, `git diff --check`, exact pushed remote-head equality, and an open PR;
7. writes runtime evidence outside Git.

A PASS reaches **live-agent-repository-mutation** proof.

If Codex's native sandbox cannot provide the required Android write boundary, treat that as a real runtime blocker. Do not solve it by enabling `--dangerously-bypass-approvals-and-sandbox`.

## General phone sprint

For the Herdr migration plan or later bounded work, put one self-contained sprint prompt in a file on an isolated non-`main` branch:

```bash
agentswitchboard-android sprint --prompt-file /path/to/sprint.md
```

The launcher refuses a dirty starting tree and refuses writing work on `main`. Codex receives the prompt in a 30-minute bounded run. The harness does not report success until the branch is committed, pushed, clean, exact-head matched to the remote, and associated with an open PR.

## Codex versus Herdr

Keep these responsibilities separate:

- **Codex**: coding/reasoning agent that reads, edits, validates, commits, and prepares PRs.
- **tmux**: current Android session/persistence backend.
- **Herdr**: experimental future session/backend migration lane.

Installing Codex does not promote Herdr. A later Herdr backend adapter should launch the same Codex agent contract rather than reintroducing Pi or hiding product behavior in prompts.

## Evidence

Local untracked evidence remains under:

```text
~/.local/state/agentswitchboard/android-runtime/
```

Key artifacts:

- `install-result.env`
- `last-open.env`
- `runs/<run-id>/events.jsonl`
- `runs/<run-id>/stderr.log`
- `runs/<run-id>/result.env`

JSONL can include repository text, commands, and task prompts. Keep it local.

## Proof ceiling

Repository and hosted CI can prove the Codex version/release pin, official ARM64 target identity, exact checksum/size contract, shell syntax, profile registration, sandbox/secret guardrails, and deterministic JSONL evidence rules. Only the intended physical Termux device can prove the release binary executes on Android, ChatGPT device authentication succeeds, the native sandbox works, a model responds, command/file tool behavior occurs, repository mutation succeeds, the tmux launcher is usable, or later Herdr-backed Codex operation works.
