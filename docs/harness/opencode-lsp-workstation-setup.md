# OpenCode LSP workstation setup harness

This harness gives a Windows operator or low-capability agent one path:

`resolve canonical checkout -> recover runtime -> inspect -> configure immutable local artifacts -> verify -> launch -> observe -> handoff`

It does not edit governance, AgentSwitchboard product launchers, existing OpenCode global/project/custom config, or credentials.

## Run from any PowerShell directory

The operator must not need to know, remember, or first navigate to an AgentSwitchboard checkout. The canonical bootstrap is `Invoke-AgentSwitchboardOpenCodeBootstrap.ps1`, and it is designed to run from any PowerShell directory, including another Git repository.

Use GitHub's repository-content endpoint so the initial command does not assume a local path or a remembered checkout. The initial API request is bounded to 30 seconds. The bootstrap then independently resolves the current remote default branch and exact HEAD once, stages `Resolve-AgentSwitchboardCheckout.ps1` from that exact SHA with a bounded download, and passes the same immutable branch/SHA directly to the bounded resolver child. There is no second head selection. If the branch advances after the snapshot is selected, the resolver continues only when the selected SHA remains an ancestor of the freshly fetched branch; a force-style rewrite that makes the snapshot unreachable fails closed. The worktree remains pinned to the originally selected SHA. After checkout recovery the bootstrap verifies the resulting root by origin, exact selected HEAD, and clean status, performs `Set-Location -LiteralPath` to that verified root, and only then dispatches bounded runtime recovery.

```powershell
$u='https://api.github.com/repos/EndeavorEverlasting/AgentSwitchboard/contents/tooling/harness/operational/opencode-lsp-setup/Invoke-AgentSwitchboardOpenCodeBootstrap.ps1'; $r=Invoke-RestMethod -Uri $u -TimeoutSec 30; $s=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(($r.content -replace '\s',''))); & ([scriptblock]::Create($s))
```

Successful routing prints evidence such as:

```text
BOOTSTRAP_CALLER_LOCATION=<where the operator happened to start>
BOOTSTRAP_DEFAULT_BRANCH=<current configured default branch>
BOOTSTRAP_EXPECTED_HEAD=<selected remote default-branch snapshot>
BOOTSTRAP_RESOLVED_ROOT=<verified AgentSwitchboard worktree>
BOOTSTRAP_VERIFIED_ORIGIN=https://github.com/EndeavorEverlasting/AgentSwitchboard.git
BOOTSTRAP_VERIFIED_HEAD=<same selected snapshot>
BOOTSTRAP_ACTIVE_LOCATION=<same verified AgentSwitchboard worktree>
```

A wrong current directory is not an operator error. It is an untrusted candidate that the resolver ignores when its remote identity does not match. If no canonical local checkout is usable, the existing checkout resolver acquires an isolated canonical checkout under `%LOCALAPPDATA%\AgentSwitchboard` without deleting or rewriting the unrelated working directory.

Remote Git resolution and exact-head staging default to 30-second bounds. The checkout child defaults to 120 seconds. Runtime recovery has its own internal deadlines plus a parent bootstrap deadline. Network or child-process stalls therefore return typed bootstrap failures instead of hanging indefinitely.

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

### Release-pinned retry after a missing binary

If the newest parseable runtime receipt for the requested WSL distribution proves `OPENCODE_POST_INSTALL_MISSING` after the reviewed installer returned nonzero, do not simply rerun the same install. `Retry-OpenCodeRuntimeWithPinnedRelease.ps1` owns one bounded retry for that exact state. It selects evidence only for the requested WSL distribution, atomically claims the source run before any release-network or installer mutation, resolves one semantic OpenCode release through the Windows host GitHub API, temporarily forwards only `VERSION` into WSL through `WSLENV`, and then re-enters the current canonical bootstrap. The reviewed installer source commit remains unchanged; only its already-supported explicit release input is supplied. Prior `VERSION`/`WSLENV` values are restored afterward.

The retry is location-free. Run it from any PowerShell directory:

```powershell
$u='https://api.github.com/repos/EndeavorEverlasting/AgentSwitchboard/contents/tooling/harness/operational/opencode-lsp-setup/Retry-OpenCodeRuntimeWithPinnedRelease.ps1'; $r=Invoke-RestMethod -Uri $u -TimeoutSec 30; $s=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(($r.content -replace '\s',''))); & ([scriptblock]::Create($s))
```

Before release lookup, the helper creates an atomic claim at `%LOCALAPPDATA%\AgentSwitchboard\opencode-lsp\retry-claims\<source-run-id>.claim` using create-new semantics; a collision fails closed with `OPENCODE_PINNED_RETRY_ALREADY_ATTEMPTED`. It then creates its own retry run directory under `%LOCALAPPDATA%\AgentSwitchboard\opencode-lsp\runs` and writes `opencode-release-pinned-retry.json` there. The artifact records only retry run ID, source run ID, requested distribution, selected release, attempt time, result run ID when unique, every new same-distribution result run ID, status, and the fact that no environment dump is persisted. It does not modify the source or resulting runtime-recovery runs.

Immediately before bootstrap dispatch, the helper verifies that the claimed source is still the newest runtime receipt for the requested WSL distribution. If a newer same-distribution receipt appeared concurrently, it fails closed with `OPENCODE_PINNED_RETRY_SOURCE_STALE` instead of installing against stale evidence. A runtime run already bound as the source or result of a retry artifact also fails closed with `OPENCODE_PINNED_RETRY_ALREADY_ATTEMPTED`; the failure workflow does not loop this repair indefinitely.

## Runtime proof

After Configure, run the generated CMD, open a `.py` or `.yml` file, and observe OpenCode server/diagnostic behavior. Configuration proof is not LSP runtime proof.

## Troubleshooting

- starting PowerShell in the wrong repo or an arbitrary directory: use the location-free bootstrap above; do not ask the operator to find an AgentSwitchboard worktree first.
- `BOOTSTRAP_GIT_TIMEOUT`: a Git operation exceeded its bounded window.
- `BOOTSTRAP_STAGE_DOWNLOAD_TIMEOUT`: exact-head resolver staging exceeded its bounded network window.
- `BOOTSTRAP_CHECKOUT_RECOVERY_TIMEOUT`: exact-head checkout resolution exceeded its bounded child-process window.
- `BOOTSTRAP_RUNTIME_RECOVERY_TIMEOUT`: focused runtime recovery exceeded its bounded parent window.
- `EXPECTED_HEAD_NO_LONGER_REACHABLE`: the branch changed after snapshot selection and the selected SHA is no longer an ancestor of the freshly fetched branch; the bootstrap refuses to reinterpret the requested snapshot.
- `BOOTSTRAP_WRONG_REPOSITORY`: a resolved root failed canonical origin verification; unrelated folders are preserved.
- `BOOTSTRAP_HEAD_MISMATCH`: the acquired worktree does not match the already selected remote snapshot; inconsistent proof is refused.
- `WRONG_REPOSITORY`: repository-local setup reached the wrong origin; route through the location-free bootstrap rather than manually navigating.
- `OPENCODE_NOT_FOUND`: runtime recovery repairs OpenCode only and must not delegate to broad command-shim/technician setup.
- missing `LOCALAPPDATA`: stop before recovery; the router will not create a shim under a different state root than Inspect uses.
- OpenCode only on inherited/system WSL `PATH`: recovery deliberately ignores it and installs/resolves a bounded user-local runtime before creating the canonical Windows shim.
- existing bounded `opencode` command but version exit nonzero/empty: recovery performs one bounded pinned official reinstall, then judges the official installer path rather than searching other locations.
- installer provenance needs updating: review the current upstream `anomalyco/opencode` installer, update the pinned source commit and contract together, and revalidate; do not silently switch recovery back to a mutable branch URL.
- `OPENCODE_INSTALLER_CONTRACT_DRIFT`: the pinned installer no longer matches the repository's reviewed install-path/no-profile-mutation assertions; stop before execution.
- `OPENCODE_POST_INSTALL_MISSING`: after a nonzero installer attempt, use the evidence-gated release-pinned retry above once rather than repeating the same moving release-discovery path inside WSL.
- `OPENCODE_PINNED_RETRY_ALREADY_ATTEMPTED`: this failure chain has already consumed or claimed its one host-selected-release retry; preserve the resulting evidence and diagnose that next typed gate rather than looping.
- `OPENCODE_PINNED_RETRY_SOURCE_STALE`: a newer runtime receipt for the requested WSL distribution appeared after the source was claimed; installer dispatch is refused rather than acting on stale evidence.
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

`Test-OpenCodeLspHarness.cmd` proves a usable Python 3 runtime, runs the focused harness, cwd-independent-bootstrap, and release-pinned-retry contracts, runs PowerShell completeness and canonical documentation validation, and finishes with diff hygiene. Hosted Windows/Ubuntu CI parses the retry entrypoint and runs its focused contracts; hosted Windows additionally starts from an unrelated temporary directory and executes `Invoke-AgentSwitchboardOpenCodeBootstrap.ps1 -Mode ResolveOnly` so current-working-directory independence is exercised as behavior rather than inferred from tokens. The smoke verifies that the same caller runspace ends at a canonical AgentSwitchboard root; the bootstrap itself proves that root is at the selected remote snapshot before returning success.
