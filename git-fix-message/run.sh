#!/bin/sh

eval $(
	zz_args "Rewrite an arbitrary commit message" $0 "$@" <<-help
			f -        force     allow overwritting pushed history
			p -        push      push to remote
			m msg      msg       new commit message
			- sha      sha       sha commit to rewrite message
	help
)

cd "$(git rev-parse --show-toplevel)" >/dev/null

git fetch --progress --prune --recurse-submodules=no origin >/dev/null

if ! git diff-index --quiet HEAD --; then
	zz_log e "You have uncommitted changes. Please commit or stash them before running this script."
	exit 1
fi

if git isRebase >/dev/null 2>&1; then
	zz_log e "A rebase is in progress. Please finish or abort it before running this script."
	exit 1
fi

sha=$(git getcommit $force $sha)

if ! git rev-parse --verify --quiet "$sha^{commit}" >/dev/null; then
	zz_log e "Invalid commit: $sha"
	exit 1
fi

if ! git merge-base --is-ancestor "$sha" HEAD; then
	zz_log e "Commit $(echo "$sha" | cut -c1-7) is not in the current branch history."
	exit 1
fi

if [ -z "$msg" ]; then
	msg=$(zz_prompt "New commit message:")
fi

if [ -z "$msg" ]; then
	zz_log e "Commit message cannot be empty."
	exit 1
fi

old_msg=$(git log -1 --pretty=%s "$sha")
zz_log w "Commit to rewrite: $(echo "$sha" | cut -c1-7)"
zz_log - "Current message: $old_msg"
zz_log - "New message: $msg"
zz_log w "This will rewrite git history. Make sure you understand the consequences."

if [ "$(zz_ask "Yn" "Do you want to proceed?")" != "y" ]; then
	zz_log i "Operation cancelled by user."
	exit 1
fi

# A minimal range including target commit and descendants speeds up the rewrite over --all
if [ -n "$(git rev-list --parents -n 1 "$sha" | cut -d' ' -f2)" ]; then
	range="$sha^..HEAD"
else
	range="--all"
fi

TARGET_SHA="$sha" NEW_MESSAGE="$msg" git filter-branch --msg-filter '
	if [ "$GIT_COMMIT" = "$TARGET_SHA" ]; then
		printf "%s\n" "$NEW_MESSAGE"
	else
		cat
	fi
' --tag-name-filter cat -- $range

# filter-branch leaves rewritten refs behind; purge them so the old history is unreachable
rm -rf .git/refs/original/
git reflog expire --expire=now --all
git gc --prune=now

if [ -n "$push" ]; then
	if git rev-parse --verify --quiet origin/HEAD >/dev/null; then
		zz_log i "Pushing to remote..."
		if [ -n "$force" ]; then
			git push --force origin HEAD
		else
			git push --force-with-lease origin HEAD
		fi
	else
		zz_log i "Branch not pushed, skipping push..."
	fi
fi

zz_log s "Commit message rewritten successfully."