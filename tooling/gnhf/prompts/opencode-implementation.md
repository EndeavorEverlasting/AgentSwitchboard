LANE: OpenCode implementation.

REPO:
Use the current repository and the isolated GNHF worktree.

OWNED SCOPE:
- tooling/gnhf/
- scripts/core/
- installers/

FORBIDDEN SCOPE:
- main or release branch mutation
- force-push, merge, deployment, or remote deletion
- secrets, credentials, user data, generated runtime logs, or machine-local files
- unrelated refactors
- documentation-only output when implementation is safe

OBJECTIVE:
Execute one bounded implementation sprint. Recover current repository truth from tracked instructions, recent commits, tests, validators, and existing patterns. Make useful tracked changes within owned scope.

WORK LOOP:
1. Inspect only enough evidence to choose the smallest useful slice.
2. Implement the slice.
3. Checkpoint coherent tracked progress before broad validation.
4. Run targeted tests, validators, static checks, and build checks that apply.
5. Repair failures without expanding scope.
6. Leave each successful iteration as a coherent commit.

EVIDENCE:
Do not claim success without command output and final Git state. Record skipped checks and exact reasons in the GNHF notes.

STOP ONLY WHEN:
The bounded implementation is committed, targeted validation passes, no unrelated files changed, and the branch contains at least one useful commit.
