#!/bin/sh

# Function to print help and manage arguments
eval $(
    zz_args "Set user.name and user.email to specified commit's author" $0 "$@" <<-help
        -   sha     sha         SHA of the commit to copy author from
help
)

# Navigate to the repository root
cd "$(git rev-parse --show-toplevel)" >/dev/null

# Remove global user configuration
git config --global --remove-section user 2>/dev/null || true

# Get the commit SHA and set user config based on its author
git getcommit -f $sha | xargs -I {} sh -c 'git config user.name "$(git log -1 --pretty=format:"%an" {})"; git config user.email "$(git log -1 --pretty=format:"%ae" {})"'
