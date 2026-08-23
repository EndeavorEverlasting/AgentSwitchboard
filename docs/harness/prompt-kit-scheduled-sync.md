# Prompt Kit scheduled website sync

AgentSwitchboard can keep a local, validated copy of the canonical Prompt Kit website from `EndeavorEverlasting/web-excel-repair-triage` on Windows. The feature is **off by default**. Nothing is scheduled and no Prompt Kit network poll occurs until the user explicitly enables it.

## Operator commands

From an AgentSwitchboard checkout:

```bat
PromptKit-Website-Sync.cmd Status
PromptKit-Website-Sync.cmd Enable -IntervalMinutes 60
PromptKit-Website-Sync.cmd Run
PromptKit-Website-Sync.cmd Open
PromptKit-Website-Sync.cmd Disable
```

`Enable` is the consent boundary. It writes an enabled local config, installs a stable runtime copy under `%LOCALAPPDATA%\AgentSwitchboard\prompt-kit-sync\runtime`, and registers `AgentSwitchboard-PromptKitWebsiteSync` for the current interactive Windows user at limited privilege. The default interval is 60 minutes; the minimum accepted interval is 15 minutes. The repeating trigger is registered with a ten-year duration rather than an unbounded daemon lifetime, and re-running `Enable` refreshes that horizon. The scheduled task never opens a browser.

`Enable` writes `enabled=true` only after Task Scheduler registration succeeds, so a failed installation cannot leave polling logically enabled. `Disable` writes `enabled=false` **before** unregistering the task. The poller checks this toggle before its first Git/network operation, so polling remains stopped even if local policy prevents task removal.

## What is polled

The source of truth is the triage repository's actual remote default branch. Each enabled poll runs `git ls-remote --symref` and treats the returned exact commit SHA as the version identity. It does not infer freshness from timestamps, filenames, page contents, or a remembered `main` branch.

When the SHA is unchanged and the previously published site's SHA-256 still matches local state, the run is a no-op. When a newer head exists or the local published copy needs repair, AgentSwitchboard updates its **own managed source checkout** only by fetch plus fast-forward. A dirty checkout, unexpected origin, changed branch, or non-ancestor/diverged state fails closed; the poller never uses `git reset`, `git clean`, or a checkout overwrite to recover.

The user's normal `web-excel-repair-triage` development checkout is not discovered or mutated by this feature.

## Validation and extraction

Before publishing a changed site, the poller verifies the upstream generator manifest and runs the triage repository's canonical exact-output check:

```text
scripts/build_prompt_kit_registry.py --output web/prompt-kit/index.html --check
```

Only after that check succeeds does AgentSwitchboard copy `web/prompt-kit/index.html` into an immutable local release directory keyed by the exact source commit SHA. It records the website SHA-256 and path in `state.json`. `Open` resolves that recorded path rather than guessing a checkout location.

Local runtime state lives under:

```text
%LOCALAPPDATA%\AgentSwitchboard\prompt-kit-sync\
  config.json
  state.json
  last-run.json
  sync.lock
  runtime\Sync-PromptKitWebsite.ps1
  source\web-excel-repair-triage\
  website\releases\<source-sha>\index.html
```

The website cache retains two SHA-addressed releases by default. Cleanup is restricted to 40-hex release directories inside this AgentSwitchboard-owned cache. No credentials, raw user prompts, or developer checkout content are copied into AgentSwitchboard state.

## Profile behavior

The feature is machine-local and user-local rather than hard-coded to one named workstation. That makes the same control usable on an admin box, a personal Windows profile, or another Windows machine. Enabling it on one machine does not enable it on another. This deliberately keeps the permission/toggle decision at the computer where the schedule will execute.

## Failure behavior and proof boundary

`last-run.json` records a compact success, no-op, lock-held, or failure receipt. A failure does not replace the last known good website. Concurrent polls are suppressed with an exclusive local lock, and Task Scheduler is configured to ignore a new instance while one is running.

Repository tests prove the tracked consent/safety/update contracts and parse the PowerShell scripts on Windows. They do not prove that a particular workstation can reach GitHub, register Scheduled Tasks under its local policy, execute the triage generator with its installed Python, or open the browser. Those are runtime acceptance checks on the target Windows machine.
