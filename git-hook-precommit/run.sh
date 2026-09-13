#!/bin/sh
# git-hook-precommit — git `pre-commit` hook: keep package-lock.json /
# composer.lock in sync with any staged manifest changes, install any
# missing prettier plugins, then run git-precommit-checks + lint-staged.
# Install as the repo's .git/hooks/pre-commit (or via husky) invoking
# `git hook-precommit "$@"`.

zz_use zz_colors zz_args zz_npx git-hook-installplugins git-precommit-checks lint-staged
. zz_colors

eval $(
	zz_args "Git pre-commit hook" $0 "$@" <<-help
		# refs refs  Optional refs/paths passed through to 'git diff --name-only'
	help
)

toplevel=$(git rev-parse --show-toplevel) || { zz_log e "Not inside a git repository."; exit 1; }
cd "$toplevel"

# Enable colors
if [ -t 1 ]; then
	exec >/dev/tty 2>&1
fi

# Check if the current Git command is a rebase
if test "$GIT_COMMAND" = "rebase"; then
	zz_log s "Skip pre-commit hook during rebase"
	exit 0
fi

zz_log i "Git command: {Cyan $GIT_COMMAND}"

# Staged files, computed once and reused below
if [ "$#" -eq 0 ]; then
	changed_files=$(git diff --name-only --cached)
else
	changed_files=$(git diff --name-only "$@")
fi

# Check if the current commit contains package.json changes
if echo "$changed_files" | grep -q "package.json"; then

	# ensure that the package.json is valid and package-lock.json is up-to-date
	zz_log i "Ensure that the package.json is valid and package-lock.json is up-to-date..."

	# --package-lock-only --ignore-scripts: recompute the lockfile without
	# installing anything or running install/postinstall lifecycle scripts.
	# A full `npm install --ws` here runs every workspace's lifecycle
	# scripts on every commit that touches any package.json, which can
	# rewrite arbitrary tracked files mid-hook — lint-staged's git-stash
	# based backup/restore of the original staged snapshot then has to
	# reconcile that unrelated noise, and unrelated staged changes can be
	# dropped instead of committed.
	ws=$(npm pkg get workspaces)
	if test "$ws" = "undefined" || test "$ws" = "{}"; then
		npm install --package-lock-only --ignore-scripts || true
	else
		npm install --package-lock-only --ignore-scripts --ws --if-present --include-workspace-root || true
	fi

	# commit the updated package-lock.json if file changed
	if git diff --quiet package-lock.json; then
		zz_log s "package-lock.json update not required"
	else
		git add package-lock.json && zz_log w "Updated package-lock.json"
	fi
fi

# Check if the current commit contains composer.json changes
if echo "$changed_files" | grep -q "composer.json"; then

	# ensure that the composer.json is valid and composer.lock is up-to-date
	zz_log i "Ensure that the composer.json is valid and composer.lock is up-to-date..."
	composer_validate=$(composer validate --no-check-all --strict 2>&1)
	composer_valid=$?
	missing_packages=$(echo "$composer_validate" | grep -oP 'Required package "\K[^"]+')
	if [ -n "$missing_packages" ]; then
		echo "$missing_packages" | while read -r package; do
			composer require --ignore-platform-reqs --with-all-dependencies --no-scripts --no-interaction --no-progress --no-install "$package"
		done
		# requiring packages changed composer.json's state, so re-check before deciding on a full update
		composer validate --no-check-all --strict || composer update --lock --minimal-changes --ignore-platform-reqs --with-all-dependencies --no-scripts --no-interaction --no-progress --no-install
	elif [ "$composer_valid" -ne 0 ]; then
		composer update --lock --minimal-changes --ignore-platform-reqs --with-all-dependencies --no-scripts --no-interaction --no-progress --no-install
	fi

	# commit the updated composer.lock if file changed
	if git diff --quiet composer.lock; then
		zz_log s "composer.lock update not required"
	else
		git add composer.lock && zz_log w "Updated composer.lock"
	fi
fi

# Install Prettier plugins if they are not already installed
git-hook-installplugins '.prettier.plugins//""'

# Run pre-commit checks
zz_npx git-precommit-checks
zz_npx lint-staged --cwd ${INIT_CWD:-$PWD} --allow-empty
