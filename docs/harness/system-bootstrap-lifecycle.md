# Reversible system bootstrap lifecycle

AgentSwitchboard treats a machine-wide installer as incomplete unless it can also inspect and safely reverse the machine mutations it owns. The shared lifecycle is therefore:

```text
Inspect -> Apply -> Inspect/verify -> Remove -> Inspect/verify
```

OpenCode is the reference implementation. Pi and future system bootstrap adapters should consume the same lifecycle contract rather than inventing their own uninstall semantics.

## Canonical ownership state

Machine deletion authority lives under:

```text
%ProgramData%\AgentSwitchboard\bootstrap-lifecycle\<adapter-id>\state.json
```

This is deliberately machine-scoped. A receipt under `%LOCALAPPDATA%` is useful evidence, but it is **not** sufficient authority to delete machine-wide state because it may belong to a different user/profile or an incomplete historical run.

The durable state records an adapter ID, install ID, lifecycle status, original before-state, exact ASB-owned deltas, post-Apply fingerprints, backups required for restoration, and timestamps. State writes are atomic. If Apply or Remove is interrupted, the intermediate `applying` or `removing` status remains evidence for recovery rather than being silently treated as success.

## Canonical operations

Every registered system bootstrap adapter implements exactly these lifecycle operations:

- **Inspect** — non-mutating; report runtime presence, durable ownership, drift, and whether Remove is currently safe.
- **Apply** — ascertain first, snapshot the pre-ASB baseline, persist ownership state before reversible payload mutation, mutate only owned scope, verify convergence, and prove immediate Remove readiness.
- **Remove** — prove ownership and preflight all owned surfaces for drift before destructive rollback; reverse only recorded ASB deltas; verify rollback; become idempotently `removed`.

The common registry is `tooling/harness/system-bootstrap-lifecycle/adapters.v1.json`. New adapters are not lifecycle-complete until they register there with Inspect/Apply/Remove parity and pass the shared validator.

## Resource rules

### Dedicated files

If ASB creates a file, Remove may delete it only when its current fingerprint still matches the ASB-recorded post-Apply fingerprint. If ASB replaced a preexisting file, Apply must create and verify a backup before replacement; Remove restores that exact backup after verifying the current installed file has not drifted.

### Dedicated directories

An adapter never recursively deletes a directory merely because the path looks canonical. It removes an adapter-created directory only after owned files are reversed and the directory is empty.

### Machine PATH

Apply records whether an exact normalized entry already existed. Remove deletes the entry only when `addedByAsb=true`. Entries that predate AgentSwitchboard survive unbootstrap.

### Shared JSON configuration

Shared configuration uses property-level rollback. Apply records the previous presence/value of every property it changes. Remove first proves that the current property still equals the ASB-applied value, then restores only that property. Unrelated properties added or changed later are preserved.

The reference OpenCode adapter uses this for `lsp` and `$schema` in `%ProgramData%\opencode\opencode.json`.

### Shared AgentSwitchboard roots

Adapters may own adapter-specific descendants under AgentSwitchboard machine roots. No adapter may recursively remove a shared AgentSwitchboard root because another bootstrap adapter may also use it.

## Fail-closed removal

Presence is not ownership. If a target is present but durable machine ownership is missing, Remove stops instead of guessing.

Likewise, Remove stops **before rollback mutation** when an owned surface has drifted. Representative examples are:

- installed binary hash no longer equals the recorded post-Apply hash;
- required restoration backup is missing or changed;
- an ASB-owned shared-config property no longer equals the value ASB set;
- shared JSON became invalid or a competing JSONC owner appeared.

The operator can then inspect and reconcile the discrepancy without an automated uninstaller making the situation worse.

## User-state boundary

System bootstrap lifecycle ownership does not automatically extend to user state. Unless a separate explicit contract says otherwise, Remove never targets:

- provider credentials or OAuth state;
- API keys;
- sessions or chat history;
- project files or trust decisions;
- user model preferences;
- caches or logs outside an adapter-owned machine/runtime scope.

This makes "unbootstrap" mean **undo what AgentSwitchboard changed**, not "purge every trace of the third-party application from the computer."

## OpenCode reference commands

Apply:

```cmd
Bootstrap-OpenCode-SystemWide.cmd
```

Inspect:

```powershell
pwsh -NoLogo -NoProfile -File tooling/profiles/windows/Install-AgentSwitchboardOpenCode.ps1 -Mode Inspect
```

Remove:

```cmd
Unbootstrap-OpenCode-SystemWide.cmd
```

The OpenCode adapter journals machine ownership under `%ProgramData%\AgentSwitchboard\bootstrap-lifecycle\opencode`.

## Validation

```powershell
pwsh -NoLogo -NoProfile -File scripts/Test-SystemBootstrapLifecycleContracts.ps1 -RootPath .
python -m unittest tests.test_system_bootstrap_lifecycle -v
```

The PowerShell validator exercises the shared state and PATH helpers entirely in temporary test locations. Adapter-specific validators remain responsible for their own resource semantics.

## Adoption pattern for Pi and future agents

A new adapter should reuse `BootstrapLifecycle.psm1`, register in `adapters.v1.json`, persist state under its own adapter ID, and map its machine surfaces into the same resource classes. The adapter owns the details of its runtime/archive/configuration, while the shared lifecycle owns the meaning of ownership, drift, rollback, evidence, and terminal states.

This deliberately factors the **safety semantics**, not every installer command. Different tools can have different install layouts without inventing incompatible uninstall behavior.
