#!/bin/sh

eval $(
	zz_args "Fix git history" $0 "$@" <<-help
		    f -      force     allow overwritting pushed history
			e -      edit      edit commit message
			p -      push      push to remote
			- sha    sha       sha commit to fixup
	help
)

if [ -n "$(git diff --cached --name-only | grep -E 'composer.lock|package-lock.json')" ]; then
	zz_log e 'Packages lock file are staged, fixup is not allowed.'
	exit 1
fi

if [ -z "$edit" ]; then
	export GIT_EDITOR=":"
fi

cd "$(git rev-parse --show-toplevel)" >/dev/null

git fetch --progress --prune --recurse-submodules=no origin >/dev/null

if git isFixup; then
	zz_log e 'Fixup commit found, please continue rebasing...'
	exit 1
fi

if [ -z "$(git diff --cached --name-only)" ]; then
	zz_log e 'No files are staged, fixup is not allowed.'
	exit 1
fi

sha=$(git getcommit $force $sha)

zz_log i "Fixup commit given: $sha"

if ! git commit --fixup $sha; then
	zz_log e 'Fixup commit failed...'
	exit 1
fi

git rebase -i --autosquash $sha~ --autostash --no-verify --reschedule-failed-exec --exec 'git hook run --ignore-missing pre-commit -- HEAD HEAD~1 && git commit --amend --no-edit --no-verify' --no-verify

while [ $? -ne 0 ]; do

	if [ -f composer.lock ]; then
		if grep -q "^<<<<<<< \|^======= \|^>>>>>>> " composer.lock; then
			git checkout --theirs composer.lock
			composer lock || zz_log e 'Please resolve composer.lock conflicts manually.'
		fi
	fi

	if [ -f package-lock.json ]; then
		if grep -q "^<<<<<<< \|^======= \|^>>>>>>> " package-lock.json; then
			git checkout --theirs package-lock.json
			npm install || zz_log e 'Please resolve package-lock.json conflicts manually.'
		fi
	fi

	git rebase --continue
done

if [ "$?" -eq 0 -a -n "$push" ]; then
	if git rev-parse --verify --quiet origin/HEAD >/dev/null; then
		zz_log i "Pushing to remote..."
		git push --force-with-lease origin HEAD
	else
		zz_log i "Branch not pushed, skipping push..."
	fi
fi
