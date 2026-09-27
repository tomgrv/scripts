#!/bin/sh

eval $(
    zz_args "Pick files from a specific commit" $0 "$@" <<-help
		    c commit   commit    commit sha to pick from (if not provided, will prompt)
			- path     path      path to restore (default: current directory)
	help
)

cd "$(git rev-parse --show-toplevel)"

if [ -z "$commit" ]; then
    commit=$(git getcommit)
    if [ $? -ne 0 ] || [ -z "$commit" ]; then
        zz_log e "No commit selected or invalid commit"
        exit 1
    fi
fi

if [ -z "$path" ]; then
    path=$(git rev-parse --show-prefix)
    if [ -z "$path" ]; then
        path="."
    fi
fi

zz_log i "Picking files from commit: $commit"
zz_log i "Target path: $path"

git restore --source="$commit" --staged --worktree "$path"

if [ $? -eq 0 ]; then
    zz_log s "Successfully picked files from commit $commit to $path"
else
    zz_log e "Failed to pick files from commit $commit"
    exit 1
fi
