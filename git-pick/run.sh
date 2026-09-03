#!/bin/sh

# Function to print help and manage arguments
eval $(
    zz_args "Pick files from a specific commit" $0 "$@" <<-help
		    c commit   commit    commit sha to pick from (if not provided, will prompt)
			- path     path      path to restore (default: current directory)
	help
)

#### Go to repository root
cd "$(git rev-parse --show-toplevel)"

# If no commit is provided, use git getcommit to select one
if [ -z "$commit" ]; then
    commit=$(git getcommit)
    if [ $? -ne 0 ] || [ -z "$commit" ]; then
        zz_log e "No commit selected or invalid commit"
        exit 1
    fi
fi

# If no path is provided, use current prefix (relative to repo root)
if [ -z "$path" ]; then
    path=$(git rev-parse --show-prefix)
    # If path is empty (we're at repo root), use current directory
    if [ -z "$path" ]; then
        path="."
    fi
fi

zz_log i "Picking files from commit: $commit"
zz_log i "Target path: $path"

# Execute the git restore command
git restore --source="$commit" --staged --worktree "$path"

if [ $? -eq 0 ]; then
    zz_log s "Successfully picked files from commit $commit to $path"
else
    zz_log e "Failed to pick files from commit $commit"
    exit 1
fi
