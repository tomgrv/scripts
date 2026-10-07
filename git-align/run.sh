#!/bin/sh

branch=$(git rev-parse --abbrev-ref HEAD)
origin=$(git config --get branch.$branch.remote)

# Record the stash ref before/after so we only pop when something was stashed
# (a clean tree stashes nothing, and an unconditional pop would consume an
# unrelated, older stash entry).
before=$(git rev-parse -q --verify refs/stash 2>/dev/null)
git stash push -u -m "Stashing changes before aligning branch"
after=$(git rev-parse -q --verify refs/stash 2>/dev/null)

git fetch $origin
git branch -m $branch $branch-to-delete
if git checkout -b $branch $origin/$branch; then
    git branch -D $branch-to-delete
else
    zz-log e "Failed to checkout branch $branch from $origin/$branch"
    git branch -m $branch-to-delete $branch
fi
[ "$before" != "$after" ] && git stash pop

zz-log i "Current branch: $(git rev-parse --abbrev-ref HEAD)"
