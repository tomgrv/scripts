#!/bin/sh
# zz-ask <options> <question...> — interactive single-char confirm.
# <options> e.g. "Yn" — the uppercase letter is the default. Prints the
# chosen option (lowercased) to stdout. A wrapper over zz-prompt -c, the
# shared reader.

. zz-colors

# --- arguments
eval "$(zz-args "Interactive single-char confirm" "$0" "$@" <<help
- options options Choices, the uppercase letter is the default (e.g. Yn)
+ question question Question to ask
help
)"

# --- ask
exec zz-prompt -c "$options" "$question"
