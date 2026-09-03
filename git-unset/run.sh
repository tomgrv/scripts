#!/bin/sh

#### Goto repository root
cd "$(git rev-parse --show-toplevel)" >/dev/null

#### Unset all git config keys starting with the given prefix
git config ${2:---local} --get-regexp "^${1:-[a-z]+}\\." | cut -d ' ' -f 1 | while read alias_key; do
     git config ${2:---local} --unset-all "$alias_key"
done
