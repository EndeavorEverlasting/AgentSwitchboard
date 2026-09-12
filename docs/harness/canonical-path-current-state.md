# Canonical Path Seam — Current State

This is a human-readable harness report, not physical-workstation proof. Refresh repository/provider evidence and run the canonical path workflow on the target machine before promoting any local proof state.

## Working

- The machine-specific Windows path owner already exists at `tooling/profiles/windows/harness/machine-profile/machine-profile.registry.json`; P01 does not create a competing resolver.
- `tooling/harness/operational/canonical-path.contract.json` defines the cross-harness seam every app/profile harness must consume or explicitly mark N/A.
- Local repository-backed actions default to canonical path proof before mutation, validation/build/generation, launcher/updater use, or a workstation command handoff.
- Four proof states are independent: remote default branch containment, canonical development checkout currency, production/use path currency, and real operator entrypoint observation.
- Dirty/diverged/separately owned work is preserved; parallel/proof work uses an approved isolated worktree rather than a second mutable canonical clone.

## Broken / blocked

- The current main machine-profile resolver predates the deeper `pathRoles`/`NONCANONICAL_PRESERVE` repair proposed in draft PR #149. This P01 sprint deliberately does not copy that product/profile repair into a second owner.
- Hosted CI cannot prove a physical workstation's actual canonical checkout, installed/use path, or real entrypoint execution.

## Missing / unproven

- P92/PR #149 still owns deep Windows path classification/launcher enforcement and must be reconciled independently with the current default branch before integration.
- Each physical machine/profile remains UNPROVEN until its canonical path workflow resolves the roles and observes the required proof states.
- Runtime, provider, deployment, GUI/TUI, and user acceptance remain separate domain gates.

## Operator path

1. Read `AGENTS.md`, then `HARNESS.md`, then select the operational route.
2. Before a local repository-backed action, load `tooling/harness/operational/canonical-path.contract.json` and `.ai/skills/canonical-path-proof/SKILL.md`.
3. Resolve paths through the registered machine/profile owner; do not infer authority from the current working directory.
4. Refresh remote truth first, then safely fast-forward the canonical clean behind-only checkout or preserve it and use the approved isolated worktree.
5. Invoke the requested validator/build/launcher only from the proven path state and capture its receipt.

## Proof ceiling

This seam proves tracked path/proof contracts, discoverability, fail-closed path-sprawl policy, and hosted/static validation. It does not prove any particular physical workstation has adopted `main`, that a production/use path is current, or that a real operator entrypoint executed until those observations are made there.
