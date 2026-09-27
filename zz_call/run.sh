#!/bin/sh
# zz_call — resolve a caller's declared env vars (prompt+persist if
# missing via zz_prompt/zz_persist), then either exec a wrapped command
# with them exported, or print `export VAR='value'` lines for the caller
# to `eval`.
#
# Config comes from a package.json (default: ./package.json) under
# `config`:
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
# - "var" (required): the env var checked, prompted for, and persisted.
# - "as" (optional, default: var): export/print name, for a command that
#   expects a different name (e.g. ask "DB_PASSWORD", export "PGPASSWORD").
# - "question"/"default": used for "input" entries when "var" is unset.
# - "input": vars to ensure are set — already-set ones are used as-is;
#   missing ones are prompted, persisted to "file" (default ".env"), and
#   exported under both "var" and "as".
# - "output": which resolved vars to print as `export <as>='value'`.
#   Defaults to "input" when omitted.
#
# Usage:
#   zz_call [-p package.json] [command [args...]]

set -e

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

if [ "$#" -gt 0 ]; then
    exec "$@"
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
