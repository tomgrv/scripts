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

# zz-log tags every line with the current step (inherited by the scripts run
# below) and indents what nested steps print.
ZZ_LOG_STEP=zz-setup
export ZZ_LOG_STEP
step() {
    ZZ_LOG_STEP="zz-setup:$1"
    export ZZ_LOG_STEP
}

# Repository first (getopts stops there), then everything else untouched in "$@".
eval "$(zz-args "Fetch a GitHub org/repo, propose its workspaces and inputs, then run them" "$0" "$@" <<help
- repo spec <org>/<repo>[@<ref>]: the repository to fetch and run
# args rest Options for its workspaces (zz-setup <repo> -h), or arguments for its entrypoint
help
)"

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

zz-log i "repo=$spec ref=$ref dir=$dir"
if [ -z "$local" ] && [ -z "$ZZ_SETUP_REF" ] && [ "$ref" = main ] && [ "${spec#*@}" = "$spec" ]; then
    zz-log w "No ref given, using 'main'. A plain 'export' before 'sudo zz-setup' is dropped by sudo: put it on the sudo line, e.g. 'sudo ZZ_SETUP_REF=... zz-setup'."
fi

# --- fetch: zz-fetch clones or updates the checkout (nothing for a local one).
step fetch
if [ -n "$local" ]; then
    zz-log i "Using the local checkout in place."
else
    zz-fetch -r "$ref" -d "$dir" "$url"
fi

# --- entrypoint mode: no workspaces (or forced): hand over to the repo.
run_entry() {
    step entry
    entry=
    for cand in "$ZZ_SETUP_ENTRY" "$repo-setup/run.sh" setup.sh run.sh; do
        if [ -n "$cand" ] && [ -f "$dir/$cand" ]; then
            entry=$cand
            break
        fi
    done
    [ -n "$entry" ] || {
        zz-log e "No workspace or entrypoint found in $dir (tried $repo-setup/run.sh, setup.sh, run.sh)."
        exit 1
    }
    zz-log i "Running {Purple $entry}..."
    cd "$dir"
    exec sh -c '[ -x "$0" ] && exec "$0" "$@" || exec bash "$0" "$@"' "$dir/$entry" "$@"
}

cd "$dir"
[ -z "$ZZ_SETUP_ENTRY" ] && [ -f package.json ] || run_entry "$@"
# --- select: zz-workspaces lists the runnable workspaces, one row each:
# order US name US dir US description US default US deps US conflicts US bin.
us=$(printf '\037')
list=$(zz-workspaces)
[ -n "$list" ] || run_entry "$@"
names=$(printf '%s\n' "$list" | cut -d"$us" -f2)

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

envfile="${ZZ_SETUP_ENV_FILE:-}"
if [ -z "$envfile" ]; then
    if [ "$(id -u)" -eq 0 ]; then envfile="${ZZ_ETC_DIR:-/etc}/$repo.env"; else envfile="$dir/.env"; fi
fi

# The env file is plain KEY=VALUE (zz-persist's format), read literally and
# never sourced, so a value can hold spaces/quotes without being executed.
env_get() { [ ! -f "$envfile" ] || sed -n "s/^$1=//p" "$envfile" | tail -n1; }

# The last successful run is remembered per workspace (up, or skip once brought
# down; "down" is never sticky) and preselects the menu, which only opens on a
# terminal with no option, so flags and non-interactive runs are unchanged.
state_key() { printf 'ZZ_%s' "$(var_of "$1")"; }

for n in $names; do
    if [ "$(ws "$n" 5)" = true ]; then
        state_set "$n" up
    else
        state_set "$n" skip
    fi
done

apply_state() {
    for n in $(printf '%s' "$2" | tr ',' ' '); do
        exists "$n" || {
            zz-log e "Unknown workspace: $n (available: $(printf '%s' "$names" | tr '\n' ' '))"
            exit 1
        }
        state_set "$n" "$1"
    done
}

eval "$(zz-args "$spec workspaces: $(printf '%s' "$names" | tr '\n' ' ')" "zz-setup $spec" "$@" <<help
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
    zz-log e "Unknown argument: $1 (zz-setup $spec -h)"
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
        echo "Aborted, nothing changed."
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
                zz-log w "Also enabling '$dep' (required by '$n')."
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
            zz-log e "'$n' conflicts with '$c' and both are enabled. Skip one of them: -s $c, or -s $n."
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
                zz-log e "Refusing to bring '$n' down: '$o' depends on it and is still enabled. Also pass -d $o, or -F."
                exit 1
            done
        done
    done
fi

up_names=
for n in $names; do [ "$(state_get "$n")" = up ] && up_names="$up_names $n"; done
[ "$status_only" -eq 1 ] || [ -n "$up_names$(for n in $names; do [ "$(state_get "$n")" = down ] && echo "$n"; done)" ] || {
    zz-log w "Nothing selected, nothing to do."
    exit 0
}

# --- inputs: zz-inputs shows them (-S), or asks, resolves and refuses a
# missing required one; its export lines are evaluated here so the
# workspaces inherit the values. Exit 3 means the user aborted.
step inputs
set --
for n in $([ "$status_only" -eq 1 ] && echo "$names" || echo "$up_names"); do
    set -- "$@" "$n=$(dir_of "$n")"
done
if [ "$status_only" -eq 1 ]; then
    for n in $names; do
        printf '%-6s %-22s %s\n' "$(state_get "$n")" "$n" "$(desc_of "$n")"
    done
    zz-inputs -S -f "$envfile" "$@"
    exit 0
fi
if [ "$#" -gt 0 ]; then
    rc=0
    out=$(zz-inputs -f "$envfile" ${ZZ_SETUP_PROFILE:+-P "$ZZ_SETUP_PROFILE"} "$@") || rc=$?
    [ "$rc" -ne 3 ] || exit 0
    [ "$rc" -eq 0 ] || exit "$rc"
    eval "$out"
fi

# --- run: down in reverse order first, then up in order.
# Each workspace runs tagged with its own name and one level deeper, so its
# zz-log lines nest under the "=== Running" line.
run_step() {
    d=$(dir_of "$1")
    b=$(ws "$1" 8)
    zz-log i "=== Running $1 ($d/$b $2) ==="
    rc=0
    (
        ZZ_LOG_STEP=$1
        ZZ_LOG_INDENT=$((${ZZ_LOG_INDENT:-0} + 2))
        export ZZ_LOG_STEP ZZ_LOG_INDENT
        cd "$d" && if [ -x "$b" ]; then "./$b" $2; else bash "$b" $2; fi
    ) || rc=$?
    if [ "$rc" -ne 0 ]; then
        zz-log e "Step '$1' failed (exit $rc). Fix it and re-run just this step with: zz-setup $spec -o $1"
        exit 1
    fi
    zz-log s "=== Done: $1 ($2) ==="
    if [ "$2" = up ]; then _remember=up; else _remember=skip; fi
    zz-persist -f "$envfile" "$(state_key "$1")" "$_remember"
}

step run
for n in $(printf '%s\n' "$names" | sed '1!G;h;$!d'); do
    [ "$(state_get "$n")" = down ] && run_step "$n" down
done
for n in $names; do
    [ "$(state_get "$n")" = up ] && run_step "$n" up
done
exit 0
