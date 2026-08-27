#!/bin/sh
# zz_call — ensure a caller's declared env vars are set before running
# something that needs them, vps-dispatch.sh style: ask for whatever's
# missing (zz_prompt), persist the answer so nothing asks again next time
# (zz_persist), then call — either exec a wrapped command with them
# exported, or with no command, print filtered/formatted `export
# VAR='value'` lines for the caller to `eval` (the same pattern zz_bindir
# uses for `$dir`).
#
# What to check/ask/set, and what to print back, is declared in a
# package.json (default: ./package.json — the caller's own, since every
# script in this repo has one right next to its run.sh) under `config`:
#
#   {
#     "config": {
#       "file": ".env",
#       "input": [
#         {"var": "DB_HOST", "question": "Database host?", "default": "localhost"},
#         {"var": "DB_PASSWORD", "question": "Database password?"}
#       ],
#       "output": ["DB_HOST", {"var": "DB_PASSWORD", "as": "PGPASSWORD"}]
#     }
#   }
#
# - "input": one entry per env var to ensure is set. Each is checked
#   against the environment first; only a missing (unset/empty) one is
#   asked for (via "question", offering "default") and persisted (to
#   "file", default ".env"). An already-set var is used as-is — nothing
#   is asked, and nothing new is persisted for it.
# - "output": which resolved vars to print as `export NAME='value'` lines,
#   and under what name. Each entry is either a plain var name (string) or
#   {"var": "<source>", "as": "<exported-as>"} to rename on the way out.
#   Defaults to every "input" var, printed under its own name, when
#   "output" is omitted.
#
# Usage:
#   zz_call [-p package.json] [command [args...]]

set -e

zz_use zz_colors zz_args zz_prompt zz_persist jq
. zz_colors

eval $(
    zz_args "Resolve a caller's declared env vars (ask+persist if missing), then run a command" $0 "$@" <<-help
        p package   package     package.json to read config.input/config.output from (default: ./package.json)
        # cmd        cmd         Command (and args) to run once every input var is resolved
help
)

pkg="${package:-./package.json}"
[ -f "$pkg" ] || { zz_log e "No package.json found at {U $pkg}"; exit 1; }

file=$(jq -r '.config.file // ".env"' "$pkg")

# jq's own output is looped over via a captured command substitution, not
# a pipe: `jq ... | while read ...` would run the loop in a subshell, and
# the `export`s inside it would be lost the moment that subshell exits.
_old_ifs=$IFS
_input_entries=$(jq -c '.config.input // [] | .[]' "$pkg")
IFS='
'
for _entry in $_input_entries; do
    IFS="$_old_ifs"
    var=$(printf '%s' "$_entry" | jq -r '.var')
    question=$(printf '%s' "$_entry" | jq -r '.question // empty')
    default=$(printf '%s' "$_entry" | jq -r '.default // empty')

    case "$var" in
    [A-Za-z_][A-Za-z0-9_]*) ;;
    *)
        zz_log e "Invalid variable name in {U $pkg} config.input: {Purple $var}"
        exit 1
        ;;
    esac

    eval "_current=\${$var:-}"
    if [ -z "$_current" ]; then
        _current=$(zz_prompt "${question:-Value for $var?}" "$default")
        zz_persist -f "$file" "$var" "$_current"
    fi
    export "$var=$_current"
    IFS='
'
done
IFS="$_old_ifs"

if [ -n "$cmd" ]; then
    eval exec $cmd
    exit 0
fi

_outputs=$(jq -c '.config.output // (.config.input // [] | map(.var))' "$pkg")
_output_entries=$(printf '%s' "$_outputs" | jq -c '.[]')
IFS='
'
for _entry in $_output_entries; do
    IFS="$_old_ifs"
    if printf '%s' "$_entry" | jq -e 'type == "string"' >/dev/null 2>&1; then
        src=$(printf '%s' "$_entry" | jq -r '.')
        as="$src"
    else
        src=$(printf '%s' "$_entry" | jq -r '.var')
        as=$(printf '%s' "$_entry" | jq -r '.as // .var')
    fi
    eval "_val=\${$src:-}"
    echo "export ${as}='$(printf '%s' "$_val" | sed "s/'/'\\\\''/g")'"
    IFS='
'
done
IFS="$_old_ifs"
