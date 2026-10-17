#!/bin/sh
# zz-call — resolve a caller's declared env vars (prompt+persist if
# missing via zz-prompt/zz-persist), then either exec a wrapped command
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
# Also accepted: "engines.zz-setup.inputs" (object keyed by var: description, default,
# secret) next to "config.input", several package.json files at once
# (-p a.json:b.json), and a persisted-value lookup in the env file (read
# literally, never sourced): environment first, then the file, then a prompt.
#
# Usage:
#   zz-call [-p package.json[:more.json]] [-f envfile] [-P profile] [-n] [-e]
#           [command [args...]]
#   -f  env file to read/persist (default: config.file of the first package.json, else .env)
#   -P  also export persisted values from /etc/profile.d/<profile>.sh
#   -n  never prompt: a missing var falls back to its default, not persisted
#   -e  also persist values already set in the environment

set -e

. zz-colors

eval $(
    zz-args "Resolve a caller's declared env vars (ask+persist if missing), then run a command" $0 "$@" <<-help
        p package   package     package.json file(s) to read, ':'-separated (default: ./package.json)
        f file      envfile     Env file to read and persist to (default: config.file, else .env)
        P profile   profile     Also export persisted values from /etc/profile.d/<profile>.sh
        n -         noprompt    Never prompt: missing vars fall back to their default (not persisted)
        e -         persistenv  Also persist values already set in the environment
        # cmd        cmd         Command (and args) to run once every input var is resolved
help
)

pkgs="${package:-./package.json}"
first=${pkgs%%:*}
for _p in $(printf '%s' "$pkgs" | tr ':' ' '); do
    [ -f "$_p" ] || { zz-log e "No package.json found at {U $_p}"; exit 1; }
done
pkg=$first

file="${envfile:-$(jq -r '.config.file // ".env"' "$first")}"

# Collect input entries from every package: config.input plus engines.zz-setup.inputs
# (normalised to the same shape), first definition of a var wins.
_collect() {
    for _p in $(printf '%s' "$pkgs" | tr ':' ' '); do
        jq -c "$1" "$_p"
    done | jq -c -s 'reduce .[] as $e ([]; if any(.[]; .var == $e.var) then . else . + [$e] end) | .[]'
}
_inputs='(.config.input // [])[], (((.engines["zz-setup"] | objects).inputs // {}) | to_entries[] | {var: .key, question: .value.description, default: .value.default, secret: .value.secret})'
_input_entries=$(_collect "$_inputs")
_output_entries=$(_collect '(.config.output // [])[]')
[ -n "$_output_entries" ] || _output_entries=$_input_entries

# Sets var/as/question/default/secret from one input/output entry.
# "as" defaults to "var" so every caller can rely on it being set.
_parse_entry() {
    var=$(printf '%s' "$1" | jq -r '.var')
    as=$(printf '%s' "$1" | jq -r '.as // .var')
    question=$(printf '%s' "$1" | jq -r '.question // empty')
    default=$(printf '%s' "$1" | jq -r '.default // empty')
    secret=$(printf '%s' "$1" | jq -r '.secret // false')

    case "$var" in
    "" | [0-9]* | *[!A-Za-z0-9_]*)
        zz-log e "Invalid variable name in {U $pkgs}: {Purple $var}"
        exit 1
        ;;
    esac
}

# Value of $1 in the env file, read literally (the file is never sourced).
_file_get() { [ ! -f "$file" ] || sed -n "s/^$1=//p" "$file" | tail -n1; }

# Persisting, secrets included, is zz-persist's job alone: a secret entry is
# only flagged (-s), and zz-persist masks, restricts the file and refuses.
# $1=var $2=value $3=secret(true|false)
_flag() { [ "$1" != true ] || printf '%s' -s; }

_persist_profile() {
    [ -n "$profile" ] || return 0
    _q=$(printf '%s' "$2" | sed "s/'/'\\\\''/g")
    zz-persist -p "$profile" $(_flag "$3") "$1" "'$_q'"
}

_persist() {
    zz-persist -f "$file" $(_flag "$3") "$1" "$2"
    _persist_profile "$1" "$2" "$3"
}

# jq's own output is looped over via a captured command substitution, not
# a pipe: `jq ... | while read ...` would run the loop in a subshell, and
# the `export`s inside it would be lost the moment that subshell exits.
_old_ifs=$IFS
IFS='
'
for _entry in $_input_entries; do
    IFS="$_old_ifs"
    _parse_entry "$_entry"

    eval "_current=\${$var:-}"
    if [ -n "$_current" ]; then
        # Set by the caller: used as-is, persisted only on request.
        [ -z "$persistenv" ] || _persist "$var" "$_current" "$secret"
    else
        _current=$(_file_get "$var")
        if [ -n "$_current" ]; then
            :
        elif [ -n "$noprompt" ]; then
            _current=$default
        elif [ "$secret" = true ]; then
            # Asked and stored by zz-persist (masked, owner-only).
            zz-persist -f "$file" -s -i "${question:-$var}" ${default:+-v "$default"} "$var"
            _current=$(_file_get "$var")
            [ -z "$_current" ] || _persist_profile "$var" "$_current" true
        else
            _current=$(zz-prompt "${question:-Value for $var?}" "$default")
            _persist "$var" "$_current" false
        fi
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
