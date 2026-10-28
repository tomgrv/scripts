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
# The "summary" action is opt-in: a workspace with "config.summary": true gets it
# after every run (its blocks printed as is, in order), and alone from
# `zz-setup <repo> -m`, which runs nothing else.
#
# "config.requires" ({"root": true, "os": "ubuntu"}) is checked for every selected
# workspace before the first one runs (zz-require).
#
# Runnable workspace: has a "bin" and an "engines.zz-setup" field in its
# package.json (the run context, any value such as "*"). Its optional "config"
# holds the settings: "order" sorts, "default" preselects, "conflicts" lists
# workspaces that cannot be enabled together with it, "inputs" (or
# "config.input") declare inputs. Its (first) bin gets "up"/"down" as argument.
#
# The state of each workspace you run is remembered in the env file
# (ZZ_STATE_<name>=up|skip|down) and preselects the next menu; the menu's
# choices are remembered as soon as they are confirmed.
#
# Options (parsed with zz-args, after the repository; names are space- or
# comma-separated): -w enable, -s skip, -d down, -o only these, -D down all,
# -F force down, -S status only, -m summaries, -h. No options on a terminal opens the menu.
#
# Env: ZZ_SETUP_REF (default main; "@<ref>" wins; exported to the workspaces), ZZ_SETUP_DIR (parent of the
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
# The workspaces run for this ref: the one given as @<ref> too, so a step that
# fetches a shared library of the same repository (zz-use <org>/<repo>/lib@${ZZ_SETUP_REF})
# gets the same version as the checkout, not main.
[ -n "$local" ] || export ZZ_SETUP_REF="$ref"
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
# run_output <command> [args...]: run a command; when nobody can answer a
# prompt (stdin is not a terminal) its stdout is shown as operation output
# (zz-log o), apart from our own lines. On a terminal it stays raw: a prompt
# without a newline must show up at once. Its stderr (including the zz-log lines
# of a child script) is left alone.
run_output() {
    local fifo reader
    local rc=0

    if [ -t 0 ]; then
        "$@"
        return
    fi
    fifo=$(mktemp -u) && mkfifo "$fifo" || {
        "$@"
        return
    }
    zz-log o <"$fifo" &
    reader=$!
    "$@" >"$fifo" || rc=$?
    wait "$reader"
    rm -f "$fifo"
    return "$rc"
}

# run_entry [args...]: no workspaces (or forced): hand over to the repo's own
# entrypoint, with the remaining arguments.
run_entry() {
    local entry cand

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

# get_field <name> <column>: column of workspace <name>'s row (3 dir,
# 4 description, 5 default, 6 deps, 7 conflicts, 8 bin).
get_field() { printf '%s\n' "$list" | awk -F"$us" -v n="$1" -v f="$2" '$2 == n { print $f; exit }'; }

# get_dir / get_description / get_deps / get_conflicts <name>: a workspace's
# directory, description, and its dependencies / conflicts one per line.
# has_workspace <name>: true when <name> is a known workspace.
get_dir() { get_field "$1" 3; }
has_workspace() { [ -n "$(get_field "$1" 3)" ]; }
get_description() { get_field "$1" 4; }
get_deps() { get_field "$1" 6 | tr ',' '\n'; }
get_conflicts() { get_field "$1" 7 | tr ',' '\n'; }

# get_state_var <name>: the shell variable holding workspace <name>'s state.
# get_state <name>: its state (up|skip|down), skip when unset.
# set_state <name> <state>: set it.
get_state_var() {
    local rest="$1" out= c

    # character by character in the shell: it is asked for every workspace, a tr each time adds up
    while [ -n "$rest" ]; do
        c=${rest%"${rest#?}"}
        rest=${rest#?}
        case "$c" in
        [A-Za-z0-9_]) out=$out$c ;;
        *) out=${out}_ ;;
        esac
    done
    printf 'STATE_%s' "$out"
}
get_state() { eval "printf '%s' \"\${$(get_state_var "$1"):-skip}\""; }
set_state() { eval "$(get_state_var "$1")=\$2"; }

# get_env_value <key>: the env file is plain KEY=VALUE (zz-persist's format),
# read literally and never sourced, so a value can hold spaces/quotes without
# being executed.
get_env_value() { [ ! -f "$envfile" ] || sed -n "s/^$1=//p" "$envfile" | tail -n1; }

# get_state_key <name>: the env file key under which the last successful run
# is remembered per workspace (up, skip or down, as is) and preselects the menu
# and starts runs given flags from it.
get_state_key() { printf 'ZZ_%s' "$(get_state_var "$1")"; }

# apply_state <state> <names>: set the state of the comma-separated workspaces
# to <state>.
apply_state() {
    local state="$1"      # up, skip or down (mandatory)
    local list_names="$2" # comma-separated workspace names (mandatory, may be empty)
    local n

    for n in $(printf '%s' "$list_names" | tr ',' ' '); do
        has_workspace "$n" || {
            zz-log e "Unknown workspace: {Purple $n}"
            zz-log - "Available: $(printf '%s' "$names" | tr '\n' ' ')"
            exit 1
        }
        set_state "$n" "$state"
    done
}

# --- run: down in reverse order first, then up in order.
# The workspace's own zz-log lines and its stdout hang under the "running" line.
# exec_bin <name> <action>: run a workspace's bin from its own directory with
# <action> as its argument.
exec_bin() {
    local name="$1"   # workspace name (mandatory)
    local action="$2" # up, down, summary... (mandatory)

    sh -c 'cd "$1" && if [ -x "$2" ]; then "./$2" $3; else bash "$2" $3; fi' sh "$(get_dir "$name")" "$(get_field "$name" 8)" "$action"
}

# run_step <name> <action>: run a workspace's bin with <action> (up|down, or any
# action asked with -a); the states themselves are remembered before the run.
# print_results: one line per planned step (action:name in $plan) - ok, failed or not run -
# when the run had several, so a failure midway shows what did and did not happen.
print_results() {
    local item action name line st secs

    [ "${step_total:-0}" -gt 1 ] || return 0
    printf '\n' >&2
    zz-log i "Results:"
    for item in $plan; do
        action="${item%%:*}" name="${item#*:}"
        line="$(printf '%s' "$results" | awk -v a="$action" -v n="$name" '$2 == a && $3 == n { print; exit }')"
        st="${line%% *}" secs="${line##* }"
        case "$st" in
        ok) zz-log s "  {B $name} $action: ok (${secs}s)" ;;
        failed) zz-log e "  {B $name} $action: failed (${secs}s)" ;;
        *) zz-log w "  {B $name} $action: not run" ;;
        esac
    done
}

run_step() {
    local name="$1"   # workspace name (mandatory)
    local action="$2" # up, down or a custom action (mandatory)
    local ws_dir ws_bin start secs tag
    local rc=0

    ws_dir=$(get_dir "$name")
    ws_bin=$(get_field "$name" 8)
    # A tagged, spaced entry and exit: [step] action (n/total), then how long it took.
    step_no=$((step_no + 1))
    tag="{B [$name]} $action"
    [ "${step_total:-0}" -le 1 ] || tag="$tag ($step_no/$step_total)"
    start=$(date +%s)
    printf '\n' >&2
    zz-log i "$tag"
    run_output exec_bin "$name" "$action" || rc=$?
    secs=$(($(date +%s) - start))
    if [ "$rc" -ne 0 ]; then
        zz-log e "{B [$name]} $action failed (exit $rc) after ${secs}s"
        zz-log - "Script: {U $ws_dir/$ws_bin}"
        zz-log - "Re-run only this step: zz-setup $spec -o $name"
        results="${results}failed $action $name $secs
"
        print_results
        printf '\n' >&2
        exit 1
    fi
    results="${results}ok $action $name $secs
"
    zz-log s "{B [$name]} $action done in ${secs}s"
}

# print_summaries: ask every workspace declaring "config.summary" for its
# "summary" action and print each non-empty block as is.
print_summaries() {
    local n out header=""

    # The summaries read their steps' inputs (ports, credential files): resolved
    # as for a run - environment, env file, default - but never asked.
    set --
    for n in $names; do
        [ "$(get_field "$n" 9)" = true ] || continue
        set -- "$@" "$n=$(get_dir "$n")"
    done
    [ "$#" -eq 0 ] || eval "$(zz-vars -n -f "$envfile" "$@")"
    for n in $names; do
        [ "$(get_field "$n" 9)" = true ] || continue
        out=$(exec_bin "$n" summary) || true
        [ -n "$out" ] || continue
        # one header line, once, before the first block: where the summary starts
        [ -n "$header" ] || zz-log s "{B $repo} summary"
        header=1
        printf '%s\n\n' "$out"
    done
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

# --- select: ws-list picks the runnable workspaces (bin + engines.zz-setup, by
# config.order); one row each:
# order US name US dir US description US default US deps US conflicts US bin
# US summary US requires. name has its @scope/ removed; deps and
# conflicts are comma-separated names; requires is comma-separated
# (config.requires: root, os=<id>; see zz-require); summary is
# true|false (config.summary).
us=$(printf '\037')
# A slow read says so (zz-progress), on the line the menu will take over.
zz-progress "Reading the workspaces..."
list=$(ws-list -b -e zz-setup -o . | while IFS= read -r w; do
    jq -r --arg d "${w#./}" '
      [ (.config.order // 1000 | tostring),
        (.name | sub("^@[^/]*/"; "")),
        $d,
        ((.description // "") | gsub("[\n\r]"; " ")),
        ((.config.default // false) | tostring),
        (((.dependencies // {}) + (.peerDependencies // {})) | keys | map(sub("^@[^/]*/"; "")) | join(",")),
        ((.config.conflicts // []) | map(sub("^@[^/]*/"; "")) | join(",")),
        (.bin | if type == "string" then . else (to_entries[0].value // "") end),
        ((.config.summary // false) | tostring),
        ((.config.requires // {}) | to_entries | map(if .value == true then .key else "\(.key)=\(.value)" end) | join(",")) ]
      | join("\u001f")' "$w/package.json"
done)
zz-progress
[ -n "$list" ] || run_entry "$@"
names=$(printf '%s\n' "$list" | cut -d"$us" -f2)

# --- bins: the run.sh of every workspace with a bin - a step or not - is put on PATH
# under its folder name, so a step can call a sibling (a shared helper that is not a
# step) by name. A local path origin: no download, always re-linked.
install_bins() {
    local w out

    for w in $(ws-list -b .); do
        [ -f "$w/run.sh" ] || continue
        out=$(zz-use "$PWD/${w#./}" 2>&1) || {
            zz-log w "Could not put ${w#./} on PATH"
            printf '%s\n' "$out" >&2
        }
    done
}
# A bin is a copy, so it finds the checkout through ZZ_SETUP_ROOT, not its own location.
export ZZ_SETUP_ROOT="$PWD"
install_bins

# Initial state: the workspaces flagged "default" start enabled.
for n in $names; do
    if [ "$(get_field "$n" 5)" = true ]; then
        set_state "$n" up
    else
        set_state "$n" skip
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
a action action_name Run this action (any argument the bin understands) on the -o workspaces instead of up
y - assume_yes Do not ask to confirm the workspaces set to down
m - summary_flag Print the summary of each workspace that declares config.summary, run nothing
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
nflags=$(printf '%s' "$with_list$skip_list$down_list$only_list$down_all$force_flag$status_flag$summary_flag$action_name" | wc -c)

# --- summary: -m prints the summaries (inputs resolved, never asked) and stops.
if [ -n "$summary_flag" ]; then
    print_summaries
    exit 0
fi

# Remembered states (the last runs' up/skip) come first, so a flag only changes what
# it names: -s b does not forget that a was skipped last time.
load_saved_states() {
    local line key saved

    [ -f "$envfile" ] || return 0
    # The env file is read once (the last line of a key wins); only plain shell names are kept.
    while IFS= read -r line; do
        key=${line%%=*}
        case "$line" in
        ZZ_STATE_*=*)
            case "$key" in *[!A-Za-z0-9_]*) continue ;; esac
            eval "saved_$key=\${line#*=}"
            ;;
        esac
    done <"$envfile"
    for n in $names; do
        eval "saved=\${saved_$(get_state_key "$n"):-}"
        [ -z "$saved" ] || set_state "$n" "$saved"
    done
}
[ "$nflags" -eq 0 ] || load_saved_states

apply_state up "$with_list"
apply_state skip "$skip_list"
[ -z "$down_all" ] || apply_state down "$names"
apply_state down "$down_list"
apply_state up "$only_list"
only=$(printf '%s' "$only_list" | tr ',' ' ')
[ -z "$action_name" ] || [ -n "$only_list" ] || {
    zz-log e "-a <action> needs -o <workspaces>"
    exit 1
}

if [ "$nflags" -eq 0 ] && zz-interactive; then
    load_saved_states
    tab=$(printf '\t')
    while :; do
        set --
        # list rows: 1 order, 2 name, 3 dir, 4 description, 5 default (true = up)
        while IFS="$us" read -r _ n _ desc dflt _; do
            [ -n "$n" ] || continue
            mark=" "
            [ "$dflt" = true ] && mark="*"
            # grouped by the name's prefix (svc-k3s -> svc); a name with no dash stays ungrouped
            group=
            case "$n" in *-*) group=${n%%-*} ;; esac
            set -- "$@" "$n:$(get_state "$n")=$group$tab$mark$tab$n$tab$desc"
        done <<ROWS
$list
ROWS
        rc=0
        out=$(zz-menu -t "$repo workspaces" -g 1 -c "skip,up,down" -z "~reset=Reset to defaults (* up, others skip)" \
            -f " (* = default) Number cycles skip -> up -> down; <enter> validates; q quits." \
            "$@") || rc=$?
        # 0: every workspace back to its default (up when marked *, else skip), then ask again
        [ "$rc" -eq 0 ] && [ "$out" = "~reset" ] || break
        for n in $names; do
            if [ "$(get_field "$n" 5)" = true ]; then set_state "$n" up; else set_state "$n" skip; fi
        done
    done
    if [ "$rc" -ne 0 ]; then
        zz-log n "Aborted, nothing changed"
        exit 0
    fi
    for line in $out; do
        set_state "${line%%=*}" "${line#*=}"
        # A skipped workspace never runs, so remember every choice now, as is.
        zz-persist -q -f "$envfile" "$(get_state_key "${line%%=*}")" "${line#*=}"
    done
    # down removes what the workspace installed: confirm each, unless -y
    if [ -z "$assume_yes" ]; then
        for n in $names; do
            [ "$(get_state "$n")" = down ] || continue
            [ "$(zz-prompt -c yN "Bring $n down (remove what it installed)?")" = y ] || set_state "$n" skip
        done
    fi
fi

if [ -n "$only" ]; then
    for n in $names; do set_state "$n" skip; done
    for n in $only; do set_state "$n" up; done
fi

# Enable what a selected workspace depends on.
pass=0
while [ "$pass" -lt 5 ]; do
    changed=0
    for n in $names; do
        [ "$(get_state "$n")" = up ] || continue
        for dep in $(get_deps "$n"); do
            has_workspace "$dep" || continue
            if [ "$(get_state "$dep")" = skip ]; then
                zz-log n "Also enabling {Purple $dep} (required by $n)"
                set_state "$dep" up
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
        [ "$(get_state "$n")" = up ] || continue
        for c in $(get_conflicts "$n"); do
            has_workspace "$c" && [ "$(get_state "$c")" = up ] || continue
            zz-log e "{Purple $n} conflicts with {Purple $c}, and both are enabled"
            zz-log - "Skip one of them: -s $c, or -s $n"
            exit 1
        done
    done
fi

# What the selected workspaces need from the host (config.requires: root,
# os=<id>), checked before any of them starts.
if [ "$status_only" -ne 1 ]; then
    for n in $names; do
        [ "$(get_state "$n")" = skip ] && continue
        req=$(get_field "$n" 10 | tr ',' ' ')
        # shellcheck disable=SC2086
        [ -z "$req" ] || zz-require -n "$n" $req || exit 1
    done
fi

if [ "$force_down" -ne 1 ]; then
    for n in $names; do
        [ "$(get_state "$n")" = down ] || continue
        for o in $names; do
            [ "$o" != "$n" ] && [ "$(get_state "$o")" = up ] || continue
            for dep in $(get_deps "$o"); do
                [ "$dep" = "$n" ] || continue
                zz-log e "Cannot bring {Purple $n} down: {Purple $o} depends on it and stays enabled"
                zz-log - "Also pass -d $o, or -F"
                exit 1
            done
        done
    done
fi

up_names=
for n in $names; do [ "$(get_state "$n")" = up ] && up_names="$up_names $n"; done
# the workspaces this run brings up, for the steps that only concern those (e.g. which apps to list)
export ZZ_SETUP_UP=" $(echo $up_names) "
[ "$status_only" -eq 1 ] || [ -n "$up_names$(for n in $names; do [ "$(get_state "$n")" = down ] && echo "$n"; done)" ] || {
    zz-log n "Nothing selected, nothing to do"
    exit 0
}

# Remember every workspace's state, as is, whatever it is.
if [ "$status_only" -ne 1 ]; then
    for n in $names; do zz-persist -q -f "$envfile" "$(get_state_key "$n")" "$(get_state "$n")"; done
fi

# --- inputs: zz-vars shows them (-S), or asks, resolves and refuses a
# missing required one; its export lines are evaluated here so the
# workspaces inherit the values. Exit 3 means the user aborted.
set --
for n in $([ "$status_only" -eq 1 ] && echo "$names" || echo "$up_names"); do
    set -- "$@" "$n=$(get_dir "$n")"
done
if [ "$status_only" -eq 1 ]; then
    for n in $names; do
        printf '%-6s %-22s %s\n' "$(get_state "$n")" "$n" "$(get_description "$n")"
    done
    zz-vars -S -f "$envfile" "$@"
    exit 0
fi
if [ "$#" -gt 0 ]; then
    rc=0
    out=$(zz-vars -e -f "$envfile" ${ZZ_SETUP_PROFILE:+-P "$ZZ_SETUP_PROFILE"} "$@") || rc=$?
    [ "$rc" -ne 3 ] || exit 0
    [ "$rc" -eq 0 ] || exit "$rc"
    eval "$out"
fi

# --- -a: one custom action on the selected workspaces, nothing else.
step_no=0 step_total=0 results= plan=
if [ -n "$action_name" ]; then
    step_total=$(printf '%s\n' $up_names | grep -c .)
    for n in $up_names; do plan="$plan $action_name:$n"; done
    for n in $up_names; do
        run_step "$n" "$action_name"
    done
    print_results
    exit 0
fi

# --- run: all "down" steps in reverse order, then all "up" steps in order.
for n in $names; do
    case "$(get_state "$n")" in up | down) step_total=$((step_total + 1)) ;; esac
done
for n in $(printf '%s\n' "$names" | sed '1!G;h;$!d'); do
    [ "$(get_state "$n")" = down ] && plan="$plan down:$n"
done
for n in $names; do
    [ "$(get_state "$n")" = up ] && plan="$plan up:$n"
done
for n in $(printf '%s\n' "$names" | sed '1!G;h;$!d'); do
    [ "$(get_state "$n")" = down ] || continue
    run_step "$n" down
    # removed for good: remembered as skip, so it is not brought down again (nor asked about) next time
    set_state "$n" skip
    zz-persist -q -f "$envfile" "$(get_state_key "$n")" skip
done
for n in $names; do
    [ "$(get_state "$n")" = up ] && run_step "$n" up
done
print_results

# --- summary: what the workspaces declaring config.summary report, once all ran.
print_summaries
exit 0
