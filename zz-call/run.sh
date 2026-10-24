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
# "config.inputs" (object keyed by var: description, default, required, secret,
# as) is the canonical form and does everything "config.input" does, "as"
# included; "config.input" is kept as a deprecated alias. Also accepted:
# several package.json files at once
# (-p a.json:b.json), and a persisted-value lookup in the env file (read
# literally, never sourced): environment first, then the file, then a prompt.
#
# Usage:
#   zz-call [-p package.json[:more.json]] [-f envfile] [-P profile] [-n] [-e] [-l]
#           [command [args...]]
#   -f  env file to read/persist (default: config.file of the first package.json, else .env)
#   -P  also export persisted values from <ZZ_PROFILE_DIR, default /etc/profile.d>/<profile>.sh
#   -n  never prompt: a missing var falls back to its default, not persisted
#   -e  also persist values already set in the environment
#   -l  list the declared inputs, one per line, fields separated by \037:
#       var, question, required, default, secret; resolve nothing

set -e

. zz-colors

# --- arguments
eval "$(
    zz-args "Resolve a caller's declared env vars (ask+persist if missing), then run a command" $0 "$@" <<help
        p package   package     package.json file(s) to read, ':'-separated (default: ./package.json)
        f file      envfile     Env file to read and persist to (default: config.file, else .env)
        P profile   profile     Also export persisted values from <ZZ_PROFILE_DIR, default /etc/profile.d>/<profile>.sh
        n -         noprompt    Never prompt: missing vars fall back to their default (not persisted)
        e -         persistenv  Also persist values already set in the environment
        l -         list        List the declared inputs (var, question, required, default, secret), resolve nothing
        # cmd        cmd         Command (and args) to run once every input var is resolved
help
)"

# --- parameters: the package.json files and the env file.
pkgs="${package:-./package.json}"
first=${pkgs%%:*}
for pkg_file in $(printf '%s' "$pkgs" | tr ':' ' '); do
    [ -f "$pkg_file" ] || {
        zz-log e "No package.json found at {U $pkg_file}"
        exit 1
    }
    [ "$(jq '(.config.input // []) | length' "$pkg_file")" -eq 0 ] ||
        zz-log w "config.input in {U $pkg_file} is deprecated: use config.inputs"
done
pkg=$first

file="${envfile:-$(jq -r '.config.file // ".env"' "$first")}"

# --- functions

# collect_entries <filter>: collect input entries from every package:
# config.input plus config.inputs (normalised to the same shape), first
# definition of a var wins.
collect_entries() {
    local filter="$1" # jq filter selecting the entries of one package (mandatory)
    local pkg_file

    for pkg_file in $(printf '%s' "$pkgs" | tr ':' ' '); do
        jq -c "$filter" "$pkg_file"
    done | jq -c -s 'reduce .[] as $e ([]; if any(.[]; .var == $e.var) then . else . + [$e] end) | .[]'
}
# parse_entry <json>: set the script-wide var/as/question/default/secret from
# one input/output entry. "as" defaults to "var" so every caller can rely on it
# being set.
parse_entry() {
    local json="$1" # one entry, as a JSON object (mandatory)

    var=$(printf '%s' "$json" | jq -r '.var')
    as=$(printf '%s' "$json" | jq -r '.as // .var')
    question=$(printf '%s' "$json" | jq -r '.question // empty')
    default=$(printf '%s' "$json" | jq -r '.default // empty')
    secret=$(printf '%s' "$json" | jq -r '.secret // false')

    case "$var" in
    "" | [0-9]* | *[!A-Za-z0-9_]*)
        zz-log e "Invalid variable name in {U $pkgs}: {Purple $var}"
        exit 1
        ;;
    esac
}

# get_file_value <key>: value of <key> in the env file, read literally (the
# file is never sourced).
get_file_value() {
    local key="$1" # variable name (mandatory)

    [ ! -f "$file" ] || sed -n "s/^$key=//p" "$file" | tail -n1
}

# get_secret_flag <is_secret>: persisting, secrets included, is zz-persist's
# job alone: a secret entry is only flagged (-s), and zz-persist masks,
# restricts the file and refuses.
get_secret_flag() {
    local is_secret="$1" # "true" when the value is a secret (mandatory)

    [ "$is_secret" != true ] || printf '%s' -s
}

# persist_profile <name> <value> <is_secret>: export the value from the
# profile snippet, when a profile is given.
persist_profile() {
    local name="$1"      # variable name (mandatory)
    local value="$2"     # value to persist (mandatory)
    local is_secret="$3" # "true" or "false" (mandatory)

    [ -n "$profile" ] || return 0
    # zz-persist quotes the value for the sourced snippet.
    zz-persist -p "$profile" $(get_secret_flag "$is_secret") "$name" "$value"
}

# persist_value <name> <value> <is_secret>: persist the value to the env file
# and the profile snippet.
persist_value() {
    local name="$1"      # variable name (mandatory)
    local value="$2"     # value to persist (mandatory)
    local is_secret="$3" # "true" or "false" (mandatory)

    zz-persist -f "$file" $(get_secret_flag "$is_secret") "$name" "$value"
    persist_profile "$name" "$value" "$is_secret"
}

# --- resolve: the declared inputs, then (when no command) the outputs.
# config.ports ([{name, port, access}]) are inputs too: <NAME>_PORT, defaulting to the port.
inputs_filter='(.config.input // [])[], ((.config.inputs // {}) | to_entries[] | {var: .key, question: (.value.question // .value.description), default: .value.default, secret: .value.secret, required: .value.required, as: .value.as}), ((.config.ports // [])[] | {var: ((.name | ascii_upcase) + "_PORT"), question: (.name + " port (" + (.access // "public") + ")"), default: (.port | tostring)})'
input_entries=$(collect_entries "$inputs_filter")
output_entries=$(collect_entries '(.config.output // [])[]')

if [ -n "$list" ]; then
    [ -z "$input_entries" ] || printf '%s\n' "$input_entries" | jq -r '[.var, (.question // ""), ((.required // false) | tostring), (.default // ""), ((.secret // false) | tostring)] | join("\u001f")'
    exit 0
fi
[ -n "$output_entries" ] || output_entries=$input_entries

# Each input comes from the environment, then the env file, then a prompt (or
# its default with -n).
# jq's own output is looped over via a captured command substitution, not
# a pipe: `jq ... | while read ...` would run the loop in a subshell, and
# the `export`s inside it would be lost the moment that subshell exits.
old_ifs=$IFS
IFS='
'
for entry in $input_entries; do
    IFS="$old_ifs"
    parse_entry "$entry"

    eval "current=\${$var:-}"
    if [ -n "$current" ]; then
        # Set by the caller: used as-is, persisted only on request.
        [ -z "$persistenv" ] || persist_value "$var" "$current" "$secret"
    else
        current=$(get_file_value "$var")
        if [ -n "$current" ]; then
            :
        elif [ -n "$noprompt" ]; then
            current=$default
        elif [ "$secret" = true ]; then
            # Asked and stored by zz-persist (masked, owner-only).
            zz-persist -f "$file" -s -i "${question:-$var}" ${default:+-v "$default"} "$var"
            current=$(get_file_value "$var")
            [ -z "$current" ] || persist_profile "$var" "$current" true
        else
            current=$(zz-prompt "${question:-Value for $var?}" "$default")
            persist_value "$var" "$current" false
        fi
    fi
    export "$var=$current"
    [ "$as" != "$var" ] && export "$as=$current"
    IFS='
'
done
IFS="$old_ifs"

# With a command, run it with everything resolved in its environment.
if [ "$#" -gt 0 ]; then
    exec "$@"
fi

# Without one, print the declared outputs as `export` lines to eval.
IFS='
'
for entry in $output_entries; do
    IFS="$old_ifs"
    parse_entry "$entry"

    eval "value=\${$var:-}"
    echo "export ${as}='$(printf '%s' "$value" | sed "s/'/'\\\\''/g")'"
    IFS='
'
done
IFS="$old_ifs"
