#!/bin/sh
# zz-setup <org>/<repo>[@<ref>] [args...] — fetch a GitHub repo and run it
# the way a workspace installer does:
#   1. shallow clone (or fast-forward) into a fixed directory;
#   2. if the root package.json lists workspaces, propose the runnable ones
#      (skip/up/down menu, dependencies auto-enabled), then list the inputs
#      they declare, offer to set them (persisted to an env file), and run
#      each selected workspace's run.sh;
#   3. otherwise (or with ZZ_SETUP_ENTRY) exec the repo's own installer with
#      the remaining arguments: <repo>-setup/run.sh, setup.sh, run.sh.
#
# Runnable workspace: has a run.sh and an "engines.zz-setup" field in its
# package.json ("order" sorts, "default" preselects, "inputs" or
# "config.input" declare inputs). Its run.sh gets "up"/"down" as argument.
#
# Options (parsed with zz-args, after the repository; names are space- or
# comma-separated): -w enable, -s skip, -d down, -o only these, -D down all,
# -F force down, -S status only, -h. No options on a terminal opens the menu.
#
# Env: ZZ_SETUP_REF (default main; "@<ref>" wins), ZZ_SETUP_DIR (parent of the
# checkout; default /opt as root, else ~/.local/share), ZZ_SETUP_URL_BASE
# (default https://github.com), ZZ_SETUP_ENTRY, ZZ_SETUP_ENV_FILE (inputs; default
# /etc/<repo>.env as root, else <checkout>/.env, read literally, written by
# zz-persist), ZZ_SETUP_PROFILE (also export persisted inputs from
# /etc/profile.d/<name>.sh).

set -e

. zz-colors

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

zz-log i "[zz-setup] repo=$spec ref=$ref dir=$dir"
if [ -z "$local" ] && [ -z "$ZZ_SETUP_REF" ] && [ "$ref" = main ] && [ "${spec#*@}" = "$spec" ]; then
    zz-log w "[zz-setup] No ref given, using 'main'. A plain 'export' before 'sudo zz-setup' is dropped by sudo: put it on the sudo line, e.g. 'sudo ZZ_SETUP_REF=... zz-setup'."
fi

command -v git >/dev/null 2>&1 || [ -n "$local" ] || zz-install git

if [ -n "$local" ]; then
    zz-log i "[zz-setup] Using the local checkout in place."
elif [ -d "$dir/.git" ]; then
    zz-log i "[zz-setup] Updating existing checkout..."
    git -C "$dir" fetch --depth 1 origin -- "$ref"
    git -C "$dir" checkout -q -B "$ref" FETCH_HEAD
    git -C "$dir" reset -q --hard FETCH_HEAD
elif [ -d "$dir" ]; then
    zz-log i "[zz-setup] $dir exists and is not a git checkout; running it in place."
else
    zz-log i "[zz-setup] Cloning $url..."
    mkdir -p "$parent"
    git clone -q --depth 1 --branch "$ref" "$url" "$dir"
fi


# --- entrypoint mode: no workspaces (or forced): hand over to the repo.
run_entry() {
    entry=
    for cand in "$ZZ_SETUP_ENTRY" "$repo-setup/run.sh" setup.sh run.sh; do
        if [ -n "$cand" ] && [ -f "$dir/$cand" ]; then
            entry=$cand
            break
        fi
    done
    [ -n "$entry" ] || {
        zz-log e "[zz-setup] No workspace or entrypoint found in $dir (tried $repo-setup/run.sh, setup.sh, run.sh)."
        exit 1
    }
    zz-log i "[zz-setup] Running {Purple $entry}..."
    cd "$dir"
    exec sh -c '[ -x "$0" ] && exec "$0" "$@" || exec bash "$0" "$@"' "$dir/$entry" "$@"
}

cd "$dir"
[ -z "$ZZ_SETUP_ENTRY" ] && [ -f package.json ] || run_entry "$@"
command -v jq >/dev/null 2>&1 || zz-install jq

# --- discover runnable workspaces: "order<TAB>name<TAB>dir", sorted.
all=$(jq -r '(.workspaces // []) | (if type == "array" then . else .packages // [] end) | .[]' package.json)
[ -n "$all" ] || run_entry "$@"

cands=
for w in $all; do
    [ -f "$w/package.json" ] && [ -f "$w/run.sh" ] || continue
    cands="$cands$w
"
done
list=
for w in $cands; do
    [ "$(jq -r '(.engines // {}) | has("zz-setup")' "$w/package.json")" = true ] || continue
    list="$list$(jq -r --arg d "$w" '[((.engines["zz-setup"] | objects).order // 1000), (.name | sub("^@[^/]*/"; "")), $d] | @tsv' "$w/package.json")
"
done
list=$(printf '%s' "$list" | sort -n -k1,1)
[ -n "$list" ] || run_entry "$@"
names=$(printf '%s\n' "$list" | cut -f2)

dir_of() { printf '%s\n' "$list" | awk -F'\t' -v n="$1" '$2 == n { print $3; exit }'; }
exists() { [ -n "$(dir_of "$1")" ]; }
desc_of() { jq -r '.description // empty' "$(dir_of "$1")/package.json"; }
deps_of() {
    jq -r '((.dependencies // {}) + (.peerDependencies // {})) | keys[] | sub("^@[^/]*/"; "")' "$(dir_of "$1")/package.json"
}
var_of() { printf 'STATE_%s' "$1" | tr -c 'A-Za-z0-9_\n' '_'; }
state_get() { eval "printf '%s' \"\${$(var_of "$1"):-skip}\""; }
state_set() { eval "$(var_of "$1")=\$2"; }

for n in $names; do
    if [ "$(jq -r '(.engines["zz-setup"] | objects).default // false' "$(dir_of "$n")/package.json")" = true ]; then
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
    items=
    set --
    for n in $names; do
        mark=" "
        [ "$(jq -r '(.engines["zz-setup"] | objects).default // false' "$(dir_of "$n")/package.json")" = true ] && mark="*"
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
                zz-log w "[zz-setup] Also enabling '$dep' (required by '$n')."
                state_set "$dep" up
                changed=1
            fi
        done
    done
    [ "$changed" -eq 1 ] || break
    pass=$((pass + 1))
done

if [ "$force_down" -ne 1 ]; then
    for n in $names; do
        [ "$(state_get "$n")" = down ] || continue
        for o in $names; do
            [ "$o" != "$n" ] && [ "$(state_get "$o")" = up ] || continue
            for dep in $(deps_of "$o"); do
                [ "$dep" = "$n" ] || continue
                zz-log e "[zz-setup] Refusing to bring '$n' down: '$o' depends on it and is still enabled. Also pass -d $o, or -F."
                exit 1
            done
        done
    done
fi

up_names=
for n in $names; do [ "$(state_get "$n")" = up ] && up_names="$up_names $n"; done
[ "$status_only" -eq 1 ] || [ -n "$up_names$(for n in $names; do [ "$(state_get "$n")" = down ] && echo "$n"; done)" ] || {
    zz-log w "[zz-setup] Nothing selected, nothing to do."
    exit 0
}

# --- inputs: "VAR<US>description<US>required<US>default<US>name<US>secret"
# (US = \037; a whitespace separator like tab would collapse empty fields),
# from "engines.zz-setup.inputs" (object keyed by var) and "config.input" (zz-call array).
inputs_of() {
    jq -r --arg n "$1" '
      (((.engines["zz-setup"] | objects).inputs // {}) | to_entries[]
         | [.key, (.value.description // ""), ((.value.required // false) | tostring), (.value.default // ""), $n, ((.value.secret // false) | tostring)] | join("\u001f")),
      ((.config.input // [])[]
         | [.var, (.question // ""), "false", (.default // ""), $n, "false"] | join("\u001f"))' "$(dir_of "$1")/package.json"
}

envfile="${ZZ_SETUP_ENV_FILE:-}"
if [ -z "$envfile" ]; then
    if [ "$(id -u)" -eq 0 ]; then envfile="/etc/$repo.env"; else envfile="$dir/.env"; fi
fi

us=$(printf '\037')
all_inputs=
for n in $([ "$status_only" -eq 1 ] && echo "$names" || echo "$up_names"); do
    all_inputs="$all_inputs$(inputs_of "$n")
"
done
all_inputs=$(printf '%s' "$all_inputs" | awk -F"$us" 'NF && !seen[$1]++')

# The env file is plain KEY=VALUE (zz-persist's format), read literally and
# never sourced, so a value can hold spaces/quotes without being executed.
env_get() { [ ! -f "$envfile" ] || sed -n "s/^$1=//p" "$envfile" | tail -n1; }

# Status view only (menu): the caller's environment, then the env file.
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

input_status() {
    if [ -n "$(eval "printf '%s' \"\${$1:-}\"")" ]; then
        echo set
    elif [ "$2" = true ]; then
        echo required
    else
        echo optional
    fi
}

if [ "$status_only" -eq 1 ]; then
    for n in $names; do
        printf '%-6s %-22s %s\n' "$(state_get "$n")" "$n" "$(desc_of "$n")"
    done
    while IFS="$us" read -r var desc req def owner secret; do
        [ -n "$var" ] || continue
        printf '  input %-24s [%s] %s\n' "$var" "$(input_status "$var" "$req")" "$owner"
    done <<STATUS
$all_inputs
STATUS
    exit 0
fi

if [ -t 0 ] && [ -n "$all_inputs" ]; then
    while :; do
        set --
        unset_count=0
        while IFS="$us" read -r var desc req def owner secret; do
            st=$(input_status "$var" "$req")
            [ "$st" = set ] || unset_count=$((unset_count + 1))
            set -- "$@" "$var=$(printf '%-24s' "$var") [$(printf '%-8s' "$st")] $owner${desc:+ - $desc}"
        done <<EOF
$all_inputs
EOF
        [ "$unset_count" -gt 0 ] || break
        rc=0
        choice=$(zz-menu -t "Inputs" \
            -f "  Number sets that input; <enter> proceeds with what's set, q quits." \
            "$@") || rc=$?
        case "$rc" in
        0) ;;
        1)
            echo "Aborted, nothing changed."
            exit 0
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

# Resolve every declared input with zz-call: the caller's environment (also
# persisted), then the env file, then the default; nothing is prompted here.
# A required input still empty aborts before anything runs.
pkgs=
for n in $up_names; do pkgs="$pkgs${pkgs:+:}$(dir_of "$n")/package.json"; done
if [ -n "$pkgs" ]; then
    eval "$(zz-call -n -e -f "$envfile" ${ZZ_SETUP_PROFILE:+-P "$ZZ_SETUP_PROFILE"} -p "$pkgs")"
fi
missing=0
while IFS="$us" read -r var desc req def owner secret; do
    [ -n "$var" ] || continue
    if [ "$(input_status "$var" "$req")" = required ]; then
        zz-log e "[zz-setup] $var is required by '$owner' but is empty: set it, or skip the workspace with -s $owner."
        missing=1
    fi
done <<EOF
$all_inputs
EOF
[ "$missing" -eq 0 ] || exit 1

# --- run: down in reverse order first, then up in order.
run_step() {
    d=$(dir_of "$1")
    zz-log i "[zz-setup] === Running $1 ($d/run.sh $2) ==="
    rc=0
    (cd "$d" && if [ -x run.sh ]; then ./run.sh $2; else bash run.sh $2; fi) || rc=$?
    if [ "$rc" -ne 0 ]; then
        zz-log e "[zz-setup] Step '$1' failed (exit $rc). Fix it and re-run just this step with: zz-setup $spec -o $1"
        exit 1
    fi
    zz-log s "[zz-setup] === Done: $1 ($2) ==="
}

for n in $(printf '%s\n' "$names" | sed '1!G;h;$!d'); do
    [ "$(state_get "$n")" = down ] && run_step "$n" down
done
for n in $names; do
    [ "$(state_get "$n")" = up ] && run_step "$n" up
done
exit 0
