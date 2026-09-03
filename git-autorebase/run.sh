#!/bin/sh

# Handle parameters
eval $(
    zz_args "Automatically handles non-interactive rebasing with conflict resolution" $0 "$@" <<-help
        f -             force       allow overwriting pushed history
        p -             push        push to remote after rebase
        a -             autosquash  Apply autosquash (default: off)
        n -             no-lock     don't automatically manage lock files
        s strategy      strategy    strategy for conflicts (default: theirs)
        o onto          onto        rebase onto (default: origin/main)
        b branch        branch       branch to rebase (default: current branch)
        - sha           sha          commit/branch to rebase onto (default: origin/main)
help
)

# Set defaults
strategy="${strategy:-theirs}"
branch="${branch:-$(git branch --show-current)}"
sha=$(git getcommit $force $sha)
lockfile_patterns="${no_lock:+}${no_lock:-package-lock.json yarn.lock composer.lock pnpm-lock.yaml go.sum}"

# Navigate to repository root and validate state
cd "$(git rev-parse --show-toplevel)" >/dev/null
git sync >/dev/null 2>&1 || git fetch --prune origin >/dev/null 2>&1

if git isRebase; then
    zz_log e 'Rebase is in progress, please finish or abort it first.'
    exit 1
fi

# Manage lockfiles during conflicts
manage_lockfiles() {

    for pattern in $lockfile_patterns; do
        find . -name "$pattern" -type f | while read lockfile; do
            if git status --porcelain | grep -q "^UU.*$lockfile"; then
                zz_log i "Resolving lock file conflict: $lockfile"
                git checkout --theirs "$lockfile" && git add "$lockfile"
            fi
        done
    done
}

# Handle all conflicts automatically
handle_conflicts() {
    git conflict | while read file; do
        zz_log i "Resolving conflict in: $file"
        case "$strategy" in
            "theirs") git checkout --theirs "$file" ;;
            "ours") git checkout --ours "$file" ;;
        esac
        git add "$file"
    done
    manage_lockfiles
}


current_branch=$(git branch --show-current)
zz_log i "Rebasing '$current_branch' onto '$sha' with '$strategy' strategy"

# Perform rebase with automatic conflict resolution
if ! git rebase --strategy-option="$strategy" ${auto:+--autosquash} --autostash --reschedule-failed-exec --exec 'git hook run --ignore-missing pre-commit -- HEAD HEAD~1 && git commit --amend --no-edit --no-verify' --no-verify ${onto:+--onto "$onto"} "$sha" "$branch"; then
    zz_log w "Resolving conflicts automatically..."
    
    attempts=0
    while git status | grep -q "rebase in progress" && [ $attempts -lt 50 ]; do
        attempts=$((attempts + 1))
        
        if git conflict | grep -q .; then
            zz_log i "Handling conflicts (attempt $attempts)"
            handle_conflicts
        fi
        
        git rebase --continue || break
        sleep 0.1
    done
    
    # Check if rebase completed successfully
    if git status | grep -q "rebase in progress"; then
        zz_log e "Rebase failed after $attempts attempts"
        git abort
        exit 1
    fi
else
    zz_log s "Rebase completed without conflicts"
fi

# Push changes if requested
if [ -n "$push" ] && git rev-parse --verify --quiet origin/HEAD >/dev/null; then
    zz_log i "Pushing changes..."
    if [ -n "$force" ]; then
        git pf origin HEAD
    else
        git push origin HEAD
    fi
fi

zz_log s "Rebase completed: '$current_branch' → '$sha'"
