#!/bin/sh

# Function to print help and manage arguments
eval $(
	zz_args "Fix git history" $0 "$@" <<-help
		    f -      force     allow overwritting pushed history
			e -      edit      edit commit message
			p -      push      push to remote
			- sha    sha       sha commit to fixup
	help
)

# Do not fixup if staged files contain composer.lock or package-lock.json
if [ -n "$(git diff --cached --name-only | grep -E 'composer.lock|package-lock.json')" ]; then
	zz_log e 'Packages lock file are staged, fixup is not allowed.'
	exit 1
fi

# Prepare environment variables GIT_EDITOR based on edit option
if [ -z "$edit" ]; then
	export GIT_EDITOR=":"
fi

# Navigate to the repository root
cd "$(git rev-parse --show-toplevel)" >/dev/null

# Fetch updates from the remote repository
git fetch --progress --prune --recurse-submodules=no origin >/dev/null

# Check if a fixup commit already exists
if git isFixup; then
	zz_log e 'Fixup commit found, please continue rebasing...'
	exit 1
fi

# Ensure there are staged files before proceeding
if [ -z "$(git diff --cached --name-only)" ]; then
	zz_log e 'No files are staged, fixup is not allowed.'
	exit 1
fi

# Retrieve the commit SHA to fixup
sha=$(git getcommit $force $sha)

# Log the commit SHA to be fixed up
zz_log i "Fixup commit given: $sha"

# Create a fixup commit and handle failure
if ! git commit --fixup $sha; then
	zz_log e 'Fixup commit failed...'
	exit 1
fi

# Start an interactive rebase with autosquash
git rebase -i --autosquash $sha~ --autostash --no-verify --reschedule-failed-exec --exec 'git hook run --ignore-missing pre-commit -- HEAD HEAD~1 && git commit --amend --no-edit --no-verify' --no-verify

while [ $? -ne 0 ]; do

	# Check if there are any composer conflicts during the rebase
	if [ -f composer.lock ]; then
		if grep -q "^<<<<<<< \|^======= \|^>>>>>>> " composer.lock; then
			# accept incoming changes in composer.lock
			git checkout --theirs composer.lock

			# run composer lock to update the lock file
			composer lock || zz_log e 'Please resolve composer.lock conflicts manually.'
		fi
	fi

	# Check if there are any package-lock conflicts during the rebase
	if [ -f package-lock.json ]; then
		if grep -q "^<<<<<<< \|^======= \|^>>>>>>> " package-lock.json; then
			# accept incoming changes in package-lock.json
			git checkout --theirs package-lock.json

			# run npm install to update the lock file
			npm install || zz_log e 'Please resolve package-lock.json conflicts manually.'
		fi
	fi

	# Continue the rebase process
	git rebase --continue
done

# if rebase successful and push option is set, push force the changes
if [ "$?" -eq 0 -a -n "$push" ]; then
	# Check if the branch is already pushed
	if git rev-parse --verify --quiet origin/HEAD >/dev/null; then
		zz_log i "Pushing to remote..."
		git push --force-with-lease origin HEAD
	else
		zz_log i "Branch not pushed, skipping push..."
	fi
fi
