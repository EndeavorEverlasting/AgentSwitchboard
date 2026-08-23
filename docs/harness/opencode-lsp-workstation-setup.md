# OpenCode LSP workstation setup harness

This harness gives a Windows operator or low-capability agent one path:

`resolve canonical checkout -> recover runtime -> inspect -> configure immutable local artifacts -> verify -> launch -> observe -> handoff`

It does not edit governance, AgentSwitchboard product launchers, existing OpenCode global/project/custom config, or credentials.

## Run from any PowerShell directory

The operator must not need to know, remember, or first navigate to an AgentSwitchboard checkout. The canonical bootstrap is `Invoke-AgentSwitchboardOpenCodeBootstrap.ps1`, and it is designed to run from any PowerShell directory, including another Git repository.

Use GitHub's repository-content endpoint so the initial command does not assume a local path or a remembered checkout. The endpoint follows the repository's configured default branch. The bootstrap then independently resolves the current remote default branch and exact HEAD, stages the checkout router/resolver from that exact SHA, verifies the resulting root by origin and HEAD, performs `Set-Location -LiteralPath` to the verified root, and only then dispatches runtime recovery.

```powershell
$u='https://api.github.com/repos/EndeavorEverlasting/AgentSwitchboard/contents/tooling/harness/operational/opencode-lsp-setup/Invoke-AgentSwitchboardOpenCodeBootstrap.ps1'; $r=Invoke-RestMethod -Uri $u; $s=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(($r.content -replace '\s',''))); & ([scriptblock]::Create($s))
```

Successful routing prints evidence such as:

```text
BOOTSTRAP_CALLER_LOCATION=<where the operator happened to start>
BOOTSTRAP_RESOLVED_ROOT=<verified AgentSwitchboard worktree>
BOOTSTRAP_VERIFIED_ORIGIN=https://github.com/EndeavorEverlasting/AgentSwitchboard.git
BOOTSTRAP_VERIFIED_HEAD=<current remote default-branch SHA>
BOOTSTRAP_ACTIVE_LOCATION=<same verified AgentSwitchboard worktree>
```

A wrong current directory is not an operator error. It is an untrusted candidate that the resolver ignores when its remote identity does not match. If no canonical local checkout is usable, the existing checkout resolver acquires an isolated canonical checkout under `%LOCALAPPDATA%\AgentSwitchboard` without deleting or rewriting the unrelated working directory.

`-Mode ResolveOnly` stops after checkout/root verification. The default `-Mode Recover` continues directly into focused OpenCode runtime recovery.

## Canonical routing

A fresh agent reaches this lane through `SKILLS.md`, `TRIGGERS.md`, and `tooling/harness/operational/workflow-registry.json`, then reads the focused manifest and workflows. The procedure is intentionally small: resolve identity first, configure only after the gates pass, preserve failure evidence, and never infer runtime success from configuration alone.

## Effective configuration

OpenCode merges multiple config sources. The Configure run writes an immutable fallback overlay under:

`%LOCALAPPDATA%\AgentSwitchboard\opencode-lsp\runs\<run-id>\opencode-lsp.overlay.json`

containing:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "lsp": true
}
```

The generated PowerShell launcher preserves an inherited `OPENCODE_CONFIG` path when one already exists. It also parses inherited `OPENCODE_CONFIG_CONTENT` in memory, preserves its keys, forces `lsp=true`, and passes that merged JSON only to the child OpenCode process. Inherited inline configuration is never copied to receipts or reports.

Configure never overwrites a prior non-empty output directory. If a caller points Configure at prior evidence, that directory remains untouched and the failure receipt/report are written to a fresh run instead. Every successful receipt therefore points to the exact immutable overlay and launcher pair that it validated.

## Interactive model selection

The launcher starts the OpenCode TUI with the current top-level `--model` option and the repository path. The default requested model is `opencode/nemotron-3-ultra-free`; it is selected per launch and is not persisted as the global model. Model visibility is checked against the provider prefix parsed from `provider/model`, so the bounded query matches the requested model namespace.

Free trial endpoints are for public/non-confidential material only. Do not submit credentials, customer data, private machine evidence, or confidential source.

## Server policy

Current stable OpenCode documentation says LSP is disabled by default and built-in servers start when a matching file is opened and requirements are met. For AgentSwitchboard, Pyright/Python and yaml-ls/YAML are useful low-friction paths. TypeScript remains conditional on a target project satisfying its requirements. The current built-in list has no PowerShell LSP, so PowerShell correctness remains owned by repository validators.

Current OpenCode V2 documentation says LSP config is accepted but has no runtime effect. The runner fails closed on a detected V2 version instead of reporting false success.

## Repository-local operator flow

Once the bootstrap has resolved and entered the verified root, repository-local entrypoints remain available:

```powershell
pwsh -NoLogo -NoProfile -File tooling/harness/operational/opencode-lsp-setup/Invoke-OpenCodeLspWorkstationSetup.ps1 -Mode Inspect -RepoPath .
pwsh -NoLogo -NoProfile -File tooling/harness/operational/opencode-lsp-setup/Invoke-OpenCodeLspWorkstationSetup.ps1 -Mode Configure -RepoPath .
```

Inspect and every expected failure write a local receipt/report. Configure additionally writes the immutable overlay and PowerShell/CMD launcher pair and validates their exact contents before returning `configured`.

To re-verify an existing Configure run without rewriting it:

```powershell
pwsh -NoLogo -NoProfile -File tooling/harness/operational/opencode-lsp-setup/Invoke-OpenCodeLspWorkstationSetup.ps1 -Mode Verify -RepoPath . -ConfigurationDirectory '<configure-run-directory>'
```

## Missing or unhealthy runtime recovery

`OPENCODE_NOT_FOUND` is owned by `Recover-OpenCodeRuntime.ps1`. The recovery is deliberately narrower than technician workstation setup:

- require Windows `LOCALAPPDATA` so runtime recovery and Inspect share exactly one AgentSwitchboard state/shim root;
- probe only the requested WSL distribution for an existing OpenCode command;
- initial discovery enumerates only `$HOME/.opencode/bin`, `$XDG_BIN_DIR` when present, `$HOME/bin`, and `$HOME/.local/bin`; inherited WSL `PATH` and arbitrary filesystem search are not runtime sources;
- validate any discovered command by its exact safe path and a bounded version probe;
- when OpenCode is absent or unhealthy, require existing `curl`, GNU `timeout`, and `grep` only; unrelated technician tooling is not installed;
- use the reviewed official installer from immutable upstream commit `anomalyco/opencode@3a31c4ea801915c0b050df4b3842997ea62b6e93`, rather than executing whatever happens to be on a mutable upstream branch later;
- download that exact commit-pinned installer to a temporary WSL file and verify before execution that it still contains the reviewed `INSTALL_DIR=$HOME/.opencode/bin` and `--no-modify-path` contract;
- execute that same pinned file with shell-profile mutation disabled and deterministic `SHELL=/bin/bash`; record installer source/exit evidence;
- do not rely on `OPENCODE_INSTALL_DIR`: the reviewed upstream installer owns its install directory internally;
- bound installer download/execution in Linux and again from the Windows parent process;
- after any ordinary installer attempt, judge its reviewed exact executable path `$HOME/.opencode/bin/opencode` before treating the coarse installer exit as terminal;
- a healthy exact-path binary may advance even when an installer postamble returned nonzero; missing, non-executable, timeout, native crash, and version failures remain typed failures;
- give that exact binary 30 seconds for `--version`, with a 10-second `--kill-after` deadline so a process that ignores SIGTERM still terminates and yields typed timeout evidence;
- persist only installer source commit, process-exit/output-presence evidence, exact path, typed health state, version exit code, and failure class. Raw OpenCode stderr, environment dumps, credentials, and inherited OpenCode configuration are not persisted;
- independently validate a healthy exact path with `--version` again before writing `%LOCALAPPDATA%\AgentSwitchboard\bin\opencode.cmd`; that reproof is the final shim-creation health gate;
- automatically re-enter Inspect through a bounded parent process after runtime recovery;
- do not install or repair unrelated agents such as AGY, Hermes, tmux, or WezTerm.

The default install timeout is 180 seconds. An immutable installer-source change requires an explicit repository update/review; a typed unhealthy native runtime is a named blocker, not a reason to broaden filesystem search or fall back to technician-wide setup.

## Runtime proof

After Configure, run the generated CMD, open a `.py` or `.yml` file, and observe OpenCode server/diagnostic behavior. Configuration proof is not LSP runtime proof.

## Troubleshooting

- starting PowerShell in the wrong repo or an arbitrary directory: use the location-free bootstrap above; do not ask the operator to find an AgentSwitchboard worktree first.
- `BOOTSTRAP_WRONG_REPOSITORY`: a resolved root failed canonical origin verification; unrelated folders are preserved.
- `BOOTSTRAP_HEAD_MISMATCH`: the acquired worktree does not match the freshly resolved remote default HEAD; stale proof is refused.
- `WRONG_REPOSITORY`: repository-local setup reached the wrong origin; route through the location-free bootstrap rather than manually navigating.
- `OPENCODE_NOT_FOUND`: runtime recovery repairs OpenCode only and must not delegate to broad command-shim/technician setup.
- missing `LOCALAPPDATA`: stop before recovery; the router will not create a shim under a different state root than Inspect uses.
- OpenCode only on inherited/system WSL `PATH`: recovery deliberately ignores it and installs/resolves a bounded user-local runtime before creating the canonical Windows shim.
- existing bounded `opencode` command but version exit nonzero/empty: recovery performs one bounded pinned official reinstall, then judges the official installer path rather than searching other locations.
- installer provenance needs updating: review the current upstream `anomalyco/opencode` installer, update the pinned source commit and contract together, and revalidate; do not silently switch recovery back to a mutable branch URL.
- `OPENCODE_INSTALLER_CONTRACT_DRIFT`: the pinned installer no longer matches the repository's reviewed install-path/no-profile-mutation assertions; stop before execution.
- `OPENCODE_POST_INSTALL_MISSING`: after the installer attempt, its reviewed executable path is absent.
- `OPENCODE_POST_INSTALL_NOT_EXECUTABLE`: after the installer attempt, its reviewed executable path cannot be executed.
- `OPENCODE_POST_INSTALL_VERSION_TIMEOUT`: the fresh binary or its final independent reproof did not complete within its bounded timeout.
- `OPENCODE_POST_INSTALL_CPU_INCOMPATIBLE`: the fresh binary produced a SIGILL-specific illegal-instruction/native CPU-compatibility signature.
- `OPENCODE_POST_INSTALL_NATIVE_CRASH`: the fresh binary produced a bus-error or segmentation-fault signature.
- `OPENCODE_POST_INSTALL_VERSION_FAILED`: the exact installer binary or final reproof returned another bounded nonzero/empty version result; the receipt records its exit code/failure class without persisting raw stderr.
- OpenCode recovery missing `curl`, GNU `timeout`, or `grep`: repair that prerequisite explicitly or use an already healthy OpenCode runtime; the focused router will not install unrelated technician tooling as a side effect.
- `OPENCODE_V2_LSP_UNAVAILABLE`: use repository lint/typecheck/test/PowerShell validators until upstream V2 supplies runtime support.
- `MODEL_ID_INVALID`: use `provider/model` format.
- `MODEL_NOT_VISIBLE`: connect/refresh the requested provider and rerun Inspect; never put credentials in repo/evidence.
- `LAUNCHER_MISMATCH`: do not hand-edit a generated run; create a new Configure run.
- `CONFIGURATION_DIRECTORY_ALREADY_OWNED`: use the default new run or an empty directory instead of overwriting old evidence.
- inherited inline config is invalid JSON: the generated launcher stops without changing the environment source.
- no PowerShell diagnostics: expected; current OpenCode built-ins do not include a PowerShell server.
- Pyright does not start: open a Python file and confirm its requirement can be resolved; do not install arbitrary packages merely to satisfy the harness.

## Validation

`Test-OpenCodeLspHarness.cmd` proves a usable Python 3 runtime, runs the focused harness plus cwd-independent-bootstrap contracts, runs PowerShell completeness and canonical documentation validation, and finishes with diff hygiene. Hosted Windows CI additionally starts from an unrelated temporary directory and executes `Invoke-AgentSwitchboardOpenCodeBootstrap.ps1 -Mode ResolveOnly` so current-working-directory independence is exercised as behavior rather than inferred from tokens.
