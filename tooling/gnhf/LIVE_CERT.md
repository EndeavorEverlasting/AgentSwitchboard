# AgentSwitchboard Live Cert

Operator-visible runtime proof for the V39 prompt-kit GNHF harness surface.

## Related V39 prompts

| Prompt | Role in this live cert |
| --- | --- |
| P37 | Exact agent/model spawn preflight before a long run |
| P38 / Blacksmith Compile | Bounded queue/compile stage used as the WezTerm smoke |
| P45 | AI-to-GNHF prompt compilation boundary |
| P47 | Committed harness workflow execution |
| P48 | Local generate/print/execute runtime |
| P49 | Environment configuration through AgentSwitchboard |

## One-click surfaces

### 1. Model-route matrix (PowerShell, optional WezTerm summary)

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass `
  -File .\tooling\gnhf\Start-LiveCertModelRouteProof.ps1 `
  -OpenWezTermWindows `
  -EnableSound
```

Probes listed DeepSeek models through Windows-safe OpenCode dispatch, classifies why each configuration works or fails, writes JSON/Markdown under:

```text
%LOCALAPPDATA%\AgentSwitchboard\GnhfFleet\logs\live-cert\
```

and mirrors the latest matrix to:

```text
%LOCALAPPDATA%\AgentSwitchboard\GnhfFleet\latest-live-cert-model-route-matrix.json
```

`-EnableSound` plays short console beeps for pass/fail so the operator can hear route outcomes while watching WezTerm.

### 2. WezTerm Blacksmith bounded compile sprint

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass `
  -File .\tooling\gnhf\Start-LiveCertWezTermSprint.ps1 `
  -Profile BlacksmithCompile `
  -AlsoRunModelMatrix `
  -EnableSound
```

Opens a native WezTerm window that runs:

```text
WezTerm -> pwsh -> Start-BlacksmithGuildNightShift.ps1 -Stage Compile
  -> Start-ProviderRoutedGnhfSprint.ps1
  -> OpenCode exact-model preflight
  -> GNHF isolated worktree
```

Compile is the bounded smoke profile (2 iterations / 180k tokens) from the BlacksmithGuild night-shift contract.

## Observed 2026-07-18 live cert

| Surface | Result |
| --- | --- |
| Model matrix | 4/4 DeepSeek models ready (`v4-pro`, `v4-flash`, `chat`, `reasoner`) |
| Windows dispatch | `pwsh-file` for OpenCode `.ps1` shim during matrix probes |
| WezTerm Compile launch | Opened; provider marker observed; GNHF sprint invoked |
| Compile delivery | **Blocked exit 79** — GNHF reported success with zero commits ahead of `6b61877` |
| Delivery gate | Harness correctly refused to treat process exit zero as proof |

Tracked sanitized matrix: `tooling/gnhf/fixtures/live-cert/model-route-matrix.observed.json`.

Operator-local evidence:

```text
%LOCALAPPDATA%\AgentSwitchboard\GnhfFleet\logs\live-cert\
%LOCALAPPDATA%\AgentSwitchboard\GnhfFleet\logs\provider-routes\*-blacksmithguild-night-compile.json
```

## Proof ceiling

- Model matrix proves authenticated marker response and Windows shim dispatch.
- WezTerm launch proves the operator-visible control surface started.
- Fail-closed exit 79 proves the commit-ahead-of-base delivery gate under live conditions.
- Blacksmith Compile still does **not** prove a committed queue/report until a later sprint repairs that objective or runtime.
- Excel for Web opening of the V39 workbook remains a separate field gate.
