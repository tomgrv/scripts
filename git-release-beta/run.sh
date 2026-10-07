#!/bin/sh

cd "$(git rev-parse --show-toplevel)" >/dev/null

GBV=$(gv -showvariable MajorMinorPatch)
if [ -z "$GBV" ]; then
    zz-log e "Cannot compute release version"
    exit 1
fi

# Compare against branches directly (not the .git/RELEASE file) so a stale
# file left over from a prior run can never block/mask the real state.
other=$(git branch --list 'release/*' | sed 's/^[* ]*release\///' | grep -vFx "$GBV")
if [ -n "$other" ]; then
    zz-log e "Other release exists, cannot proceed: $(printf '%s' "$other" | tr '\n' ' ')"
    exit 1
fi

export GIT_EDITOR=:

# Idempotent: resume if a release branch was already started.
if git show-ref --verify --quiet "refs/heads/release/$GBV"; then
    zz-log i "Release branch release/$GBV already exists, resuming"
    if [ "$(git branch --show-current)" != "release/$GBV" ] && ! git checkout "release/$GBV"; then
        zz-log e "Cannot switch to release/$GBV"
        exit 1
    fi
elif ! git flow release start "$GBV"; then
    zz-log e "Failed to start release $GBV"
    exit 1
fi

# Safe to repeat -- push is a no-op once the remote already has the branch.
printf '%s\n' "$GBV" >.git/RELEASE
if ! git push origin "release/$GBV"; then
    zz-log e "Cannot push release/$GBV, re-run this command to retry"
    exit 1
fi
