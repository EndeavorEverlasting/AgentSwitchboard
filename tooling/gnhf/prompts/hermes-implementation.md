LANE: Hermes implementation.

REPO:
Use the current AgentSwitchboard repository and the isolated GNHF worktree.

OWNED SCOPE:
- tooling/hermes/
- docs/integrations/hermes/
- tests/hermes/

FORBIDDEN SCOPE:
- main or release branch mutation
- force-push, merge, deployment, remote deletion, or provider billing changes
- secrets, credentials, user data, generated runtime logs, or machine-local files
- unrelated agent adapters or broad architecture rewrites
- unsupported claims that authentication, provider quota, or live inference succeeded

OBJECTIVE:
Execute one bounded Hermes integration sprint. Recover repository truth from tracked instructions, recent commits, tests, validators, and existing AgentSwitchboard patterns. Implement the smallest useful Hermes-specific slice within owned scope.

WORK LOOP:
1. Inspect only enough evidence to choose a bounded slice.
2. Reuse existing adapter, logging, readiness, and worktree patterns.
3. Implement real behavior rather than a placeholder.
4. Run targeted tests, validators, static checks, and build checks that apply.
5. Repair failures without expanding scope.
6. Leave successful work as a coherent commit.

VALIDATION:
- run the narrowest Hermes-specific checks first
- run relevant shared AgentSwitchboard validators
- record exact commands and results
- name skipped checks and their exact future commands
- show final git diff/status evidence

STOP ONLY WHEN:
The bounded Hermes change is committed, targeted validation passes, no unrelated files changed, and the branch contains at least one useful commit.
