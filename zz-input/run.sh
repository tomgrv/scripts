#!/bin/sh
# Usage: zz-input [input] [description]

input="$1"

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
