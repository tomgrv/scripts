#!/bin/sh

# Handle parameters
eval $(
    zz_args "Delete a specified commit and rebase subsequent history" $0 "$@" <<-help
        f -         force       allow overwriting pushed history
        p -         push        push to remote after deletion
        a -         auto        fully automatic mode - no prompts
        s strategy  strategy    strategy to use for conflict resolution (default: theirs)
        - sha       sha         sha commit to delete
help
)

# Set defaults and navigate to repository root
strategy="${strategy:-theirs}"
cd "$(git rev-parse --show-toplevel)" >/dev/null
git fetch --progress --prune --recurse-submodules=no origin >/dev/null

# Check for ongoing rebase
if git isRebase; then
    zz_log e 'Rebase is in progress, please finish or abort it first.'
    exit 1
fi

# Get and validate commit
sha=$(git getcommit $force $sha)
if ! git rev-parse --verify "$sha^" >/dev/null 2>&1; then
    zz_log e "Cannot delete commit $sha (invalid or initial commit)."
    exit 1
fi

zz_log i "Deleting commit: $sha"

# Attempt deletion with fallback to autorebase
if ! git autorebase ${auto:+-a} -s "$strategy" -o "$sha^" "$sha"  ; then
        zz_log e "Failed to delete commit $sha. Please resolve conflicts manually."
        exit 1
else
    zz_log s "Commit deleted with conflict resolution"
fi

# Push if requested
if [ -n "$push" ] && git rev-parse --verify --quiet origin/HEAD >/dev/null; then
    zz_log i "Pushing to remote..."
    git push ${force:+--force-with-lease} origin HEAD
elif [ -n "$push" ]; then
    zz_log i "Branch not tracked remotely, skipping push"
fi

zz_log s "Commit $sha successfully deleted and history rebased."