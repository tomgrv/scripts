---
name: prod
description: >
  Cut a beta release, drive tests to green, then promote to prod. Runs
  `git release beta`, loops (run tests, fix failures, rerun) until green, then
  runs `git release prod`. Use when the user says "/prod", "release to prod",
  or "promote to production".
---

`git release beta` / `git release prod` are external commands (from `tomgrv/scripts`, fetched via `zz_use`) — assume they're already on `PATH`, don't reimplement them.

## Steps

1. `git release beta`. Stop and report if it fails (uncommitted changes, tag conflict, etc.) — don't force past a failed release cut.
2. Run the repo's test suite (bats suites under `src/*/tests/`, or whatever the repo's own CI/test command is).
3. If red: diagnose and fix the failing test(s) or the code they cover, minimal changes only. Commit the fix.
4. Rerun tests. Repeat steps 3-4 until green.
5. Once green, `git release prod`.

## Boundaries

Never skip, disable, or quarantine a failing test to force green — fix the root cause. Never run `git release prod` while any test is red. Never force-push or rewrite history to make step 1 succeed — investigate the failure instead.
