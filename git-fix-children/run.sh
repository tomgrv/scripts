#!/bin/sh

set -e

eval $(
    zz-args "Delete all descendant tags and branches of a commit" $0 "$@" <<-help
		p -      push       push to remote
        f -      force      allow overwriting pushed history
		- sha    sha        sha commit to start from
	help
)

cd "$(git rev-parse --show-toplevel)" >/dev/null

sha=$(git getcommit $force $sha)

zz-log i "Deleting all tags that are descendants of $sha"

tags=$(git tag --contains "$sha")
if [ -n "$tags" ]; then
    echo "$tags" | xargs -r git tag -d
else
    zz-log w "No descendant tags found"
fi

zz-log i "Deleting all local branches that are descendants of $sha (except current, main, master)"

current=$(git rev-parse --abbrev-ref HEAD)
branches=$(git branch --contains "$sha" | sed "s/^[* ]*//" | grep -vE "^($current|main|master)$" || true)
if [ -n "$branches" ]; then
    echo "$branches" | xargs -r git branch -D
else
    zz-log w "No descendant branches found"
fi

if [ -n "$push" ]; then

    zz-log i "Pushing deletions to remote"
    for tag in $tags; do
        git push origin ":refs/tags/$tag" || zz-log w "Failed to delete remote tag $tag"
    done
    for branch in $branches; do
        git push origin --delete "$branch" || zz-log w "Failed to delete remote branch $branch"
    done
else
    zz-log w "Remote deletions not pushed. Use -p to push deletions to remote."
fi
