# Repository Agent Contract Template

Copy this directory into a child repository, then replace all `REPLACE_*` values.

## Adoption steps

1. Pin the canonical contract version from `EndeavorEverlasting/AgentSwitchboard`.
2. Fill in the child repository mission, entry points, validation commands, artifact policy, and forbidden scope.
3. Add repository-specific skills under `.ai/skills/`.
4. Add nested `AGENTS.md` files only for stricter subtree rules.
5. Add a repository-local validator using `scripts/Test-AgentDocumentationContract.ps1` as the baseline.
6. Commit the adoption through a dedicated PR.
7. Never overwrite existing local rules without reviewing and merging them.

The copied contract is intentionally local and version-pinned. AgentSwitchboard updates do not mutate child repositories automatically.
