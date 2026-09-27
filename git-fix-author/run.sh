#!/bin/sh

eval $(
    zz_args "Set user.name and user.email to specified commit's author" $0 "$@" <<-help
        -   sha     sha         SHA of the commit to copy author from
help
)

cd "$(git rev-parse --show-toplevel)" >/dev/null

git config --global --remove-section user 2>/dev/null || true

git getcommit -f $sha | xargs -I {} sh -c 'git config user.name "$(git log -1 --pretty=format:"%an" {})"; git config user.email "$(git log -1 --pretty=format:"%ae" {})"'
