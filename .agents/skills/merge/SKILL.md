---
name: merge
description: >
  Merge every open pull request this session created or is subscribed to that has
  green CI, in dependency order (base-branch chain first). Use when the user says
  "/merge", "merge my PRs", or "merge what's green".
---

Merge only PRs this session owns (created, or watching via `subscribe_pr_activity`). Never touch PRs opened by someone else.

## Steps

1. List candidate PRs: this session's created/subscribed PRs still open.
2. For each, check mergeability: CI green (all required checks passing), no merge conflict, no unresolved blocking review thread, Claude Approvals check (if repo runs one) passing.
3. Drop any PR that isn't green — leave it, don't force, don't fix it as part of `/merge` (that's the babysit/steward loop's job, not this command's).
4. Order the remaining green PRs by base-branch dependency: a PR whose base is another candidate PR's head merges after that one. Build the chain from the trunk (`develop`/`main`) outward.
5. Merge one at a time, in that order. After each merge, re-check the next PR in the chain still targets a valid base (GitHub retargets automatically when the base PR merges) and is still green before merging it.
6. Stop and report if a PR in the middle of the chain turns red or conflicts after an earlier merge — don't skip ahead.

## Report

One line per PR: merged (with number/link) or skipped (with reason: red CI, conflict, unresolved review, not in dependency order yet).

## Boundaries

Never merge a PR that isn't green. Never merge PRs outside this session's scope. Never force-merge, never bypass required checks or reviews.
