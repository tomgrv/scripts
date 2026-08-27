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
# script in this repo has one right next to its run.sh) under `config`.
# "input" and "output" entries share one schema:
#
#   {"var": "<name>", "as": "<export-name>", "question": "...", "default": "..."}
#
# - "var" (required): the env var checked, prompted for, and persisted.
# - "as" (optional, default: var): the name it's exported/printed under —
#   lets a command see a differently-named var than the one that was
#   actually asked/persisted (e.g. ask for "DB_PASSWORD", export it to a
#   psql-invoked command as "PGPASSWORD").
# - "question"/"default": only meaningful on an "input" entry — offered to
#   zz_prompt when "var" is missing.
#
#   {
#     "config": {
#       "file": ".env",
#       "input": [
#         {"var": "DB_HOST", "question": "Database host?", "default": "localhost"},
#         {"var": "DB_PASSWORD", "question": "Database password?", "as": "PGPASSWORD"}
#       ],
#       "output": [{"var": "DB_HOST"}, {"var": "DB_PASSWORD", "as": "PGPASSWORD"}]
#     }
#   }
#
# - "input": one entry per env var to ensure is set. Each is checked
#   against the environment first; only a missing (unset/empty) one is
#   asked for (via "question", offering "default") and persisted (to
#   "file", default ".env") — always under "var", regardless of "as". An
#   already-set var is used as-is — nothing is asked, and nothing new is
#   persisted for it. Every input entry is exported under "var", and
#   additionally under "as" when the two differ.
# - "output": which resolved vars to print as `export <as>='value'` lines,
#   reading each one's current value from "var". Defaults to the "input"
#   list itself when "output" is omitted.
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

# Sets var/as/question/default from one config.input/config.output entry.
# "as" defaults to "var" so every caller can rely on it being set.
_parse_entry() {
    var=$(printf '%s' "$1" | jq -r '.var')
    as=$(printf '%s' "$1" | jq -r '.as // .var')
    question=$(printf '%s' "$1" | jq -r '.question // empty')
    default=$(printf '%s' "$1" | jq -r '.default // empty')

    case "$var" in
    [A-Za-z_][A-Za-z0-9_]*) ;;
    *)
        zz_log e "Invalid variable name in {U $pkg}: {Purple $var}"
        exit 1
        ;;
    esac
}

# jq's own output is looped over via a captured command substitution, not
# a pipe: `jq ... | while read ...` would run the loop in a subshell, and
# the `export`s inside it would be lost the moment that subshell exits.
_old_ifs=$IFS
_input_entries=$(jq -c '.config.input // [] | .[]' "$pkg")
IFS='
'
for _entry in $_input_entries; do
    IFS="$_old_ifs"
    _parse_entry "$_entry"

    eval "_current=\${$var:-}"
    if [ -z "$_current" ]; then
        _current=$(zz_prompt "${question:-Value for $var?}" "$default")
        zz_persist -f "$file" "$var" "$_current"
    fi
    export "$var=$_current"
    [ "$as" != "$var" ] && export "$as=$_current"
    IFS='
'
done
IFS="$_old_ifs"

if [ -n "$cmd" ]; then
    eval exec $cmd
    exit 0
fi

_output_entries=$(jq -c '(.config.output // .config.input // []) | .[]' "$pkg")
IFS='
'
for _entry in $_output_entries; do
    IFS="$_old_ifs"
    _parse_entry "$_entry"

    eval "_val=\${$var:-}"
    echo "export ${as}='$(printf '%s' "$_val" | sed "s/'/'\\\\''/g")'"
    IFS='
'
done
IFS="$_old_ifs"
