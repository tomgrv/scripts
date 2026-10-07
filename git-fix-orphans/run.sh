#!/bin/sh

set -e

eval $(
    zz-args "Prefix remote branches that do not follow the gitflow config and have no pull request" $0 "$@" <<-help
		p -      push       apply the renames on the remote (default: dry run, only list)
		x prefix prefix     prefix to prepend (default: orphan/)
		- remote remote     remote to inspect (default: origin)
	help
)

cd "$(git rev-parse --show-toplevel)" >/dev/null

remote="${remote:-origin}"
prefix="${prefix:-orphan/}"

# Compliance is defined by the gitflow config: without one there is nothing to
# compare branch names against, so leave everything untouched.
master=$(git config gitflow.branch.master 2>/dev/null || true)
develop=$(git config gitflow.branch.develop 2>/dev/null || true)
if [ -z "$master" ] && [ -z "$develop" ]; then
    zz-log w "No gitflow config found (run 'git flow init'), nothing to check against"
    exit 0
fi

# Exact names and name prefixes that are compliant.
allowed_names="$master $develop"
allowed_prefixes="$prefix"
for kind in feature bugfix release hotfix support; do
    value=$(git config "gitflow.prefix.$kind" 2>/dev/null || true)
    [ -n "$value" ] && allowed_prefixes="$allowed_prefixes $value"
done

# Never rename the remote's default branch, whatever its name.
default=$(git ls-remote --symref "$remote" HEAD | sed -n 's|^ref: refs/heads/\(.*\)[[:space:]]HEAD$|\1|p')
allowed_names="$allowed_names $default"

# Branches that ever had a pull request (open, merged or closed) are associated.
# Without a reliable answer, rename nothing.
with_pr=$(gh pr list --state all --limit 1000 --json headRefName --jq '.[].headRefName') || {
    zz-log e "Unable to list pull requests with gh, aborting"
    exit 1
}

is_compliant() {
    for n in $allowed_names; do
        [ "$1" = "$n" ] && return 0
    done
    for p in $allowed_prefixes; do
        case "$1" in "$p"*) return 0 ;; esac
    done
    return 1
}

zz-log i "Fetching $remote"
git fetch --prune --quiet "$remote" "+refs/heads/*:refs/remotes/$remote/*"

renamed=0
for ref in $(git for-each-ref --format='%(refname:short)' "refs/remotes/$remote/"); do
    branch="${ref#"$remote"/}"
    [ "$branch" = "HEAD" ] && continue
    is_compliant "$branch" && continue
    printf '%s\n' "$with_pr" | grep -qxF -- "$branch" && continue

    target="$prefix$branch"
    if git show-ref --verify --quiet "refs/remotes/$remote/$target"; then
        zz-log w "Skipping $branch: $target already exists"
        continue
    fi

    if [ -n "$push" ]; then
        git push --atomic "$remote" "refs/remotes/$remote/$branch:refs/heads/$target" ":refs/heads/$branch" ||
            { zz-log w "Failed to rename $branch"; continue; }
    fi
    # Machine-readable result on stdout, logs stay on stderr.
    printf '%s -> %s\n' "$branch" "$target"
    renamed=$((renamed + 1))
done

if [ -z "$push" ]; then
    zz-log s "$renamed branch(es) to rename. Use -p to apply."
else
    zz-log s "$renamed branch(es) renamed."
fi
