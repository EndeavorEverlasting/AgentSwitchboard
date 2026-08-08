# First Android on-the-move editing sprint

Mission: turn the transport-independence governance already in `AGENTS.md` into a practical operator guide for cross-device command delivery.

Owned scope:
- create `docs/workstation/android-command-transport.md`;
- add the smallest useful link from `docs/workstation/README.md` if that file exists;
- documentation only.

Required content:
- one canonical plain-text command is the source of truth;
- copy/paste, careful manual entry, QR payloads, monitored live documents, and file artifacts are transport choices, not new authority;
- never place OAuth/device codes, tokens, passwords, recovery codes, or private SSH keys in QR/document/file transport;
- short commands are preferred for QR/manual transfer;
- long or quoting-sensitive actions should resolve a repository-owned launcher or versioned artifact with a digest rather than be split into unaudited QR chunks;
- live documents used as continuation channels require a freshness marker such as revision, timestamp, or digest;
- give a concrete Android/Termux example using `agentswitchboard-android status`, `smoke`, and `sprint --prompt-file`.

Validation:
- verify the new guide is linked if the workstation index exists;
- run `git diff --check`;
- run `python -m unittest tests.test_android_on_the_move_runtime` or `python3 -m unittest tests.test_android_on_the_move_runtime`;
- report the exact commands and results.

Delivery:
- commit with `docs(android): add cross-device command transport guide`;
- push the branch;
- open a PR to `main`;
- do not merge the PR yourself.
