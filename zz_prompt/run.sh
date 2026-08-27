#!/bin/sh

# zz_prompt.sh — interactive free-form input.
# Usage: value=$(zz_prompt "Question?" [default])
# The prompt is written to stderr so stdout carries only the entered value
# (or the default when the user just presses Enter). POSIX read (dash-safe).

. zz_colors

prompt=$1
default=$2

if [ -n "$default" ]; then
    printf '%b' "${BBlue}#${None} $prompt ${BBlue}[$default]${None} " >&2
else
    printf '%b' "${BBlue}#${None} $prompt " >&2
fi

read -r value
[ -z "$value" ] && value=$default
printf '%s\n' "$value"
