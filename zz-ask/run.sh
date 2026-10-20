#!/bin/sh
# zz-ask <options> <question...> — interactive single-char confirm.
# <options> e.g. "Yn" — the uppercase letter is the default. Prints the
# chosen option (lowercased) to stdout.

. zz-colors

# --- arguments
eval "$(zz-args "Interactive single-char confirm" "$0" "$@" <<help
- options options Choices, the uppercase letter is the default (e.g. Yn)
+ question question Question to ask
help
)"

# --- prompt
default=$(printf '%s' "$options" | tr -dc 'A-Z' | tr '[:upper:]' '[:lower:]')

echo "${BBlue}#${None} $question ${BBlue}[${options}]${End}" >&2

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

    zz-log w "Please enter a valid option from [${options}] (default: ${default}):"
done
