#!/bin/sh

# Function to print help and manage arguments
eval $(
    zz_args "Edit the last commit message and content" $0 "$@" <<-help
        m   msg     msg     New commit message
help
)

# Navigate to the repository root
cd "$(git rev-parse --show-toplevel)" >/dev/null

# Edit the last commit message and content
git commit --amend --edit ${msg:+-m "$msg"}
