#!/bin/sh
# zz-vars [-S] [-n | -a] [-e] -f <envfile> [-P profile] <name>=<dir>... — the
# inputs the given workspaces declare in their package.json ("config.inputs",
# keyed by variable, "config.input", the deprecated array, and "config.ports":
# each port is the input <NAME>_PORT, defaulting to its port), resolved and
# printed as `export` lines to `eval`; running a command with them is zz-call's.
# An input is resolved from the caller's environment, then the env file, then
# its default. "config.output" (array of {var, as}) filters what is printed;
# without it, every input is printed under its name and its "as" alias.
#   -S  status only: print each input as set / required / optional, run nothing
#   -n  never ask: an unset input falls back to its default (not persisted) and
#       a required one is not enforced
#   -a  ask each unset input in turn on stdin (zz-prompt, no menu), persisting
#       the answer
#   -e  also persist the values already set in the environment
#   (default) on a terminal, offer to set the unset ones (zz-menu, then
#   zz-persist, secrets masked); fail (1) when a required one is still empty
#   (3 when the user aborted).
# <dir> (or a package.json file) is relative to the current directory. The env file is plain KEY=VALUE
# (zz-persist's format), read literally and never sourced.

. zz-colors

# --- arguments
eval "$(
    zz-args "Show, ask and resolve the inputs declared by workspaces" "$0" "$@" <<help
S - status_flag Status only: show each input, run nothing
f file envfile Env file holding the persisted values
P name profile Also export persisted values from <ZZ_PROFILE_DIR>/<name>.sh
n - noprompt Never ask: unset inputs fall back to their default, required ones are not enforced
a - sequential Ask each unset input in turn on stdin, without the menu
e - persistenv Also persist the values already set in the environment
# items items <name>=<dir> of each workspace
help
)"

# --- parameters
[ -n "$envfile" ] || {
    zz-log e "Usage: zz-vars [-S] [-n | -a] [-e] -f <envfile> [-P profile] <name>=<dir>..."
    exit 1
}
us=$(printf '\037')

# --- functions

# get_env_value <key>: value of <key> in the env file, as zz-persist reads it.
get_env_value() {
    local key="$1" # variable name (mandatory)

    [ ! -f "$envfile" ] || zz-persist -r -f "$envfile" "$key"
}

# get_pkg <dir>: the package.json of a workspace; a file given as <dir> is used as is.
get_pkg() {
    local dir="$1" # workspace directory, or a package.json file (mandatory)

    if [ -f "$dir" ]; then printf '%s' "$dir"; else printf '%s/package.json' "$dir"; fi
}

# get_inputs <owner> <dir>: inputs of one workspace: "VAR US description US
# required US default US owner US secret US as".
get_inputs() {
    local owner="$1" # workspace name (mandatory)
    local dir="$2"   # workspace directory holding package.json (mandatory)
    local pkg_file

    pkg_file=$(get_pkg "$dir")
    [ "$(jq '(.config.input // []) | length' "$pkg_file")" -eq 0 ] ||
        zz-log w "config.input in {U $pkg_file} is deprecated: use config.inputs"
    jq -r --arg n "$owner" '
      ((.config.input // [])[] | {var, question, default, secret, as}),
      ((.config.inputs // {}) | to_entries[] | {var: .key, question: (.value.question // .value.description), default: .value.default, secret: .value.secret, required: .value.required, as: .value.as}),
      ((.config.ports // [])[] | {var: ((.name | ascii_upcase) + "_PORT"), question: (.name + " port (" + (.access // "public") + ")"), default: (.port | tostring)})
      | [.var, (.question // ""), ((.required // false) | tostring), (.default // ""), $n, ((.secret // false) | tostring), (.as // .var)] | join("\u001f")' "$pkg_file"
}

# get_outputs <package.json>: "VAR US as" of each "config.output" entry.
get_outputs() {
    local pkg_file="$1" # package.json of one workspace (mandatory)

    jq -r '(.config.output // [])[] | [.var, (.as // .var)] | join("\u001f")' "$pkg_file"
}

# get_input_status <name> <required>: set / required / optional for a variable.
get_input_status() {
    local name="$1"     # variable name (mandatory)
    local required="$2" # "true" when the input is required (mandatory)

    if [ -n "$(eval "printf '%s' \"\${$name:-}\"")" ]; then
        echo set
    elif [ "$required" = true ]; then
        echo required
    else
        echo optional
    fi
}

# persist_profile <name> <value> <is_secret>: export the value from the
# profile snippet, when a profile is given. A secret is only flagged (-s):
# masking and owner-only files are zz-persist's job.
persist_profile() {
    local name="$1"      # variable name (mandatory)
    local value="$2"     # value to persist (mandatory)
    local is_secret="$3" # "true" or "false" (mandatory)

    [ -n "$profile" ] || return 0
    if [ "$is_secret" = true ]; then
        zz-persist -p "$profile" -s "$name" "$value"
    else
        zz-persist -p "$profile" "$name" "$value"
    fi
}

# persist_value <name> <value> <is_secret>: persist the value to the env file
# and the profile snippet.
persist_value() {
    local name="$1"      # variable name (mandatory)
    local value="$2"     # value to persist (mandatory)
    local is_secret="$3" # "true" or "false" (mandatory)

    if [ "$is_secret" = true ]; then
        zz-persist -f "$envfile" -s "$name" "$value"
    else
        zz-persist -f "$envfile" "$name" "$value"
    fi
    persist_profile "$name" "$value" "$is_secret"
}

# ask_value <var> <question> <default> <is_secret>: ask for an input and keep
# the answer: written to the env file (and the profile snippet) and exported.
# On a terminal zz-persist asks (masked for a secret, showing the stored
# value); off one, only -a gets here and zz-prompt reads the answer from stdin
# (a secret still goes through zz-persist, which then takes its default).
ask_value() {
    local var="$1"       # variable name (mandatory)
    local question="$2"  # what to ask (mandatory)
    local default="$3"   # offered answer, may be empty (mandatory)
    local is_secret="$4" # "true" or "false" (mandatory)
    local value

    if [ "$is_secret" = true ] || [ -t 0 ]; then
        if [ "$is_secret" = true ]; then set -- -s; else set --; fi
        [ -z "$default" ] || set -- "$@" -v "$default"
        zz-persist -q -f "$envfile" -i "$question" "$@" "$var"
    else
        zz-persist -q -f "$envfile" "$var" "$(zz-prompt "$question" "$default")"
    fi
    saved=1
    value=$(get_env_value "$var")
    [ -z "$value" ] || {
        export "$var=$value"
        persist_profile "$var" "$value" "$is_secret"
    }
}

# print_export <name> <var>: the `export` line of <name> with the value of <var>.
print_export() {
    local name="$1" # exported name (mandatory)
    local var="$2"  # variable holding the value (mandatory)
    local value

    case "$name" in
    "" | [0-9]* | *[!A-Za-z0-9_]*)
        zz-log e "Invalid output name: {Purple $name}"
        exit 1
        ;;
    esac
    eval "value=\${$var:-}"
    printf "export %s='%s'\n" "$name" "$(printf '%s' "$value" | sed "s/'/'\\\\''/g")"
}

# --- collect: every workspace's inputs, first declaration of a variable wins.
command -v jq >/dev/null 2>&1 || zz-install jq || exit 1
all_inputs=
pkgs=
for item in "$@"; do
    all_inputs="$all_inputs$(get_inputs "${item%%=*}" "${item#*=}")
"
    pkgs="$pkgs${pkgs:+:}$(get_pkg "${item#*=}")"
done
all_inputs=$(printf '%s' "$all_inputs" | awk -F"$us" 'NF && !seen[$1]++')

# Names go through eval and sed below: only shell identifiers are accepted.
bad=$(printf '%s\n' "$all_inputs" | awk -F"$us" 'NF && ($1 !~ /^[A-Za-z_][A-Za-z0-9_]*$/ || $7 !~ /^[A-Za-z_][A-Za-z0-9_]*$/) { print $1 }')
[ -z "$bad" ] || {
    zz-log e "Invalid input name (not a shell identifier): $(printf '%s' "$bad" | tr '\n' ' ')"
    exit 1
}

# The caller's environment first, then the env file, for what is unset.
# The final resolution, defaults and persistence are done below.
while IFS="$us" read -r var rest; do
    [ -n "$var" ] || continue
    if [ -z "$(eval "printf '%s' \"\${$var:-}\"")" ]; then
        value=$(get_env_value "$var")
        [ -n "$value" ] && eval "export $var=\$value"
    fi
done <<EXPLICIT
$all_inputs
EXPLICIT

# --- status view
if [ -n "$status_flag" ]; then
    while IFS="$us" read -r var desc req def owner secret as; do
        [ -n "$var" ] || continue
        printf '  input %-24s [%s] %s\n' "$var" "$(get_input_status "$var" "$req")" "$owner"
    done <<STATUS
$all_inputs
STATUS
    exit 0
fi

# --- ask: on a terminal, let the user set the inputs still unset.
saved=""
if [ -t 0 ] && [ -z "$noprompt$sequential" ] && [ -n "$all_inputs" ]; then
    while :; do
        set --
        unset_count=0
        while IFS="$us" read -r var desc req def owner secret as; do
            st=$(get_input_status "$var" "$req")
            [ "$st" = set ] || unset_count=$((unset_count + 1))
            set -- "$@" "$var=$(printf '%-24s' "$var") [$(printf '%-8s' "$st")] $owner${desc:+ - $desc}"
        done <<ROWS
$all_inputs
ROWS
        [ "$unset_count" -gt 0 ] || break
        rc=0
        choice=$(zz-menu -t "Inputs" \
            -f "  Number sets that input; <enter> proceeds with what's set, q quits." \
            "$@") || rc=$?
        case "$rc" in
        0) ;;
        1)
            zz-log n "Aborted, nothing changed"
            exit 3
            ;;
        *) break ;;
        esac
        row=$(printf '%s\n' "$all_inputs" | awk -F"$us" -v v="$choice" '$1 == v { print; exit }')
        desc=$(printf '%s' "$row" | cut -d"$us" -f2)
        def=$(printf '%s' "$row" | cut -d"$us" -f4)
        secret=$(printf '%s' "$row" | cut -d"$us" -f6)
        ask_value "$choice" "${choice}${desc:+ ($desc)}" "$def" "$secret"
    done
fi

# --- resolve: the environment (the env file's values included, above), then
# the default; -a asks for what is still unset. The reads are on fd 3, so
# that zz-prompt keeps the caller's stdin.
while IFS="$us" read -r var desc req def owner secret as <&3; do
    [ -n "$var" ] || continue
    eval "current=\${$var:-}"
    if [ -n "$current" ]; then
        [ -z "$persistenv" ] || persist_value "$var" "$current" "$secret"
    elif [ -n "$noprompt" ] || [ -z "$sequential" ]; then
        current=$def
    else
        ask_value "$var" "${desc:-Value for $var?}" "$def" "$secret"
        eval "current=\${$var:-}"
        [ -n "$current" ] || current=$def
    fi
    export "$var=$current"
    [ "$as" = "$var" ] || export "$as=$current"
done 3<<RESOLVE
$all_inputs
RESOLVE
# One line for all of them, instead of one "persisted" line per input.
[ -z "$saved" ] || zz-log i "Inputs saved in {U $envfile}"

# --- refuse a required input that is still empty (not with -n).
missing=0
while IFS="$us" read -r var desc req def owner secret as; do
    [ -n "$var" ] || continue
    [ -z "$noprompt" ] || break
    if [ "$(get_input_status "$var" "$req")" = required ]; then
        zz-log e "$var is required by '$owner' but is empty: set it, or skip the workspace with -s $owner."
        missing=1
    fi
done <<CHECK
$all_inputs
CHECK
[ "$missing" -eq 0 ] || exit 1

# --- print: the declared outputs, else every input under its name and alias.
outputs=
for pkg_file in $(printf '%s' "$pkgs" | tr ':' ' '); do
    outputs="$outputs$(get_outputs "$pkg_file")
"
done
outputs=$(printf '%s' "$outputs" | awk -F"$us" 'NF && !seen[$1]++')
if [ -n "$outputs" ]; then
    while IFS="$us" read -r var as; do
        print_export "$as" "$var"
    done <<OUTPUTS
$outputs
OUTPUTS
else
    while IFS="$us" read -r var desc req def owner secret as; do
        [ -n "$var" ] || continue
        print_export "$var" "$var"
        [ "$as" = "$var" ] || print_export "$as" "$var"
    done <<ALL
$all_inputs
ALL
fi
