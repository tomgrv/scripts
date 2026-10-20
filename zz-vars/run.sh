#!/bin/sh
# zz-vars [-S] -f <envfile> [-P profile] <name>=<dir>... — the inputs the
# given workspaces declare in their package.json ("config.inputs", keyed by
# variable, and "config.input", the zz-call array).
#   -S  status only: print each input as set / required / optional, run nothing
#   (default) on a terminal, offer to set the unset ones (zz-menu, then
#   zz-persist, secrets masked), resolve all of them with zz-call (caller's
#   environment, env file, default; nothing else is prompted), fail (1) when a
#   required one is still empty (3 when the user aborted), and print the `export` lines to `eval`.
# <dir> is relative to the current directory. The env file is plain KEY=VALUE
# (zz-persist's format), read literally and never sourced.

. zz-colors

# --- arguments
eval "$(zz-args "Show, ask and resolve the inputs declared by workspaces" "$0" "$@" <<help
S - status_flag Status only: show each input, run nothing
f file envfile Env file holding the persisted values
P name profile Also export persisted values from <ZZ_PROFILE_DIR>/<name>.sh
# items items <name>=<dir> of each workspace
help
)"

# --- parameters
[ -n "$envfile" ] || {
    zz-log e "Usage: zz-vars [-S] -f <envfile> [-P profile] <name>=<dir>..."
    exit 1
}
us=$(printf '\037')

# --- functions

# Value of KEY in the env file, read literally.
env_get() { [ ! -f "$envfile" ] || sed -n "s/^$1=//p" "$envfile" | tail -n1; }

# Inputs of one workspace: "VAR US description US required US default US owner
# US secret" ($1=owner name, $2=dir).
inputs_of() {
    jq -r --arg n "$1" '
      ((.config.inputs // {}) | to_entries[]
         | [.key, (.value.description // ""), ((.value.required // false) | tostring), (.value.default // ""), $n, ((.value.secret // false) | tostring)] | join("\u001f")),
      ((.config.input // [])[]
         | [.var, (.question // ""), "false", (.default // ""), $n, "false"] | join("\u001f"))' "$2/package.json"
}

# set / required / optional for variable $1 (required flag $2).
input_status() {
    if [ -n "$(eval "printf '%s' \"\${$1:-}\"")" ]; then
        echo set
    elif [ "$2" = true ]; then
        echo required
    else
        echo optional
    fi
}

# --- collect: every workspace's inputs, first declaration of a variable wins.
command -v jq >/dev/null 2>&1 || zz-install jq || exit 1
all_inputs=
pkgs=
for item in "$@"; do
    all_inputs="$all_inputs$(inputs_of "${item%%=*}" "${item#*=}")
"
    pkgs="$pkgs${pkgs:+:}${item#*=}/package.json"
done
all_inputs=$(printf '%s' "$all_inputs" | awk -F"$us" 'NF && !seen[$1]++')

# The caller's environment first, then the env file, for what is unset.
# The final resolution, defaults and persistence are zz-call's, below.
while IFS="$us" read -r var _rest; do
    [ -n "$var" ] || continue
    if [ -z "$(eval "printf '%s' \"\${$var:-}\"")" ]; then
        _v=$(env_get "$var")
        [ -n "$_v" ] && eval "export $var=\$_v"
    fi
done <<EXPLICIT
$all_inputs
EXPLICIT

# --- status view
if [ -n "$status_flag" ]; then
    while IFS="$us" read -r var desc req def owner secret; do
        [ -n "$var" ] || continue
        printf '  input %-24s [%s] %s\n' "$var" "$(input_status "$var" "$req")" "$owner"
    done <<STATUS
$all_inputs
STATUS
    exit 0
fi

# --- ask: on a terminal, let the user set the inputs still unset.
if [ -t 0 ] && [ -n "$all_inputs" ]; then
    while :; do
        set --
        unset_count=0
        while IFS="$us" read -r var desc req def owner secret; do
            st=$(input_status "$var" "$req")
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
        # zz-persist asks (masked with -s), shows the stored value and writes
        # it; the answer is then read back into this run.
        if [ "$secret" = true ]; then set -- -s; else set --; fi
        [ -z "$def" ] || set -- "$@" -v "$def"
        zz-persist -f "$envfile" -i "${choice}${desc:+ ($desc)}" "$@" "$choice"
        _v=$(env_get "$choice")
        [ -z "$_v" ] || eval "export $choice=\$_v"
    done
fi

# --- resolve with zz-call, then refuse a required input that is still empty.
out=
if [ -n "$pkgs" ]; then
    out=$(zz-call -n -e -f "$envfile" ${profile:+-P "$profile"} -p "$pkgs")
    eval "$out"
fi
missing=0
while IFS="$us" read -r var desc req def owner secret; do
    [ -n "$var" ] || continue
    if [ "$(input_status "$var" "$req")" = required ]; then
        zz-log e "$var is required by '$owner' but is empty: set it, or skip the workspace with -s $owner."
        missing=1
    fi
done <<CHECK
$all_inputs
CHECK
[ "$missing" -eq 0 ] || exit 1
[ -z "$out" ] || printf '%s\n' "$out"
