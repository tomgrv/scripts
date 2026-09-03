#!/bin/sh

# Function to print help and manage arguments
eval $(
	zz_args "Rewrite an arbitrary commit message" $0 "$@" <<-help
			f -        force     allow overwritting pushed history
			p -        push      push to remote
			m msg      msg       new commit message
			- sha      sha       sha commit to rewrite message
	help
)

# Navigate to the repository root
cd "$(git rev-parse --show-toplevel)" >/dev/null

# Fetch updates from the remote repository
git fetch --progress --prune --recurse-submodules=no origin >/dev/null

# Make sure we don't have uncommitted changes
if ! git diff-index --quiet HEAD --; then
	zz_log e "You have uncommitted changes. Please commit or stash them before running this script."
	exit 1
fi

# Prevent running while a rebase is in progress
if git isRebase >/dev/null 2>&1; then
	zz_log e "A rebase is in progress. Please finish or abort it before running this script."
	exit 1
fi

# Retrieve the commit SHA to edit
sha=$(git getcommit $force $sha)

# Validate commit exists
if ! git rev-parse --verify --quiet "$sha^{commit}" >/dev/null; then
	zz_log e "Invalid commit: $sha"
	exit 1
fi

# Ensure commit belongs to current branch history
if ! git merge-base --is-ancestor "$sha" HEAD; then
	zz_log e "Commit $(echo "$sha" | cut -c1-7) is not in the current branch history."
	exit 1
fi

# Ask for the new message if not provided as argument
if [ -z "$msg" ]; then
	msg=$(zz_prompt "New commit message:")
fi

# Ensure message is not empty
if [ -z "$msg" ]; then
	zz_log e "Commit message cannot be empty."
	exit 1
fi

old_msg=$(git log -1 --pretty=%s "$sha")
zz_log w "Commit to rewrite: $(echo "$sha" | cut -c1-7)"
zz_log - "Current message: $old_msg"
zz_log - "New message: $msg"
zz_log w "This will rewrite git history. Make sure you understand the consequences."

if ! zz_ask "Yn" "Do you want to proceed?"; then
	zz_log i "Operation cancelled by user."
	exit 1
fi

# Build a minimal range that includes target commit and descendants.
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

# Clean up the original refs
rm -rf .git/refs/original/
git reflog expire --expire=now --all
git gc --prune=now

# Push rewritten history if requested
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