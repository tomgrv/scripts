#!/bin/sh

#### Goto repository root
cd "$(git rev-parse --show-toplevel)" >/dev/null

#### GET BUMP VERSION
GBV=$(gv -showvariable MajorMinorPatch)
if [ -z "$GBV" ]; then
    zz_log e "Cannot compute release version"
    exit 1
fi

#### EXIT IF A DIFFERENT RELEASE ALREADY EXISTS
# Compare against branches directly (not the .git/RELEASE file) so a stale
# file left over from a prior run can never block/mask the real state.
other=$(git branch --list 'release/*' | sed 's/^[* ]*release\///' | grep -vFx "$GBV")
if [ -n "$other" ]; then
    zz_log e "Other release exists, cannot proceed: $(printf '%s' "$other" | tr '\n' ' ')"
    exit 1
fi

#### PREVENT GIT EDITOR PROMPT
export GIT_EDITOR=:

#### STEP: create the release branch (idempotent -- resume if already started)
if git show-ref --verify --quiet "refs/heads/release/$GBV"; then
    zz_log i "Release branch release/$GBV already exists, resuming"
    if [ "$(git branch --show-current)" != "release/$GBV" ] && ! git checkout "release/$GBV"; then
        zz_log e "Cannot switch to release/$GBV"
        exit 1
    fi
elif ! git flow release start "$GBV"; then
    zz_log e "Failed to start release $GBV"
    exit 1
fi

#### STEP: record release state + push (safe to repeat -- push is a no-op
#### once the remote already has the branch)
printf '%s\n' "$GBV" >.git/RELEASE
if ! git push origin "release/$GBV"; then
    zz_log e "Cannot push release/$GBV, re-run this command to retry"
    exit 1
fi
