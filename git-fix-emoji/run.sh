#!/bin/sh

# Function to print help and manage arguments
eval $(
	zz_args "Fix git emoji" $0 "$@" <<-help
		f -     force	allow overwritting pushed history
		p -		push	push changes after rewriting history
		- sha   sha 	sha commit to fix from after
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

# Retrieve the commit SHA to fixup
sha=$(git getcommit -p $force $sha)

#### Rewrite history to fix author
# Rewrite commit messages to add the appropriate emoji from the specified commit
git filter-branch --msg-filter 'npx --yes devmoji' --tag-name-filter cat -- --branches --tags ${sha:---all}${sha:+..HEAD}

# Clean up the original refs
rm -rf .git/refs/original/
git reflog expire --expire=now --all
git gc --prune=now

# Push changes if the push flag is set
if [ "$push" = true ]; then
	if [ "$force" = true ]; then
		git push --force --tags origin 'refs/heads/*'
	else
		git push --force-with-lease --tags origin 'refs/heads/*'
	fi
fi

zz_log s "Git emoji fixup completed successfully."
