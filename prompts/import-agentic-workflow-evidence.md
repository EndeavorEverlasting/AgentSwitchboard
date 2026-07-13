# Import Agentic Workflow Evidence

EXECUTE THE REPOSITORY SPRINT. DO NOT STOP AT A PLAN OR REWRITE THIS PROMPT.

## Context

- **repo:** `EndeavorEverlasting/AgentSwitchboard`
- **branch:** `docs/agentic-workflow-architecture`
- **PR:** stacked architecture PR targeting `sprint/repository-floor-recovery` (expected PR #2)
- **sprint:** import agentic-workflow visual evidence and reconcile the canonical Mermaid architecture
- **lane:** docs / architecture / evidence
- **local evidence archive:** `C:\Users\Cheex\Desktop\dev\agents\Agentic Workflow.zip`

The branch already contains:

- `diagrams/agentic-software-factory.mmd`
- `docs/architecture/agentic-software-factory.md`
- an updated `README.md`

The source material is influenced by IndyDevDan's “Stop Loop Engineering. Start Agentic Engineering”:

`https://www.youtube.com/watch?v=VQy50fuxI34&t=1107s`

## Owned scope

- inspect every image in `Agentic Workflow.zip`;
- import useful original images into the repository as visual evidence;
- create a machine-readable evidence manifest;
- describe what each image actually communicates;
- compare the images against the existing Mermaid source and architecture document;
- correct the diagram or prose where the evidence requires it;
- preserve the distinction among engineers, agents, and deterministic code;
- validate, commit, push, and update the existing architecture PR.

## Forbidden scope

- do not modify `docs/repository-floor.md`, `reports/repository-floor.json`, or `scripts/Test-RepositoryFloor.ps1`;
- do not rewrite or force-push `main` or the repository-floor branch;
- do not redesign installers or agent adapters;
- do not claim that humans disappear from accountability;
- do not add ideas merely because they sound plausible;
- do not commit API keys, private configuration, machine-local paths, the source ZIP, temporary extraction folders, or generated caches;
- do not replace original screenshots with recreated approximations;
- do not merge either PR.

## Intended architecture claim

AgentSwitchboard should remove humans from **routine coding execution**, not from engineering ownership.

Humans remain responsible for:

- intent and acceptance criteria;
- constraints and risk budgets;
- policy exceptions and unsafe ambiguity;
- final acceptance when consequences justify review;
- designing and improving the software factory.

Agents own contextual reasoning and generative work. Deterministic code owns repeatable checks and transformations that should not consume tokens.

## Preflight

Run only enough preflight to avoid damaging local work:

```powershell
git status --short
git branch --show-current
git log --oneline --decorate -5
git remote -v
```

If the current worktree is dirty with unrelated changes, create an isolated worktree from `origin/docs/agentic-workflow-architecture`. Do not overwrite or stash another person's work.

Fetch the target branch when required:

```powershell
git fetch --prune origin
git switch docs/agentic-workflow-architecture
```

## Evidence import

1. Verify the archive exists and calculate its SHA-256.
2. Extract it under a temporary directory outside the repository.
3. Inventory all archive entries before copying anything.
4. Open and inspect every image. Do not infer content from filenames alone.
5. Import only relevant image files under:

```text
docs/evidence/agentic-workflow/source/
```

6. Use deterministic repository names such as:

```text
workflow-01.<ext>
workflow-02.<ext>
```

7. Preserve the mapping from original archive names to repository paths in:

```text
docs/evidence/agentic-workflow/manifest.json
```

The manifest must include:

```json
{
  "schema_version": "1.0",
  "source": {
    "archive_name": "Agentic Workflow.zip",
    "archive_sha256": "...",
    "reference_url": "https://www.youtube.com/watch?v=VQy50fuxI34&t=1107s"
  },
  "images": [
    {
      "original_name": "...",
      "repository_path": "docs/evidence/agentic-workflow/source/workflow-01.png",
      "sha256": "...",
      "width": 0,
      "height": 0,
      "description": "What is visibly communicated by this image",
      "architecture_concepts": ["engineer", "agent", "deterministic-code"]
    }
  ]
}
```

Do not include `C:\Users\...` or another machine-local absolute path in tracked files.

Create an evidence index at:

```text
docs/evidence/agentic-workflow/README.md
```

For each image, include the committed image, its evidence-backed interpretation, and the architecture section it supports. Separate direct visual evidence from your own inference.

## Diagram reconciliation

Inspect these files together:

```text
diagrams/agentic-software-factory.mmd
docs/architecture/agentic-software-factory.md
docs/evidence/agentic-workflow/manifest.json
docs/evidence/agentic-workflow/README.md
```

The canonical Mermaid must accurately show:

1. An engineer supplies intent, constraints, risk budget, and acceptance criteria.
2. A Factory Router selects a predefined ADW for work such as chores, features, or hotfixes.
3. Repository evidence and contracts inform planning and decomposition.
4. Each writing workflow runs in an isolated sandbox or worktree.
5. A build agent performs implementation.
6. Deterministic code runs formatter, linter, type, schema, policy, and similar checks.
7. Deterministic failures return to the responsible build agent, retaining the session where possible.
8. A specialized test agent executes or interprets focused validation without replacing deterministic test code.
9. Failed tests return summarized evidence to the build agent.
10. Successful work produces an evidence pack containing diff, checks, logs, artifacts, gaps, risks, and Git state.
11. Ambiguous, unsafe, destructive, or out-of-policy situations escalate to an engineer.
12. Engineers remain at acceptance and exception boundaries rather than inside every coding loop.

Do not draw agents as replacing deterministic code. Do not draw deterministic checks as free-form agent reasoning. Do not imply that routine code generation waits on a human after every step.

If image evidence conflicts with the existing diagram, update both the `.mmd` source and the embedded Mermaid block in the architecture document so they do not drift.

## Work preservation

Once the image import, manifest, and first coherent documentation update exist, checkpoint them before broad validation:

```powershell
git add docs/evidence diagrams/agentic-software-factory.mmd docs/architecture/agentic-software-factory.md
git commit -m "docs: import agentic workflow evidence"
```

The checkpoint is recoverability, not completion. Continue validation and make a bounded follow-up commit if corrections are required.

## Validation

Run the strongest practical checks available:

```powershell
git diff --check
Get-Content .\docs\evidence\agentic-workflow\manifest.json -Raw | ConvertFrom-Json | Out-Null
git status --short
git diff --stat origin/docs/agentic-workflow-architecture...HEAD
git diff origin/docs/agentic-workflow-architecture...HEAD
```

Additionally verify:

- every manifest path exists;
- every committed image opens successfully and its recorded dimensions match;
- every recorded SHA-256 matches the committed file;
- no ZIP or temporary extraction directory is tracked;
- no absolute local path or secret appears in the diff;
- the embedded Mermaid and standalone Mermaid encode the same nodes and routes;
- Mermaid renders with an already-installed renderer when available.

Do not install a large toolchain merely to render Mermaid. When `mmdc` is unavailable, record this exact skipped check:

```powershell
mmdc -i .\diagrams\agentic-software-factory.mmd -o "$env:TEMP\agentic-software-factory.svg"
```

## Commit and push

```powershell
git status --short
git diff --check
git add docs/evidence/agentic-workflow diagrams/agentic-software-factory.mmd docs/architecture/agentic-software-factory.md README.md
git commit -m "docs: reconcile agentic workflow evidence"
git push -u origin docs/agentic-workflow-architecture
```

Update the existing architecture PR body with:

- imported image count;
- archive SHA-256;
- exact files changed;
- diagram corrections made from evidence;
- validation commands and results;
- skipped Mermaid-render check, when applicable;
- remaining uncertainties.

## Required final report

Report:

- repository, branch, PR, lane, owned scope, and forbidden scope;
- exact image and documentation files added or modified;
- archive and image hashes;
- what the pictures directly establish;
- what remains an interpretation;
- Mermaid corrections;
- commands and results;
- skipped checks;
- commit SHA and push proof;
- final `git status --short`;
- one exact next command.

A final response without a commit SHA, exact blocker, or proof that no change was necessary is invalid.
