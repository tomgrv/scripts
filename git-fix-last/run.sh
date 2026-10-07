#!/bin/sh

eval $(
    zz-args "Edit the last commit message and content" $0 "$@" <<-help
        m   msg     msg     New commit message
help
)

cd "$(git rev-parse --show-toplevel)" >/dev/null

git commit --amend --edit ${msg:+-m "$msg"}
