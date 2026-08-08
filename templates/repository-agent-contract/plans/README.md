# Public Plans

Every repository adopting the AgentSwitchboard contract should keep public machine-readable coordination under `plans/`.

A plan records mission, ownership, dependencies, collision boundaries, tasks, artifacts, validation, proof, and handoff. A branch or pull request transports reviewed changes; it is not the only coordination record.

Ordinary execution-coordination plans omit `coordinationMode`. When an effort is larger than one bounded session and the destination is known but the route is still unclear, a repository may use `coordinationMode.kind: decision-frontier` with decision tasks, derived frontier state, coarse `notYetSpecified` fog, destination-level `outOfScope`, and `executionAllowed: false` until a bounded execution handoff exists. The repository must pin and validate any external contribution manifest that supplied those semantics; the external donor does not become the repository's runtime authority.

Replace the placeholder registry entry when the first repository-specific plan is created. Never store credentials, customer data, machine-local paths, or raw runtime evidence here.
