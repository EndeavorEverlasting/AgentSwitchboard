# Android On-the-Move Runtime

AgentSwitchboard's Android profile is a **Termux + tmux + Pi coding-agent implementation** designed for editing the repository from a phone without pretending that static contracts are runtime proof.

## Supported runtime

The pinned coding runtime is:

- package: `@earendil-works/pi-coding-agent`
- version: `0.82.1`
- Node.js floor: `22.19.0`
- frontend: Termux
- persistence: tmux
- provider login for the initial certificate: OpenAI ChatGPT Plus/Pro (Codex) through Pi's `/login` device flow

The runtime deliberately does not install Termux:API. Clipboard integration is optional and separate; the core workflow must remain usable through typed commands, ordinary paste, QR transport, monitored documents, or files.

## Entry point

From the repository root:

```bash
./Start-AgentSwitchboard-Android.sh status
./Start-AgentSwitchboard-Android.sh install
./Start-AgentSwitchboard-Android.sh login
./Start-AgentSwitchboard-Android.sh smoke
./Start-AgentSwitchboard-Android.sh proof-sprint
```

`install` also installs `agentswitchboard-android` into `$PREFIX/bin`, pointing back to the repository checkout at `$AGENT_SWITCHBOARD_REPO` or `~/dev/AgentSwitchboard`.

With the wrapper installed:

```bash
agentswitchboard-android
```

opens or activates one tmux session named `agentswitchboard-android` and runs Pi from the repository root. Repeating the command attaches to the same logical phone workspace instead of spawning duplicate agent sessions.

## Login

Run:

```bash
agentswitchboard-android login
```

Inside Pi, run `/login`, select **OpenAI ChatGPT Plus/Pro (Codex)**, and choose the device/headless flow when offered. Complete the browser authorization yourself.

AgentSwitchboard does not capture the one-time device code or Pi credential files. Never put those values into Git, a QR code, a shared document, or a runtime evidence log.

## Read-only live smoke

After login, exit the interactive Pi UI back to the tmux shell and run:

```bash
agentswitchboard-android smoke
```

The smoke command is bounded to five minutes and gives Pi only `read`, `grep`, `find`, and `ls`. It requires a clean repository, requires tmux, asks Pi to read `AGENTS.md`, and writes JSONL events outside the repository.

A PASS requires all of these from the same run:

1. Pi process exits successfully.
2. an `agent_end` event exists;
3. Pi issued a `read` tool call for `AGENTS.md`;
4. the `read` tool completed without error;
5. the assistant final message contains `ANDROID_RUNTIME_SMOKE=PASS`.

This is **live agent/tool behavior proof**, not repository mutation proof.

## First writing certificate

After the smoke passes:

```bash
agentswitchboard-android proof-sprint
```

The command:

1. requires clean `main`;
2. fetches and fast-forwards to live `origin/main`;
3. creates a unique `feat/android-command-transport-<timestamp>` branch;
4. invokes Pi with the repository-owned bounded task in `tooling/profiles/android/runtime-proof-sprint.prompt.md`;
5. requires successful `read`, `edit` or `write`, and `bash` tool events;
6. requires Pi's final completion marker;
7. requires a new commit, clean tree, `git diff --check`, pushed exact remote head, and an open PR;
8. writes the runtime evidence outside Git.

A PASS reaches **live-agent-repository-mutation** proof: an Android-hosted agent read the repository, changed tracked files, validated them, committed, pushed, and opened a PR. It still does not prove merge or downstream behavior until those gates are separately observed.

## General phone sprint

For later work, create an isolated branch and a prompt file, then run:

```bash
agentswitchboard-android sprint --prompt-file /path/to/sprint.md
```

The launcher refuses to write on `main`, refuses a dirty starting tree, bounds the Pi process to 30 minutes, and requires commit/push/PR evidence before it reports success.

## Evidence

Runtime evidence is local and untracked:

```text
~/.local/state/agentswitchboard/android-runtime/
```

Key artifacts include:

- `install-result.env`
- `last-open.env`
- `runs/<run-id>/events.jsonl`
- `runs/<run-id>/stderr.log`
- `runs/<run-id>/result.env`

JSONL can contain repository text and the sprint prompt. Treat it as local operational evidence; do not commit it.

## Proof ceiling

Hosted CI can prove script syntax, registration, static safety checks, and deterministic contracts. Only execution on the intended Android/Termux device can prove Termux package installation, Pi provider login, model response, tool execution, repository mutation, or operator usability.
