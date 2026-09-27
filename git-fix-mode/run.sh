#!/bin/bash

# Reapply file mode changes (chmod) from the working tree diff without touching content

deleted_files=$(git ls-files --deleted)

diff_output=$(git diff -p -R --no-color | grep -E "^(diff|(old|new) mode)" --color=never)

if [ -n "$diff_output" ]; then
    if [ -n "$deleted_files" ]; then
        # Deleted files have no mode to restore and would make git apply fail
        echo "$diff_output" | grep -vF "$deleted_files" | git apply --allow-empty --no-index
    else
        echo "$diff_output" | git apply --allow-empty --no-index
    fi
fi

exit 0
