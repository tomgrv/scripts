#!/bin/sh
# zz_wrap — ensure an env var is set before running something that needs
# it, vps-dispatch.sh style: ask for it if it's missing (zz_prompt),
# persist the answer so nothing asks again next time (zz_persist), then
# call — either exec a wrapped command with it exported, or, with no
# command given, print an `export VAR='value'` line for the caller to
# `eval` into its own shell (the same pattern zz_bindir uses for `$dir`).
#
# Usage:
#   zz_wrap -v VAR [-q "question?"] [-d default] [-f file] [command [args...]]
#
# If $VAR is already set (non-empty) in the environment, it's used as-is —
# nothing is asked, and nothing new is persisted (there's nothing new to
# persist).

set -e

zz_use zz_colors zz_args zz_prompt zz_persist
. zz_colors

eval $(
    zz_args "Ensure an env var is set (asking + persisting if missing), then run a command" $0 "$@" <<-help
        v var       var         Environment variable name to ensure is set
        q question  question    Prompt to ask if missing (default: "Value for <var>?")
        d default   default     Default value offered when prompting
        f file      file        Persist the answer to this env file (default: .env)
        # cmd        cmd         Command (and args) to run once <var> is resolved
help
)

if [ -z "$var" ]; then
    zz_log e "Usage: zz_wrap -v VAR [-q question] [-d default] [-f file] [command [args...]]"
    exit 1
fi

case "$var" in
[A-Za-z_][A-Za-z0-9_]*) ;;
*)
    zz_log e "Invalid variable name: {Purple $var}"
    exit 1
    ;;
esac

eval "_current=\${$var:-}"

if [ -z "$_current" ]; then
    _current=$(zz_prompt "${question:-Value for $var?}" "$default")
    export "$var=$_current"
    zz_persist -f "${file:-.env}" "$var" "$_current"
else
    export "$var=$_current"
fi

if [ -n "$cmd" ]; then
    eval exec $cmd
else
    echo "export $var='$(printf '%s' "$_current" | sed "s/'/'\\\\''/g")'"
fi
