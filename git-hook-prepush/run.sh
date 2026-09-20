#!/bin/sh
# git-hook-prepush — git `pre-push` hook: validate the current branch name
# against this repo's naming convention before it's pushed. Install as
# .git/hooks/pre-push (or via husky) invoking `git hook-prepush "$@"`.

zz_use zz_colors zz_args zz_npx
. zz_colors

eval $(
	zz_args "Git pre-push hook" $0 "$@" <<-help
		- remote    remote    Remote name (as passed by git)
		- url       url       Remote URL (as passed by git)
	help
)

toplevel=$(git rev-parse --show-toplevel) || { zz_log e "Not inside a git repository."; exit 1; }
cd "$toplevel"

# Enable colors
if [ -t 1 ]; then
	exec >/dev/tty 2>&1
fi

# Check if the current Git branch name is valid
zz_npx validate-branch-name
