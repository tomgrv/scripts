#!/bin/sh

# get the branch name whatever the form is
branch=$(git rev-parse --abbrev-ref HEAD)

# get the remote branch name
origin=$(git config --get branch.$branch.remote)

# Stash all changes, including untracked files, with a message
# Record the stash ref before/after so we only pop when something was stashed
# (a clean tree stashes nothing, and an unconditional pop would consume an
# unrelated, older stash entry).
before=$(git rev-parse -q --verify refs/stash 2>/dev/null)
git stash push -u -m "Stashing changes before aligning branch"
after=$(git rev-parse -q --verify refs/stash 2>/dev/null)

# Fetch the latest changes from the remote and align the branch
git fetch $origin
git branch -m $branch $branch-to-delete
if git checkout -b $branch $origin/$branch; then
    git branch -D $branch-to-delete
else
    zz_log e "Failed to checkout branch $branch from $origin/$branch"
    git branch -m $branch-to-delete $branch
fi
# Apply the stashed changes only if a new stash entry was created
[ "$before" != "$after" ] && git stash pop

# Print the current branch name
zz_log i "Current branch: $(git rev-parse --abbrev-ref HEAD)"
