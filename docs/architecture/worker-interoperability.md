# Worker interoperability contract

AgentSwitchboard treats Git isolation and work dependencies as separate concerns.

## Operating rule

Every concurrently active worker receives its own branch and worktree. Workers never share uncommitted state. A later worker may consume another worker's committed contribution when that dependency is explicit in a worker run record.

```text
base commit
  ├─ worker A worktree → commit A
  ├─ worker B worktree → commit B
  └─ integration worktree consumes A and B in declared order
```

Lanes describe responsibility, such as implementation, validation, integration, or runtime proof. They are not permanent walls. Once a contribution is committed and recorded, another worker may branch from it, cherry-pick it, merge it, or supersede it according to repository doctrine.

## Canonical record

`tooling/contracts/worker-run.schema.json` defines the portable handoff between an executor, GNHF, AgentSwitchboard, and a future integration worker.

A record must identify:

- the repository and isolated worktree;
- executor, provider, and lane as separate facts;
- branch, base SHA, head SHA, and dirty state;
- owned and forbidden scope;
- parent runs and consumed commits;
- changed files and produced commits;
- exact validation commands, statuses, and evidence;
- summary and log paths;
- integration status and conflicts.

The provider field is intentionally separate from the executor. Hermes using Copilot, for example, is one executor consuming one provider entitlement, not two independent capacity sources.

## Dependency rules

1. Uncommitted work is never consumed across workers.
2. Every consumed commit is a full 40-character SHA.
3. Parent run IDs declare provenance; consumed commit SHAs declare the actual Git material inherited.
4. A record marked `ready` or `integrated` must describe a clean worktree, no known conflicts, a head commit listed in `changes.commits`, and at least one passed validation with no failed validation.
5. A superseded record identifies the replacement run.
6. Integration order is explicit. No executor silently decides the repository-wide dependency graph.

## Integration authority

AgentSwitchboard owns interoperability between worker branches. GNHF may manage retries, commits, and rollback within one assigned worktree, but it does not own the cross-worktree dependency graph.

A future integration worker should:

1. read completed worker run records;
2. verify branches and SHAs;
3. topologically order declared dependencies;
4. create one integration worktree;
5. apply commits deterministically;
6. stop with exact conflict evidence when reconciliation is unsafe;
7. run combined validation;
8. emit a final integration report.

No integration worker may force-push, merge the default branch, deploy, or erase user work by default.

## Validation

Run the deterministic contract checks from PowerShell 7:

```powershell
pwsh -NoLogo -NoProfile -File .\tooling\contracts\Test-WorkerRunContracts.ps1
```

The validator parses the schema and fixtures, enforces SHA and readiness semantics, and proves that malformed commit identities and dirty `ready` records are rejected. It does not create worktrees, launch agents, contact providers, or mutate another repository.
