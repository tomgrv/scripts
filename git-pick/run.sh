#!/bin/sh

eval $(
    zz-args "Pick files from a specific commit" $0 "$@" <<-help
		    c commit   commit    commit sha to pick from (if not provided, will prompt)
			- path     path      path to restore (default: current directory)
	help
)

cd "$(git rev-parse --show-toplevel)"

if [ -z "$commit" ]; then
    commit=$(git getcommit)
    if [ $? -ne 0 ] || [ -z "$commit" ]; then
        zz-log e "No commit selected or invalid commit"
        exit 1
    fi
fi

if [ -z "$path" ]; then
    path=$(git rev-parse --show-prefix)
    if [ -z "$path" ]; then
        path="."
    fi
fi

zz-log i "Picking files from commit: $commit"
zz-log i "Target path: $path"

git restore --source="$commit" --staged --worktree "$path"

if [ $? -eq 0 ]; then
    zz-log s "Successfully picked files from commit $commit to $path"
else
    zz-log e "Failed to pick files from commit $commit"
    exit 1
fi
