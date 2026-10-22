#!/bin/sh
# zz-setup <org>/<repo>[@<ref>] [args...] — fetch a GitHub repo and run it
# the way a workspace installer does:
#   1. shallow clone (or fast-forward) into a fixed directory;
#   2. if the root package.json lists workspaces, propose the runnable ones
#      (skip/up/down menu, dependencies auto-enabled), then list the inputs
#      they declare, offer to set them (persisted to an env file), and run
#      each selected workspace's bin;
#   3. otherwise (or with ZZ_SETUP_ENTRY) exec the repo's own installer with
#      the remaining arguments: <repo>-setup/run.sh, setup.sh, run.sh.
#
# Runnable workspace: has a "bin" and an "engines.zz-setup" field in its
# package.json (the run context, any value such as "*"). Its optional "config"
# holds the settings: "order" sorts, "default" preselects, "conflicts" lists
# workspaces that cannot be enabled together with it, "inputs" (or
# "config.input") declare inputs. Its (first) bin gets "up"/"down" as argument.
#
# The state of each workspace you run is remembered in the env file
# (ZZ_STATE_<name>=up|skip) and preselects the next menu.
#
# Options (parsed with zz-args, after the repository; names are space- or
# comma-separated): -w enable, -s skip, -d down, -o only these, -D down all,
# -F force down, -S status only, -h. No options on a terminal opens the menu.
#
# Env: ZZ_SETUP_REF (default main; "@<ref>" wins), ZZ_SETUP_DIR (parent of the
# checkout; default /opt as root, else ~/.local/share), ZZ_SETUP_URL_BASE
# (default https://github.com), ZZ_SETUP_ENTRY, ZZ_SETUP_ENV_FILE (inputs; default
# <ZZ_ETC_DIR, default /etc>/<repo>.env as root, else <checkout>/.env, read
# literally, written by zz-persist), ZZ_SETUP_PROFILE (also export persisted
# inputs from <ZZ_PROFILE_DIR, default /etc/profile.d>/<name>.sh).

set -e

. zz-colors

# --- arguments: the repository first (getopts stops there), then everything
# else untouched in "$@". The workspace options are declared further down,
# once the checkout says which workspaces exist.
eval "$(
    zz-args "Fetch a GitHub org/repo, propose its workspaces and inputs, then run them" "$0" "$@" <<help
- repo spec <org>/<repo>[@<ref>]: the repository to fetch and run
# args rest Options for its workspaces (zz-setup <repo> -h), or arguments for its entrypoint
help
)"

# --- parameters: validate the repository, derive ref, url, checkout and env file.
[ -n "$spec" ] || {
    zz-log e "Usage: zz-setup <org>/<repo>[@<ref>] [options] (-h for help)"
    exit 1
}

case "$spec" in
*@*)
    ref=${spec#*@}
    spec=${spec%@*}
    ;;
*) ref=${ZZ_SETUP_REF:-main} ;;
esac

# A local checkout (./x, ../x, /x) is used in place: nothing is fetched.
local=
case "$spec" in
/* | ./* | ../*)
    [ -d "$spec" ] || {
        zz-log e "No such directory: {Purple $spec}"
        exit 1
    }
    local=$(cd "$spec" && pwd)
    spec=$(basename "$local")
    ref=local
    ;;
*/*/* | /* | */ | */*[!A-Za-z0-9._-]* | *[!A-Za-z0-9._/-]*)
    zz-log e "Invalid repository {Purple $spec}, expected <org>/<repo>"
    exit 1
    ;;
*/*) ;;
*)
    zz-log e "Invalid repository {Purple $spec}, expected <org>/<repo>"
    exit 1
    ;;
esac

repo=${spec#*/}
url="${ZZ_SETUP_URL_BASE:-https://github.com}/$spec.git"

if [ -n "$ZZ_SETUP_DIR" ]; then
    parent=$ZZ_SETUP_DIR
elif [ "$(id -u)" -eq 0 ]; then
    parent=/opt
else
    parent=$HOME/.local/share
fi
dir="$parent/$repo"
[ -z "$local" ] || dir=$local

envfile="${ZZ_SETUP_ENV_FILE:-}"
if [ -z "$envfile" ]; then
    if [ "$(id -u)" -eq 0 ]; then envfile="${ZZ_ETC_DIR:-/etc}/$repo.env"; else envfile="$dir/.env"; fi
fi

# --- functions
# Run a command; when nobody can answer a prompt (stdin is not a terminal) its
# stdout is shown as operation output (zz-log o), apart from our own lines. On a
# terminal it stays raw: a prompt without a newline must show up at once.
# Its stderr (including the zz-log lines of a child script) is left alone.
output() {
    if [ -t 0 ]; then
        "$@"
        return
    fi
    _fifo=$(mktemp -u) && mkfifo "$_fifo" || {
        "$@"
        return
    }
    zz-log o <"$_fifo" &
    _reader=$!
    _rc=0
    "$@" >"$_fifo" || _rc=$?
    wait "$_reader"
    rm -f "$_fifo"
    return "$_rc"
}

# No workspaces (or forced): hand over to the repo's own entrypoint.
run_entry() {
    entry=
    for cand in "$ZZ_SETUP_ENTRY" "$repo-setup/run.sh" setup.sh run.sh; do
        if [ -n "$cand" ] && [ -f "$dir/$cand" ]; then
            entry=$cand
            break
        fi
    done
    [ -n "$entry" ] || {
        zz-log e "No workspace or entrypoint found in {U $dir}"
        zz-log - "Tried $repo-setup/run.sh, setup.sh and run.sh"
        exit 1
    }
    zz-log i "Handing over to {Purple $entry}"
    cd "$dir"
    exec sh -c '[ -x "$0" ] && exec "$0" "$@" || exec bash "$0" "$@"' "$dir/$entry" "$@"
}

# Field $2 of workspace $1's row (3 dir, 4 description, 5 default, 6 deps,
# 7 conflicts, 8 bin).
ws() { printf '%s\n' "$list" | awk -F"$us" -v n="$1" -v f="$2" '$2 == n { print $f; exit }'; }
dir_of() { ws "$1" 3; }
exists() { [ -n "$(ws "$1" 3)" ]; }
desc_of() { ws "$1" 4; }
deps_of() { ws "$1" 6 | tr ',' '\n'; }
conflicts_of() { ws "$1" 7 | tr ',' '\n'; }
var_of() { printf 'STATE_%s' "$1" | tr -c 'A-Za-z0-9_\n' '_'; }
state_get() { eval "printf '%s' \"\${$(var_of "$1"):-skip}\""; }
state_set() { eval "$(var_of "$1")=\$2"; }

# The env file is plain KEY=VALUE (zz-persist's format), read literally and
# never sourced, so a value can hold spaces/quotes without being executed.
env_get() { [ ! -f "$envfile" ] || sed -n "s/^$1=//p" "$envfile" | tail -n1; }

# The last successful run is remembered per workspace (up, or skip once brought
# down; "down" is never sticky) and preselects the menu, which only opens on a
# terminal with no option, so flags and non-interactive runs are unchanged.
state_key() { printf 'ZZ_%s' "$(var_of "$1")"; }

# Set the state of the comma-separated workspaces $2 to $1 (up|skip|down).
apply_state() {
    for n in $(printf '%s' "$2" | tr ',' ' '); do
        exists "$n" || {
            zz-log e "Unknown workspace: {Purple $n}"
            zz-log - "Available: $(printf '%s' "$names" | tr '\n' ' ')"
            exit 1
        }
        state_set "$n" "$1"
    done
}

# --- run: down in reverse order first, then up in order.
# The workspace's own zz-log lines and its stdout hang under the "running" line.
run_step() {
    d=$(dir_of "$1")
    b=$(ws "$1" 8)
    zz-log i "{B $1}: $2"
    rc=0
    output sh -c 'cd "$1" && if [ -x "$2" ]; then "./$2" $3; else bash "$2" $3; fi' sh "$d" "$b" "$2" || rc=$?
    if [ "$rc" -ne 0 ]; then
        zz-log e "{B $1}: $2 failed (exit $rc)"
        zz-log - "Script: {U $d/$b}"
        zz-log - "Re-run only this step: zz-setup $spec -o $1"
        exit 1
    fi
    zz-log s "{B $1}: $2 done"
    if [ "$2" = up ]; then _remember=up; else _remember=skip; fi
    zz-persist -q -f "$envfile" "$(state_key "$1")" "$_remember"
}

# --- code
zz-log i "Setting up {Purple $spec} at {B $ref} in {U $dir}"
if [ -z "$local" ] && [ -z "$ZZ_SETUP_REF" ] && [ "$ref" = main ] && [ "${spec#*@}" = "$spec" ]; then
    zz-log w "No ref given, using 'main'"
    zz-log - "Choose one with $spec@<ref>, or ZZ_SETUP_REF=<ref> placed after sudo"
fi

# --- fetch: zz-fetch clones or updates the checkout (nothing for a local one).
if [ -n "$local" ]; then
    zz-log n "Using the local checkout, nothing fetched"
else
    zz-log i "Fetching {U $url} at {B $ref}"
    zz-fetch -r "$ref" -d "$dir" "$url" || {
        zz-log e "Could not fetch $spec at {B $ref}"
        zz-log - "@ref and ZZ_SETUP_REF set the ref of $spec; ZZ_ORIGIN_REF (for zz-use) sets the scripts' own"
        exit 1
    }
fi

# Without workspaces (no package.json, or ZZ_SETUP_ENTRY set) the repo's own
# installer takes over.
cd "$dir"
[ -z "$ZZ_SETUP_ENTRY" ] && [ -f package.json ] || run_entry "$@"

# --- select: zz-workspaces lists the runnable workspaces, one row each:
# order US name US dir US description US default US deps US conflicts US bin.
us=$(printf '\037')
list=$(zz-workspaces)
[ -n "$list" ] || run_entry "$@"
names=$(printf '%s\n' "$list" | cut -d"$us" -f2)

# Initial state: the workspaces flagged "default" start enabled.
for n in $names; do
    if [ "$(ws "$n" 5)" = true ]; then
        state_set "$n" up
    else
        state_set "$n" skip
    fi
done

# --- workspace options: declared here, not with the first zz-args call,
# because the help and the accepted names depend on the checkout.
eval "$(
    zz-args "$spec workspaces: $(printf '%s' "$names" | tr '\n' ' ')" "zz-setup $spec" "$@" <<help
w names with_list Enable workspaces (space/comma-separated)
s names skip_list Skip workspaces
d names down_list Bring workspaces down
o names only_list Run ONLY these workspaces (overrides -w/-s/-d)
D - down_all Bring every workspace down
F - force_flag Allow -d while a dependent stays enabled
S - status_flag Show each workspace's state and inputs, run nothing
# extra extra Unknown arguments (rejected)
help
)"
[ "$#" -eq 0 ] || {
    zz-log e "Unknown argument: {Purple $1}"
    zz-log - "zz-setup $spec -h lists the options"
    exit 1
}

force_down=0 status_only=0 only=
[ -z "$force_flag" ] || force_down=1
[ -z "$status_flag" ] || status_only=1
nflags=$(printf '%s' "$with_list$skip_list$down_list$only_list$down_all$force_flag$status_flag" | wc -c)

apply_state up "$with_list"
apply_state skip "$skip_list"
[ -z "$down_all" ] || apply_state down "$names"
apply_state down "$down_list"
apply_state up "$only_list"
only=$(printf '%s' "$only_list" | tr ',' ' ')

if [ "$nflags" -eq 0 ] && [ -t 0 ]; then
    for n in $names; do
        saved=$(env_get "$(state_key "$n")")
        case "$saved" in up | skip) state_set "$n" "$saved" ;; esac
    done
    items=
    set --
    for n in $names; do
        mark=" "
        [ "$(ws "$n" 5)" = true ] && mark="*"
        set -- "$@" "$n:$(state_get "$n")=$mark $(printf '%-20s' "$n") $(desc_of "$n")"
    done
    rc=0
    out=$(zz-menu -t "$repo workspaces" -c "skip,up,down" \
        -f "  (* = default) Number cycles skip -> up -> down; <enter> proceeds, q quits." \
        "$@") || rc=$?
    if [ "$rc" -ne 0 ]; then
        zz-log n "Aborted, nothing changed"
        exit 0
    fi
    for line in $out; do
        state_set "${line%%=*}" "${line#*=}"
    done
fi

if [ -n "$only" ]; then
    for n in $names; do state_set "$n" skip; done
    for n in $only; do state_set "$n" up; done
fi

# Enable what a selected workspace depends on.
pass=0
while [ "$pass" -lt 5 ]; do
    changed=0
    for n in $names; do
        [ "$(state_get "$n")" = up ] || continue
        for dep in $(deps_of "$n"); do
            exists "$dep" || continue
            if [ "$(state_get "$dep")" = skip ]; then
                zz-log n "Also enabling {Purple $dep} (required by $n)"
                state_set "$dep" up
                changed=1
            fi
        done
    done
    [ "$changed" -eq 1 ] || break
    pass=$((pass + 1))
done

# Refuse two enabled workspaces where one declares the other incompatible,
# before anything runs (checked after the dependencies above were enabled).
if [ "$status_only" -ne 1 ]; then
    for n in $names; do
        [ "$(state_get "$n")" = up ] || continue
        for c in $(conflicts_of "$n"); do
            exists "$c" && [ "$(state_get "$c")" = up ] || continue
            zz-log e "{Purple $n} conflicts with {Purple $c}, and both are enabled"
            zz-log - "Skip one of them: -s $c, or -s $n"
            exit 1
        done
    done
fi

if [ "$force_down" -ne 1 ]; then
    for n in $names; do
        [ "$(state_get "$n")" = down ] || continue
        for o in $names; do
            [ "$o" != "$n" ] && [ "$(state_get "$o")" = up ] || continue
            for dep in $(deps_of "$o"); do
                [ "$dep" = "$n" ] || continue
                zz-log e "Cannot bring {Purple $n} down: {Purple $o} depends on it and stays enabled"
                zz-log - "Also pass -d $o, or -F"
                exit 1
            done
        done
    done
fi

up_names=
for n in $names; do [ "$(state_get "$n")" = up ] && up_names="$up_names $n"; done
[ "$status_only" -eq 1 ] || [ -n "$up_names$(for n in $names; do [ "$(state_get "$n")" = down ] && echo "$n"; done)" ] || {
    zz-log n "Nothing selected, nothing to do"
    exit 0
}

# --- inputs: zz-vars shows them (-S), or asks, resolves and refuses a
# missing required one; its export lines are evaluated here so the
# workspaces inherit the values. Exit 3 means the user aborted.
set --
for n in $([ "$status_only" -eq 1 ] && echo "$names" || echo "$up_names"); do
    set -- "$@" "$n=$(dir_of "$n")"
done
if [ "$status_only" -eq 1 ]; then
    for n in $names; do
        printf '%-6s %-22s %s\n' "$(state_get "$n")" "$n" "$(desc_of "$n")"
    done
    zz-vars -S -f "$envfile" "$@"
    exit 0
fi
if [ "$#" -gt 0 ]; then
    rc=0
    out=$(zz-vars -f "$envfile" ${ZZ_SETUP_PROFILE:+-P "$ZZ_SETUP_PROFILE"} "$@") || rc=$?
    [ "$rc" -ne 3 ] || exit 0
    [ "$rc" -eq 0 ] || exit "$rc"
    eval "$out"
fi

# --- run: all "down" steps in reverse order, then all "up" steps in order.
for n in $(printf '%s\n' "$names" | sed '1!G;h;$!d'); do
    [ "$(state_get "$n")" = down ] && run_step "$n" down
done
for n in $names; do
    [ "$(state_get "$n")" = up ] && run_step "$n" up
done
exit 0
