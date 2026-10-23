#!/bin/sh
# Usage: zz-load [file|literal]

# --- parameters
input="$1"

# --- run: a file is printed, any other text is echoed, no argument reads stdin.

if [ -n "$input" ]; then
    if [ -f "$input" ]; then
        zz-log - "Reading from file: $input"
        cat -- "$input"
    else
        echo "$input"
    fi
else
    cat -
fi
