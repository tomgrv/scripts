#!/bin/sh
# zz_ask <options> <question...> — interactive single-char confirm.
# <options> e.g. "Yn" — the uppercase letter is the default. Prints the
# chosen option (lowercased) to stdout.

. zz_colors

default=$(printf '%s' "$1" | tr -dc 'A-Z' | tr '[:upper:]' '[:lower:]')
options=$1
shift

echo "${BBlue}#${None} $* ${BBlue}[${options}]${End}" >&2

while true; do

    read -r confirm

    if [ -z "$confirm" ]; then
        echo "$default"
        break
    fi

    if echo "$options" | grep -q -i "$confirm"; then
        echo "$confirm"
        break
    fi

    zz_log w "Please enter a valid option from [${options}] (default: ${default}):"
done
