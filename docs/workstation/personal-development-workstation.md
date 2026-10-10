# Personal developer workstation — bootstrap

**Owner:** AgentSwitchboard Windows workstation profile
**Canonical machine/role identity:** [machine-profile bootstrap](machine-profile-bootstrap.md) and its `environment-role.registry.json`
**Machine-independent contract:** `tooling/profiles/windows/harness/machine-profile/personal-workstation-bootstrap.v1.json`
**Acceptance:** capability-specific evidence, not a green installer exit.

## Quick navigation

1. **Code-now:** install the minimum, then start Codex or Auggie.
2. **Full engineering station:** converge the existing AgentSwitchboard Windows/WSL fleet.
3. **Selective add-ons:** project SDKs, editors, local models, providers.
4. **Safety and verification:** protect local data and record true readiness.

## 1 — Code-now: first coding session

Choose your environment role explicitly: `desktop-workstation` or `personal-windows-laptop`. Never infer it from a remembered computer name, username, OneDrive, or drive letter.

In a standard Windows PowerShell session, install the small native foundation:

```powershell
winget install --id Microsoft.PowerShell --exact --source winget --accept-source-agreements --accept-package-agreements
winget install --id Git.Git --exact --source winget --accept-source-agreements --accept-package-agreements
winget install --id OpenJS.NodeJS.LTS --exact --source winget --accept-source-agreements --accept-package-agreements
winget install --id GitHub.cli --exact --source winget --accept-source-agreements --accept-package-agreements
```

Reopen PowerShell to refresh PATH; prove versions with `pwsh --version`, `git --version`, `node --version`, `npm.cmd --version`, `gh --version`. **Auggie requires Node major version 22 or higher.**

```powershell
npm.cmd install -g @openai/codex @augmentcode/auggie@latest
codex --version
auggie --version
```

Then authenticate interactively via `codex` (select ChatGPT sign-in if offered) and `auggie login`. These are distinct providers. Never store tokens in tracked files or Drive. **AGY / Google's Antigravity CLI is not Auggie.**

Select a clean, user-authorized repo, record its origin/branch/HEAD/dirty state, and have an agent perform a read-only orientation before granting writing scope. This is the **code-now acceptance gate**; don't delay it for Docker, WSL, Android SDK or restoration work.

## Full-profile one-shot coordinator (resumable)

For a full personal DTop restore, **the requested target is `engineering-full`**. The tracked, source-reviewed coordinator composes the existing canonical installers; it doesn't replace them. After a verified checkout is available, run it in two explicit modes:

```powershell
$repo = Join-Path $env:USERPROFILE 'dev\AgentSwitchBoard-Live'
powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo 'tooling\profiles\windows\Invoke-PersonalWorkstationProvision.ps1') -EnvironmentRoleId desktop-workstation -Profile engineering-full -Mode Inspect
# After inspecting the status and approving tool installation:
powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo 'tooling\profiles\windows\Invoke-PersonalWorkstationProvision.ps1') -EnvironmentRoleId desktop-workstation -Profile engineering-full -Mode Apply
```

The Apply mode is **opt-in**, verifies canonical Git origin, installs missing PowerShell 7/Git/Node LTS/GitHub CLI through approved WinGet package IDs, installs missing native Codex/Auggie through approved npm package IDs, then delegates Ubuntu repair and full AGY/OpenCode/WezTerm/GNHF setup to the pre-existing technician entrypoints. It never silently signs in to a provider, updates an existing Git checkout, deploys project code, or configures Windows activation. Existing working commands are observed rather than reinstalled. Missing PATH, UAC permission, Ubuntu first-user setup, installer errors and reboot are explicit **stop/resume** gates.

A new machine must first obtain the actual repository checkout, and Git must be available to prove its origin. The coordinator **does not secretly download or execute an unpinned remote script**. After any blocked step, repair exactly that step and rerun the same command; it produces an individual `provision-summary.json` under `%LOCALAPPDATA%\AgentSwitchboard\personal-workstation-bootstrap\runs\<runId>`.

**Proof after Apply:** local installation/version checks and the canonical technician receipt, not provider login, running a production agent task, the FirstMate crew runtime, Android SDK, Docker, Windows updates, or full-machine acceptance. It is expected to report `installed-awaiting-operator-gates` rather than falsely claiming the entire workstation is finished. If a separate optional SDK is needed for an active project, install it in the project-owned lane after the core fleet.

## 2 — Existing AgentSwitchboard fleet: full engineering station

AgentSwitchboard already owns the WinGet/WezTerm, WSL Ubuntu, tmux, AGY, OpenCode, Copilot CLI, and optional Hermes/Pi installation surfaces; **reuse them**. FirstMate under WSL owns the multi-agent crew runtime. GNHF is a bounded Windows launcher, not another crew orchestrator.

After Git and PowerShell 7 are working, resolve the machine-profile detector's canonical checkout (normally `%USERPROFILE%\dev\AgentSwitchBoard-Live` unless an explicitly verified alternative wins). Don't blindly clone over an existing checkout or pull into a dirty worktree.

If there is no checkout, acquire one:

```powershell
$repo = Join-Path $env:USERPROFILE 'dev\AgentSwitchBoard-Live'
if (-not (Test-Path -LiteralPath (Join-Path $repo '.git'))) {
  git clone https://github.com/EndeavorEverlasting/AgentSwitchboard.git $repo
}
git -C $repo remote get-url origin
git -C $repo status --short
git -C $repo rev-parse HEAD
```

Read-only discover the current role's CLI footprint:

```powershell
& (Join-Path $repo 'tooling\profiles\windows\Get-PersonalWorkstationBootstrapStatus.ps1') -EnvironmentRoleId desktop-workstation
```

On a laptop substitute `personal-windows-laptop`. The command only discovers names on PATH and writes a **local**, private JSON/Markdown status record. It does not prove versions, logins or functional runtime.

For the full fleet, check `wsl --status` / `wsl --list --verbose`. If Ubuntu is missing, follow `Repair-Technician-WSL-Ubuntu.cmd` in the same checkout; elevation, reboot and Linux-user setup may be required. Then run:

```powershell
& (Join-Path $repo 'Technician-AgentSwitchboard-Ready.cmd') setup
```

Verify the repo-owned readiness receipts in `%LOCALAPPDATA%\AgentSwitchboard\technician-ready\runs`. Use the distinct `tooling/gnhf/Test-AuggieReadiness.ps1` for Auggie ACP advertisement. No installer success means provider login, model access, TUI readiness or FirstMate crew validation.

## 3 — Conditional extensions

| Layer | Restore only when needed |
| --- | --- |
| Editing | Cursor, VS Code, Antigravity IDE; review restored extensions/settings. |
| Languages | Python/uv, Node/TypeScript, PowerShell, .NET, Rust, Go. |
| Android | Android Studio, JDK, SDK/platform-tools for an Android project; a different device's install is not proof here. |
| Containers | WSL-hosted tools or Docker only for repos that need them. |
| Agent overflow | Goose, Copilot, Gemini, Claude, optional Pi/Hermes, local Ollama/Qwen based on tested capability and provider access. |
| Remote delivery | GitHub auth first; Render/Neon/Resend integrations only under separate project authority. |

A secondary SSD is available for selectively chosen datasets, models and artifacts. **Don't silently move `%USERPROFILE%`, OneDrive, default repo binding, Docker data, or agent caches.** Never assume an `E:` letter exists across hosts.

## 4 — Safety / evidence / continuation

- Apply only to **personal** Windows desktop/laptop roles. Work Admin Boxes are excluded; their authorization is separate. Android/Termux is an SSH/tmux cockpit, not a home for provider secrets.
- Inspect existing installations before changes. Preserve dirty worktrees, backups, installer provenance, SSH trust, credential stores and ordinary Windows protections.
- Keep account enrollment and provider auth interactive. A local Windows account does not mean zero telemetry; don't automatically turn off Windows security or updates.
- Proof levels: profile designed → repo committed → synthetic contract validated → installed on target → CLI versions observed → provider authenticated → real repo task validated.
- Report missing runtime state honestly. Do not infer installed packages from an earlier machine's receipts.
- When an identical bootstrap failure recurs, repair the canonical harness/fixture, not a one-off chat paste.

**Authorities:** [AgentSwitchboard docs](../architecture/asb-firstmate-runtime-boundary.md) for owner boundaries; [technician setup](technician-agentswitchboard-ready.md); [Auggie probe](auggie-readiness.md); [Codex vendor docs](https://github.com/openai/codex); [Auggie vendor docs](https://github.com/augmentcode/auggie). Private machine proof belongs in the existing Drive hardware ledger; public reusable bootstrap contracts remain in Git.
