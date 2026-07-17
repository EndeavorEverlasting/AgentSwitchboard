# Claude Code Adapter

Claude Code must read `AGENTS.md` first. This file adds Claude-specific operating guidance and does not replace or weaken the universal contract.

## Startup

1. Read `AGENTS.md` and the nearest nested `AGENTS.md`.
2. Read `SKILLS.md`, `CAPABILITIES.md`, and `TRIGGERS.md`.
3. Inspect the current branch, worktree status, recent commits, open PR context, and relevant validators.
4. Select the smallest applicable skill under `.ai/skills/`.
5. State the bounded sprint before writing.

## Claude-specific discipline

- Use repository search and symbol navigation before broad file reads.
- Delegate to subagents only when scopes are disjoint and each subagent has explicit inputs, outputs, and stop conditions.
- Do not let subagents share uncommitted files or claim work another subagent has not committed.
- Keep implementation in tracked source files; do not encode product behavior only in prompts or memory.
- Prefer deterministic commands for formatting, linting, typing, schemas, tests, Git inspection, and report rendering.
- Preserve the same repair context when a deterministic gate returns a correctable failure.
- Treat tool errors, unavailable integrations, and permission denials as evidence. Do not fabricate completion.
- Ask for human intervention only when repository evidence cannot safely resolve an ambiguity or when policy requires escalation.

## Proof language

Use precise proof labels:

- **contract proof** — required files, schemas, or rules exist and validate;
- **static test proof** — deterministic tests or analyzers pass without launching the product;
- **build proof** — the supported build completes;
- **harness proof** — synthetic or isolated workflow behavior is observed;
- **runtime proof** — the actual application or integration runs in the intended environment;
- **live-target proof** — behavior is observed against an authorized real target.

Never claim a higher level from a lower one.

## Forbidden shortcuts

- no direct writes to protected/default branches;
- no force-push or destructive cleanup without explicit authorization;
- no automatic merge, release, deployment, or live-target mutation;
- no secret retrieval or persistence unless explicitly authorized and safely handled;
- no broad refactor used to avoid a bounded fix;
- no plan-only response when a safe tracked sprint is available.
