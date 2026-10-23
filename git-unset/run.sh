#!/bin/sh

eval $(
    zz-args "Unset all Git config keys starting with the given prefix" $0 "$@" <<help
        - prefix prefix config key prefix (default: any lower-case prefix)
        - scope  scope  git config scope flag (default: --local)
help
)

cd "$(git rev-parse --show-toplevel)" >/dev/null

git config ${2:---local} --get-regexp "^${1:-[a-z]+}\\." | cut -d ' ' -f 1 | while read alias_key; do
    git config ${2:---local} --unset-all "$alias_key"
done
