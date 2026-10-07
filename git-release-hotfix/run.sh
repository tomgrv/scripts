#!/bin/sh

cd "$(git rev-parse --show-toplevel)" >/dev/null

eval $(
    zz-args "Create HotFix branch" $0 "$@" <<-help
        r -         rebase      force rebase of current commits onto hotfix branch
        s -         stash       stash current staged changes before creating hotfix branch and reapply them after
help
)

# Get last vX.Y.Z tag on the main branch and replace the last number with 'X' (leading 'v' is kept)
main_tag=$(git describe --tags --abbrev=0 --match "v[0-9]*.[0-9]*.[0-9]*" main)

if [ -z "$main_tag" ]; then
    zz-log e "No tag found on main branch"
    exit 1
else
    zz-log i "Current version is $main_tag"
fi

hotfix=$(echo "$main_tag" | sed -E 's/([0-9]+)\.([0-9]+)\.([0-9]+)/\1.\2.X/')

# Capture develop's tip before we potentially checkout the hotfix branch
# below, so the rebase-safety check further down always evaluates develop
# itself rather than whatever branch happens to be checked out at the time.
develop_rev=$(git rev-parse develop)

# Idempotent: reuse the hotfix branch if a previous run already created it,
# instead of failing on `git flow hotfix start`.
resumed=""
if git show-ref --verify --quiet "refs/heads/hotfix/$hotfix"; then
    resumed=true
    zz-log i "Hotfix branch hotfix/$hotfix already exists, resuming"
    if [ "$(git branch --show-current)" != "hotfix/$hotfix" ] && ! git checkout "hotfix/$hotfix"; then
        zz-log e "Cannot switch to hotfix/$hotfix"
        exit 1
    fi
fi

if [ -n "$rebase" ]; then
    zz-log i "Rebase forced via command line option, will rebase commits onto hotfix branch"
elif git log --reverse --pretty=oneline --format=%B develop --not origin/develop --no-merges | grep -vE "^$|^fix(\(.+\))?:" >/dev/null; then
    zz-log w "There are commits since $main_tag that are not of type 'fix:', creating hotfix branch only"
    unset rebase
else
    zz-log i "All commits since $main_tag are of type 'fix:', creating hotfix branch and rebasing current history + stash on top of it"
    rebase=true
fi

# If rebase needed, check that develop branch has not been pushed since last
# tag and that its tip isn't a merge commit -- either makes it unsafe to reset
# develop back to the main tag afterwards. Refresh the remote-tracking ref
# first so a stale local origin/develop can't mask the first case, and check
# develop's captured tip explicitly (not HEAD, which may now be the hotfix
# branch if this run resumed an already-created one).
if [ -n "$rebase" ]; then
    if ! git fetch origin develop >/dev/null 2>&1; then
        zz-log e "Cannot fetch develop branch from remote"
        exit 1
    fi
    if [ "$develop_rev" = "$(git rev-parse origin/develop)" ] || [ "$(git rev-list --parents -1 "$develop_rev" | wc -w)" -gt 2 ]; then
        zz-log e "Develop branch has already been pushed or its tip is a merge commit, cannot rebase safely, aborting"
        exit 1
    fi
fi

# Idempotent: reclaim a stash left over from an interrupted previous run
# instead of stashing again on top of it or leaving it stuck.
pending_stash=$(git stash list | grep -m1 "Hotfix stash:" | cut -d: -f1)

if [ -z "$resumed" ]; then
    if [ -n "$(git status --porcelain)" ]; then
        zz-log w "Working directory is not clean. Stashing staged changes before creating hotfix branch..."
        git stash save -k -m "Hotfix stash: $(date +%Y-%m-%d-%H-%M-%S)"
        pending_stash=$(git stash list | grep -m1 "Hotfix stash:" | cut -d: -f1)
    else
        zz-log i "Working directory is clean, no need to stash changes"
    fi
elif [ -n "$pending_stash" ]; then
    zz-log i "Found stash left over from a previous run ($pending_stash), will reapply it"
fi

export GIT_EDITOR=:

# Bail out if it fails, so we don't pop the stash or rebase onto the wrong branch.
if [ -z "$resumed" ] && ! git flow hotfix start "$hotfix"; then
    zz-log e "Failed to start hotfix branch $hotfix"
    exit 1
fi

# Idempotent: no-op when there is no pending stash.
if [ -n "$pending_stash" ]; then
    zz-log i "Applying stashed changes ($pending_stash)..."
    if ! git stash pop --index "$pending_stash"; then
        zz-log e "Stash pop had conflicts. Resolve them, then re-run this command to continue."
        exit 1
    fi
fi

# Naturally idempotent: only moves commits still ahead of the hotfix branch,
# so a re-run after everything already moved is a no-op.
if [ -n "$rebase" ]; then
    zz-log i "Rebasing develop commits onto hotfix branch..."
    git fix base -p "hotfix/$hotfix" develop
fi
