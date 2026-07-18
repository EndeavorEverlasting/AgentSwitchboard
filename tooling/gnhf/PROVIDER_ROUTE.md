# Provider-routed GNHF

## Root cause repaired by this contract

Merged installer/launcher code previously:

- hardcoded `gnhf@0.1.42` even when npm latest was `0.1.41` (`ETARGET`);
- required a GNHF `--model` flag that current CLI help does not define;
- aborted before installing provider launchers when runtime repair failed.

## Distribution decision

Prefer a **published** GNHF package that satisfies the capability matrix. Inject model selection through OpenCode (`OPENCODE_CONFIG_CONTENT` and bounded `opencode run --model` preflight). Pass GNHF `--model` only when the installed binary independently exposes that flag.

Do not infer npm publication from upstream `package.json`. Do not trigger repair solely because an unpublished source version string is newer.

## Operator repair

From the AgentSwitchboard repo root:

```text
Repair-ProviderRoutedGnhf.cmd
```

Or:

```powershell
pwsh -NoLogo -NoProfile -File .\tooling\gnhf\Install-ProviderRoutedGnhf.ps1 -Apply
```

## Installed capability contract

Child repositories consume:

```text
%LOCALAPPDATA%\AgentSwitchboard\GnhfFleet\gnhf-runtime-capability.json
```

Schema: `agentswitchboard.gnhf-runtime-capability.v1`

## Rollback

Each apply creates a timestamped backup under:

```text
%LOCALAPPDATA%\AgentSwitchboard\GnhfFleet\backups\provider-route-*
```

Restore backed-up launcher files and `state.json`, then rerun the repair command. Failed installs do not leave a ready capability document.

## Proof ceiling

This surface proves distribution discovery, capability readiness, synthetic installer behavior, and launcher contracts. It does not prove provider quota, long-running GNHF delivery, merge, or deployment.
