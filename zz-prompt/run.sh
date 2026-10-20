#!/bin/sh
# zz-prompt [-s] [-e] <question> [default] — interactive free-form input.
# The prompt is written to stderr so stdout carries only the entered value
# (or the default when the user just presses Enter). POSIX read (dash-safe).
#   -s  secret: the answer is not echoed and the default is shown as [***]
#   -e  fail (status 1) when input ends instead of answering with the default

. zz-colors

# --- arguments
eval "$(zz-args "Interactive free-form input" "$0" "$@" <<help
s - secret Secret: masked input, default shown as ***
e - eof_fail Exit 1 when input ends (no answer at all)
- question question Question to ask
- default default Value used when the user just presses Enter
help
)"

# --- prompt
shown=$default
[ -z "$secret" ] || shown=***

if [ -n "$default" ]; then
    printf '%b' "${BBlue}#${None} $question ${BBlue}[$shown]${None} " >&2
else
    printf '%b' "${BBlue}#${None} $question " >&2
fi

# --- read the answer (echo off for a secret, restored even when read fails)
stty_orig=
if [ -n "$secret" ]; then
    stty_orig=$(stty -g 2>/dev/null) || stty_orig=
    [ -z "$stty_orig" ] || stty -echo 2>/dev/null
fi
eof=
read -r value || eof=1
if [ -n "$stty_orig" ]; then
    stty "$stty_orig" 2>/dev/null
    echo >&2
fi

[ -z "$eof" ] || [ -z "$eof_fail" ] || [ -n "$value" ] || exit 1
[ -z "$value" ] && value=$default
printf '%s\n' "$value"
