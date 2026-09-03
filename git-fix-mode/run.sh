#!/bin/bash

# Fix file mode changes from diff
# Handle the case where no deleted files exist

# Get the list of deleted files
deleted_files=$(git ls-files --deleted)

# Generate the diff with mode information
diff_output=$(git diff -p -R --no-color | grep -E "^(diff|(old|new) mode)" --color=never)

# If we have diff output
if [ -n "$diff_output" ]; then
    if [ -n "$deleted_files" ]; then
        # Filter out deleted files
        echo "$diff_output" | grep -vF "$deleted_files" | git apply --allow-empty --no-index
    else
        # No deleted files, apply all mode changes
        echo "$diff_output" | git apply --allow-empty --no-index
    fi
fi

exit 0
