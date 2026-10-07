#!/bin/sh
# git-hook-postcheckout — git `post-checkout` hook. Install as
# .git/hooks/post-checkout (or via husky) invoking
# `git hook-postcheckout "$@"` — git passes the previous HEAD, new HEAD,
# and a flag (1 for a branch checkout, 0 for a file checkout).

. zz-colors

eval $(
	zz-args "Git post-checkout hook" $0 "$@" <<-help
		- prevhead  prevhead  Previous HEAD ref (as passed by git)
		- newhead   newhead   New HEAD ref (as passed by git)
		- flag      flag      1 if a branch checkout, 0 if a file checkout
	help
)

toplevel=$(git rev-parse --show-toplevel) || { zz-log e "Not inside a git repository."; exit 1; }
cd "$toplevel"

if [ -t 1 ]; then
	exec >/dev/tty 2>&1
fi

isChanged() {
	git diff --name-only HEAD@{1} HEAD | grep "^$1" >/dev/null 2>&1
}

isRebase() {
	git rev-parse --git-dir | grep -q 'rebase-merge' || git rev-parse --git-dir | grep -q 'rebase-apply' >/dev/null 2>&1
}

if test "$GIT_COMMAND" = "rebase"; then
	zz-log s "Skip post-checkout hook during rebase."
	exit 0
fi
