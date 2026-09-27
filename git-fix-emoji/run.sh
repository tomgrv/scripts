#!/bin/sh

eval $(
	zz_args "Fix git emoji" $0 "$@" <<-help
		f -     force	allow overwritting pushed history
		p -		push	push changes after rewriting history
		- sha   sha 	sha commit to fix from after
	help
)

cd "$(git rev-parse --show-toplevel)" >/dev/null

git fetch --progress --prune --recurse-submodules=no origin >/dev/null

if ! git diff-index --quiet HEAD --; then
	zz_log e "You have uncommitted changes. Please commit or stash them before running this script."
	exit 1
fi

sha=$(git getcommit -p $force $sha)

git filter-branch --msg-filter 'npx --yes devmoji' --tag-name-filter cat -- --branches --tags ${sha:---all}${sha:+..HEAD}

# filter-branch leaves rewritten refs behind; purge them so the old history is unreachable
rm -rf .git/refs/original/
git reflog expire --expire=now --all
git gc --prune=now

if [ "$push" = true ]; then
	if [ "$force" = true ]; then
		git push --force --tags origin 'refs/heads/*'
	else
		git push --force-with-lease --tags origin 'refs/heads/*'
	fi
fi

zz_log s "Git emoji fixup completed successfully."
