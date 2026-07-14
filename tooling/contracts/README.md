# AgentSwitchboard contracts

Machine-readable contracts that let independent workers exchange committed Git state without sharing an uncommitted checkout.

## Worker run record

- Schema: `worker-run.schema.json`
- Validator: `Test-WorkerRunContracts.ps1`
- Fixtures: `fixtures/worker-run.*.json`
- Doctrine: `../../docs/architecture/worker-interoperability.md`

Run from the repository root:

```powershell
pwsh -NoLogo -NoProfile -File .\tooling\contracts\Test-WorkerRunContracts.ps1
```

A `ready` or `integrated` record must identify a clean worktree, full commit SHAs, the produced head commit, passed validation evidence, and no unresolved conflicts. Executor and provider are separate fields so multiple clients consuming one exhausted provider are not misreported as independent capacity.
