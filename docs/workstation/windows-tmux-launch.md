# Windows tmux launch operator report

## The two commands

| Operator intent | Command | tmux contract | WezTerm contract |
|---|---|---|---|
| Continue the prior workspace/conversation | `Open-AgentSwitchboard-Continue.cmd` | Reuse `dev`; create it only when absent | Activate the existing marked Continue frontend when present; otherwise start one frontend |
| Start isolated work | `Open-AgentSwitchboard-New.cmd` | Create the first unused `dev-N`; never attach to an existing session | Start exactly one separate process with a unique workspace and window class |

These are deliberately different contracts. `wezterm` by itself is not an AgentSwitchboard launch command and may follow the default configuration back into the prior `dev` session.

## Install or refresh desktop launchers

From the AgentSwitchboard repository:

```powershell
Set-Location -LiteralPath (Join-Path $HOME 'Desktop\dev\AgentSwitchboard')
.\Install-AgentSwitchboard-Tmux-Launchers.cmd
```

The installer creates:

- `AgentSwitchboard - Continue Work.cmd`
- `AgentSwitchboard - New Instance.cmd`

in the Windows Desktop known folder. It preserves and reports legacy surfaces instead of deleting them.

## Validate before runtime

```powershell
Set-Location -LiteralPath (Join-Path $HOME 'Desktop\dev\AgentSwitchboard')
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\tooling\profiles\windows\Test-AgentSwitchboardTmuxLaunchers.ps1
git diff --check
```

## Runtime certificate

1. Record `wsl.exe -d Ubuntu -- tmux list-sessions -F '#S'`.
2. Click Continue twice. The second click must not start another marked Continue frontend.
3. Click New twice. The two clicks must create distinct first-unused sessions such as `dev-1` and `dev-2` and request distinct WezTerm processes.
4. Record the generated result JSON files under `%LOCALAPPDATA%\AgentSwitchboard\profiles\windows\runs`.
5. Do not promote proof above command acknowledgement until the windows and attachments are visibly observed.

## Known trap

Launching `wezterm` from PowerShell invokes the general WezTerm configuration. It is not equivalent to New Instance. When the default program attaches to `dev`, it will show the prior conversation by design.

## Failure handling

- Continue never falls back to New.
- New never falls back to Continue.
- No launcher kills or closes an existing session or process.
- A stale marked Continue frontend with a missing `dev` session blocks rather than creating a duplicate.
- Legacy CMD/LNK files remain non-authoritative until the operator removes them after live acceptance.

## Proof ceiling

Repository validation proves the two contracts are separately encoded and deterministic in Plan mode. Desktop installation proves file content and receipt generation. Only workstation observation proves visible-window activation, separation, layout, and operator acceptance.
