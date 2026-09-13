#!/bin/sh
# git-hook-preparecommitmsg — git `prepare-commit-msg` hook: install
# commitizen plugins declared in package.json, then launch commitizen's
# interactive prompt to build the commit message, unless one was already
# provided (merge/squash/template commits, or a message passed with -m).
# Install as .git/hooks/prepare-commit-msg (or via husky) invoking
# `git hook-preparecommitmsg "$@"`.

zz_use zz_colors zz_args zz_npx git-hook-installplugins git-cz
. zz_colors

eval $(
	zz_args "Git prepare-commit-msg hook" $0 "$@" <<-help
		- msgfile   msgfile   Path to the commit message file (as passed by git)
		- source    source    Commit message source (message/template/merge/squash/commit)
		- commit    commit    Commit SHA-1, present when source is 'commit'
	help
)

toplevel=$(git rev-parse --show-toplevel) || { zz_log e "Not inside a git repository."; exit 1; }
cd "$toplevel"

# Enable colors
if [ -t 1 ]; then
	exec >/dev/tty 2>&1
fi

# Install commitizen plugins
git-hook-installplugins -g '[.config.commitizen.path // "", .commitlint.extends // ""]'

# Edit commit message
if [ $(grep -cv -e '^#' -e '^$' .git/COMMIT_EDITMSG) -eq 0 ]; then
	(exec </dev/tty && zz_npx git-cz --hook || zz_log e "Unable to start commitizen.") || zz_log e "Commitizen failed."
else
	zz_log i "Commitizen not relevant. Skipping..."
fi
