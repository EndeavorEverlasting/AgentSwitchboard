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

The durable state records an adapter ID, validated install ID, lifecycle status, original before-state, exact ASB-owned deltas, planned mutations, post-Apply fingerprints, per-resource rollback checkpoints, backups required for restoration, and timestamps. State writes are atomic. Lifecycle history filenames are built only from validated install IDs; path-bearing or dot-dot identifiers are rejected before a history path is constructed.

## Crash-safe mutation model

A reversible installer has two dangerous gaps: the instant after a machine resource changes but before ownership is journaled, and the instant after a rollback succeeds but before Remove finishes. The lifecycle contract closes both gaps.

### Apply write-ahead intent

Before a reversible resource mutation that could make ownership ambiguous after a crash, Apply persists enough intent to identify the exact planned ASB state. For example, a dedicated binary records its planned post-write SHA-256 before replacement.

If an `applying` lifecycle is resumed, the adapter may recover automatically only when the resource is provably in one of two states:

1. the recorded pre-ASB baseline, meaning the mutation did not complete; or
2. the exact planned ASB state, meaning the mutation completed before the interruption.

Any third state is drift and fails closed. A completed `installed` lifecycle is even stricter: a later Apply may not silently refresh hashes or otherwise re-baseline an owned resource that changed outside ASB.

### Remove checkpoints

Remove persists `rollbackComplete` immediately after each resource is verified at its pre-ASB state. A later resource failure therefore leaves durable progress. Retrying a lifecycle in `removing` resumes from the first incomplete resource instead of re-checking an already-restored resource against its old post-Apply value.

The OpenCode reference order is:

```text
managed configuration -> Machine PATH -> binary/runtime
```

The order is adapter-specific; the requirement to persist verified per-resource completion is shared.

## Canonical operations

Every registered system bootstrap adapter implements exactly these lifecycle operations:

- **Inspect** — non-mutating; report runtime presence, durable ownership, drift, interrupted lifecycle state, and whether Remove is currently safe.
- **Apply** — ascertain first, snapshot the pre-ASB baseline, persist write-ahead ownership intent before reversible payload mutation, mutate only owned scope, recover only provable interrupted states, verify convergence, and prove immediate Remove readiness.
- **Remove** — prove ownership, preflight incomplete owned surfaces for drift, reverse only recorded ASB deltas, checkpoint every verified rollback resource, verify final rollback, and become idempotently `removed`.

The common registry is `tooling/harness/system-bootstrap-lifecycle/adapters.v1.json`. New adapters are not lifecycle-complete until they register there with Inspect/Apply/Remove parity and pass the shared validator.

## Resource rules

### Dedicated files

If ASB creates a file, Remove may delete it only when its current fingerprint still matches the ASB-recorded post-Apply fingerprint. If ASB replaced a preexisting file, Apply must create and verify a backup before replacement; Remove restores that exact backup after verifying the current installed file has not drifted. Binary replacement should use a write-ahead expected hash so an interrupted Apply can distinguish a completed ASB write from unknown content.

### Dedicated directories

An adapter never recursively deletes a directory merely because the path looks canonical. It removes an adapter-created directory only after owned files are reversed and the directory is empty.

### Machine PATH

Apply records whether an exact normalized entry already existed and journals mutation intent before adding an ASB-owned entry. Remove deletes the entry only when `addedByAsb=true`, verifies absence, then checkpoints that rollback. Entries that predate AgentSwitchboard survive unbootstrap.

Windows PATH values are normalized as **Windows data** even when repository validators run on Linux; both `\` and `/` trailing separators are handled explicitly rather than inheriting the validator host's path semantics.

### Shared JSON configuration

Shared configuration uses property-level rollback. Apply records the previous presence/value of every property it changes and journals write intent before replacing the file. Remove first proves that the current property still equals the ASB-applied value, then restores only that property. Unrelated properties added or changed later are preserved. The restored property state is verified before the resource is checkpointed complete.

The reference OpenCode adapter uses this for `lsp` and `$schema` in `%ProgramData%\opencode\opencode.json`.

### Shared AgentSwitchboard roots

Adapters may own adapter-specific descendants under AgentSwitchboard machine roots. No adapter may recursively remove a shared AgentSwitchboard root because another bootstrap adapter may also use it.

## Fail-closed ownership and drift

Presence is not ownership. If a target is present but durable machine ownership is missing, Remove stops instead of guessing. This includes competing or alternate config surfaces such as an OpenCode `opencode.jsonc` even when the ordinary JSON file is absent.

Likewise, Remove stops before mutating an incomplete rollback resource when that resource matches neither the recorded ASB state nor a valid already-rolled-back state. Representative blockers are:

- installed binary hash no longer equals the recorded post-Apply hash;
- required restoration backup is missing or changed;
- an ASB-owned shared-config property no longer equals the value ASB set;
- shared JSON became invalid or a competing JSONC owner appeared.

A later Apply also refuses to turn this drift into a new trusted baseline. The operator can inspect and reconcile the discrepancy without an automated installer or uninstaller making the situation worse.

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

The PowerShell validator exercises atomic lifecycle-state persistence, history-ID confinement, SHA-256 helpers, and Windows PATH delta behavior entirely in temporary test locations. Adapter-specific validators remain responsible for resource mutation and recovery semantics.

## Adoption pattern for Pi and future agents

A new adapter should reuse `BootstrapLifecycle.psm1`, register in `adapters.v1.json`, persist state under its own adapter ID, and map its machine surfaces into the same resource classes. The adapter owns the details of its runtime/archive/configuration, while the shared lifecycle owns the meaning of ownership, write-ahead intent, interrupted-state recovery, drift, rollback checkpoints, evidence, and terminal states.

That is the pattern the parallel Pi implementation should emulate after reconciling against the shared lifecycle on `main`: **factor the safety semantics, not every installer command**. Different tools can have different install layouts without inventing incompatible uninstall behavior.
