#!/bin/sh
# git-hook-commitmsg — git `commit-msg` hook: install commitizen/commitlint
# plugins declared in package.json, apply commitlint rules to the commit
# message git just wrote, then run devmoji to prepend/rewrite its emoji.
# Install as .git/hooks/commit-msg (or via husky) invoking
# `git hook-commitmsg "$@"` — git passes the commit message file as $1.

. zz-colors

eval $(
	zz-args "Git commit-msg hook" $0 "$@" <<-help
		- msgfile   msgfile   Path to the commit message file (as passed by git)
	help
)

toplevel=$(git rev-parse --show-toplevel) || { zz-log e "Not inside a git repository."; exit 1; }
cd "$toplevel"

if [ -t 1 ]; then
	exec >/dev/tty 2>&1
fi

if [ -z "$msgfile" ]; then
	zz-log e "No commit message file provided."
	exit 1
fi

git-hook-installplugins -g '[.config.commitizen.path // "", .commitlint.extends // ""]'

zz-log i "Applying commitlint rules to the latest commit..."
zz-npx commitlint --edit "$msgfile" && zz-npx devmoji -e
