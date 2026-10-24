#!/bin/sh
# Usage: zz-load [-r] [file|url|literal]
#   -r  require a file or URL: a missing file is an error, not a literal

# --- parameters
strict=
[ "$1" != -r ] || {
    strict=1
    shift
}
input="$1"

# --- run: a URL is downloaded, a file is printed, any other text is echoed
# (an error with -r), no argument reads stdin.
case "$input" in
http://* | https://*)
    zz-log - "Downloading file from {U $input}"
    curl -fsSL "$input" || {
        zz-log e "Unable to download file {U $input}"
        exit 1
    }
    ;;
"")
    [ -z "$strict" ] || {
        zz-log e "No source provided"
        exit 1
    }
    # Without a terminal guard a bare `zz-load` would hang waiting for input.
    [ ! -t 0 ] || {
        zz-log e "Usage: zz-load [-r] [file|url|literal]"
        exit 1
    }
    cat -
    ;;
*)
    if [ -f "$input" ]; then
        zz-log - "Reading from file: $input"
        cat -- "$input"
    elif [ -n "$strict" ]; then
        zz-log e "File {U $input} not found"
        exit 1
    else
        printf '%s\n' "$input"
    fi
    ;;
esac
