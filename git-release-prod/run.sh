#!/bin/sh

# Parse arguments and print help if needed
eval $(
    zz_args "Release production branch" $0 "$@" <<-help
help
)

# Change to repository root
cd "$(git rev-parse --show-toplevel)" >/dev/null

# Refresh tags up front so the "already finished" checks below (which rely on
# tag existence) see what's actually on the remote, not a stale local view.
git fetch origin --tags >/dev/null 2>&1

# git flow finish tags as <gitflow.prefix.versiontag><version> (default "v").
versiontag_prefix=$(git config gitflow.prefix.versiontag 2>/dev/null)
versiontag_prefix="${versiontag_prefix:-v}"

#### STEP: resolve which flow branch to finish -----------------------------
# Prefer the branch we're already on, so a checked-out hotfix/release branch
# is never overridden by an unrelated one that also happens to exist locally.
current=$(git branch --show-current)
case "$current" in
hotfix/*)
    flow=hotfix
    name=${current#hotfix/}
    zz_log i "On hotfix branch: {Yellow $name}"
    ;;
release/*)
    flow=release
    name=${current#release/}
    zz_log i "On release branch: {Blue $name}"
    ;;
esac

# Not currently on a flow branch: fall back to discovery, but refuse to guess
# when more than one candidate exists -- silently picking one risks finishing
# (merging + tagging + pushing) the wrong release/hotfix.
if [ -z "$flow" ]; then
    hotfixes=$(git branch --list 'hotfix/*' | sed 's/^[* ]*hotfix\///')
    hotfix_count=$(printf '%s\n' "$hotfixes" | grep -c .)

    if [ "$hotfix_count" -gt 1 ]; then
        zz_log e "Multiple hotfix branches found, checkout the one to finish first: $(printf '%s' "$hotfixes" | tr '\n' ' ')"
        exit 1
    elif [ "$hotfix_count" -eq 1 ]; then
        flow=hotfix
        name=$hotfixes
        zz_log i "Hotfix branch found: {Yellow $name}"
    elif [ -f .git/RELEASE ]; then
        name=$(cat .git/RELEASE)
        # Cleanup-only case: `git flow finish` already ran to completion on a
        # prior run (it deletes the release branch on success), but the
        # trailing bump-tag/cleanup step never happened. There's no branch
        # left to check out, so finish the leftover cleanup here and stop.
        if ! git show-ref --verify --quiet "refs/heads/release/$name" \
            && git rev-parse -q --verify "refs/tags/${versiontag_prefix}${name}" >/dev/null; then
            zz_log i "Release $name already finished (branch gone, tag exists) -- cleaning up only"
            bump-tag "$name"
            rm -f .git/RELEASE
            exit 0
        fi
        flow=release
        zz_log i "Release branch found: {Blue $name}"
    else
        releases=$(git branch --list 'release/*' | sed 's/^[* ]*release\///')
        release_count=$(printf '%s\n' "$releases" | grep -c .)

        if [ "$release_count" -gt 1 ]; then
            zz_log e "Multiple release branches found, checkout the one to finish first: $(printf '%s' "$releases" | tr '\n' ' ')"
            exit 1
        elif [ "$release_count" -eq 1 ]; then
            flow=release
            name=$releases
            zz_log i "Release branch found: {Blue $name}"
        fi
    fi
fi

# Exit if no flow branch is found
if [ -z "$flow" ] || [ -z "$name" ]; then
    zz_log e "No flow branch found"
    exit 1
fi

# Switch to the resolved branch
if ! git checkout "$flow/$name" >/dev/null 2>&1; then
    zz_log e "Cannot switch to $flow/$name branch"
    exit 1
fi
zz_log s "On branch: {Blue $flow/$name}"

#### STEP: determine target version + whether finish already happened ------
GBV=$(gv -showvariable MajorMinorPatch)
if [ -z "$GBV" ]; then
    zz_log e "Cannot get version from .gitversion"
    exit 1
fi
zz_log i "Bump version: {Blue $GBV}"

# If the finish tag already exists, finish already ran to completion on a
# prior run -- resume at cleanup only instead of redoing the merge/tag/push.
finished=""
if git rev-parse -q --verify "refs/tags/${versiontag_prefix}${GBV}" >/dev/null; then
    zz_log i "Tag ${versiontag_prefix}${GBV} already exists, release already finished -- resuming cleanup only"
    finished=true
fi

# Prevent git editor prompt during finish
export GIT_EDITOR=:

if [ -z "$finished" ]; then

    # Ensure working directory is clean
    if [ -n "$(git status --porcelain)" ]; then
        zz_log e "Working directory is not clean. Please commit or stash changes."
        exit 1
    fi

    # Ensure the flow branch has an up-to-date remote
    if ! git fetch origin >/dev/null 2>&1; then
        zz_log e "Cannot fetch from remote"
        exit 1
    fi

    # is-ancestor(remote, local) succeeds only when the remote tip is already
    # contained in local -- i.e. local is not behind. Passed the other way
    # round it would succeed while local is behind (needs a pull).
    if ! git merge-base --is-ancestor "$(git rev-parse "refs/remotes/origin/$flow/$name")" "$(git rev-parse "$flow/$name")" ; then
        zz_log e "$flow/$name branch is not up-to-date with remote. Please pull the latest changes."
        exit 1
    fi

    #### STEP: bump version/changelog + commit (idempotent -- skip if a
    #### previous run already made this exact commit)
    if [ "$(git log -1 --pretty=%s)" = "chore(release): $GBV" ]; then
        zz_log i "Version & CHANGELOG already committed for $GBV, skipping bump"
    else
        if ! bump-changelog -f "$GBV" -b -m; then
            zz_log e "Cannot update version & CHANGELOG"
            exit 1
        fi
        zz_log s "Version & CHANGELOG updated to: {B $GBV}"
        if ! git commit -am "chore(release): $GBV"; then
            zz_log e "Cannot commit version & CHANGELOG"
            exit 1
        fi
    fi

    #### STEP: push (safe to repeat -- no-op once the remote already has it)
    if ! git push --set-upstream origin "$flow/$name"; then
        zz_log e "Cannot push $flow/$name, re-run this command to retry"
        exit 1
    fi
    zz_log s "Version & CHANGELOG committed and pushed"

    # Ensure develop branch is up-to-date before finishing release
    if ! git fetch origin develop:develop; then
        zz_log e "Cannot fetch develop branch from remote"
        exit 1
    fi

    if ! git merge-base --is-ancestor "$(git rev-parse origin/develop)" "$(git rev-parse develop)" ; then
        zz_log e "Develop branch is not up-to-date with remote. Please pull the latest changes."
        exit 1
    fi

    #### STEP: finish (merge to main/develop + tag + push)
    # git flow finish prepends gitflow.prefix.versiontag to --tagname itself,
    # so pass the bare version here -- prefixing it ourselves would tag "vv$GBV".
    if git flow "$flow" finish "$name" --push --tagname "$GBV" --message "$GBV" ; then
        zz_log s "Release finished: {B $GBV}"
    else
        zz_log e "Cannot finish release. Please fix the issues, commit any pending changes, then re-run this command to retry -- or finish manually with:"
        zz_log - "   git flow $flow finish $name --push --tagname $GBV --message $GBV"
        exit 1
    fi
fi

#### STEP: tag follow-up + cleanup (both idempotent, safe to repeat) -------
bump-tag "$GBV"
# Clear release state only once the release has actually finished.
rm -f .git/RELEASE
