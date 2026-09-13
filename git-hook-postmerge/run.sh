#!/bin/sh
# git-hook-postmerge — git `post-merge` hook: if the merge changed
# package-lock.json or composer.lock, keep "theirs" (the merged-in
# version) staged and tell the developer to reinstall dependencies.
# Install as .git/hooks/post-merge (or via husky) invoking
# `git hook-postmerge "$@"` — git passes a squash flag (1 if `--squash`).

zz_use zz_colors zz_args
. zz_colors

eval $(
	zz_args "Git post-merge hook" $0 "$@" <<-help
		- squash    squash    1 if the merge was a squash merge, 0 otherwise
	help
)

toplevel=$(git rev-parse --show-toplevel) || { zz_log e "Not inside a git repository."; exit 1; }
cd "$toplevel"

# Enable colors
if [ -t 1 ]; then
	exec >/dev/tty 2>&1
fi

# Check if file is changed
isChanged() {
	git diff --name-only HEAD@{1} HEAD | grep "^$1" >/dev/null 2>&1
}

# Checkout composer.lock or package-lock.json if changed
if isChanged 'composer.lock' || isChanged 'package-lock.json'; then
	git checkout --theirs composer.lock package-lock.json && git add composer.lock package-lock.json
	zz_log s "Files <package-lock.json> or <composer.lock> changed."
	zz_log s "Run composer/npm install to bring your dependencies up to date."
fi
