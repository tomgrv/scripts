#!/bin/sh
# zz-run <org>/<repo>[@<ref>] [args...] — fetch a GitHub repo and run it
# the way vps-setup does for perspikapps/vps:
#   1. shallow clone (or fast-forward) into a fixed directory;
#   2. if the root package.json lists workspaces, propose the runnable ones
#      (skip/up/down menu, dependencies auto-enabled), then list the inputs
#      they declare, offer to set them (persisted to an env file), and run
#      each selected workspace's run.sh;
#   3. otherwise (or with ZZ_RUN_ENTRY) exec the repo's own installer with
#      the remaining arguments: <repo>-setup/run.sh, setup.sh, run.sh.
#
# Runnable workspace: has a run.sh. If any workspace has a "vps" key in its
# package.json, only those are proposed ("vps.order" sorts, "vps.default"
# preselects, "vps.inputs" or "config.input" declare inputs); a "vps"
# workspace's run.sh gets "up"/"down" as argument.
#
# Flags (workspace mode): --skip-<n> --with-<n> --only-<n> --down-<n>
# --force-down -h. No flags on a terminal opens the menu.
#
# Env: ZZ_RUN_REF (default main; "@<ref>" wins), ZZ_RUN_DIR (parent of the
# checkout; default /opt as root, else ~/.local/share), ZZ_RUN_URL_BASE
# (default https://github.com), ZZ_RUN_ENTRY, ZZ_RUN_ENV_FILE (inputs; default
# /etc/<repo>.env as root, else <checkout>/.env).

set -e

. zz-colors

[ -n "$1" ] || {
    zz-log e "Usage: zz-run <org>/<repo>[@<ref>] [args...]"
    exit 1
}

spec=$1
shift

case "$spec" in
*@*)
    ref=${spec#*@}
    spec=${spec%@*}
    ;;
*) ref=${ZZ_RUN_REF:-main} ;;
esac

case "$spec" in
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
url="${ZZ_RUN_URL_BASE:-https://github.com}/$spec.git"

if [ -n "$ZZ_RUN_DIR" ]; then
    parent=$ZZ_RUN_DIR
elif [ "$(id -u)" -eq 0 ]; then
    parent=/opt
else
    parent=$HOME/.local/share
fi
dir="$parent/$repo"

zz-log i "[zz-run] repo=$spec ref=$ref dir=$dir"
if [ -z "$ZZ_RUN_REF" ] && [ "$ref" = main ] && [ "${spec#*@}" = "$spec" ]; then
    zz-log w "[zz-run] No ref given, using 'main'. A plain 'export' before 'sudo zz-run' is dropped by sudo: put it on the sudo line, e.g. 'sudo ZZ_RUN_REF=... zz-run'."
fi

command -v git >/dev/null 2>&1 || zz-install git

if [ -d "$dir/.git" ]; then
    zz-log i "[zz-run] Updating existing checkout..."
    git -C "$dir" fetch --depth 1 origin -- "$ref"
    git -C "$dir" checkout -q -B "$ref" FETCH_HEAD
    git -C "$dir" reset -q --hard FETCH_HEAD
elif [ -d "$dir" ]; then
    zz-log i "[zz-run] $dir exists and is not a git checkout; running it in place."
else
    zz-log i "[zz-run] Cloning $url..."
    mkdir -p "$parent"
    git clone -q --depth 1 --branch "$ref" "$url" "$dir"
fi


# --- entrypoint mode: no workspaces (or forced): hand over to the repo.
run_entry() {
    entry=
    for cand in "$ZZ_RUN_ENTRY" "$repo-setup/run.sh" setup.sh run.sh; do
        if [ -n "$cand" ] && [ -f "$dir/$cand" ]; then
            entry=$cand
            break
        fi
    done
    [ -n "$entry" ] || {
        zz-log e "[zz-run] No workspace or entrypoint found in $dir (tried $repo-setup/run.sh, setup.sh, run.sh)."
        exit 1
    }
    zz-log i "[zz-run] Running {Purple $entry}..."
    cd "$dir"
    exec sh -c '[ -x "$0" ] && exec "$0" "$@" || exec bash "$0" "$@"' "$dir/$entry" "$@"
}

cd "$dir"
[ -z "$ZZ_RUN_ENTRY" ] && [ -f package.json ] || run_entry "$@"
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
has_vps=0
for w in $cands; do
    [ "$(jq -r 'has("vps")' "$w/package.json")" = true ] && has_vps=1
done
list=
for w in $cands; do
    [ "$has_vps" -eq 0 ] || [ "$(jq -r 'has("vps")' "$w/package.json")" = true ] || continue
    list="$list$(jq -r --arg d "$w" '[(.vps.order // 1000), (.name | sub("^@[^/]*/"; "")), $d] | @tsv' "$w/package.json")
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
    if [ "$(jq -r '.vps.default // false' "$(dir_of "$n")/package.json")" = true ]; then
        state_set "$n" up
    else
        state_set "$n" skip
    fi
done

usage() {
    echo "Usage: zz-run <org>/<repo>[@<ref>] [options]"
    echo "       (no options, on a terminal: interactive menu)"
    echo
    for n in $names; do
        printf '  --with-%-20s %s\n' "$n" "$(desc_of "$n")"
    done
    echo
    echo "Also: --skip-<n>, --only-<n> (repeatable, overrides skip/with), --down-<n>,"
    echo "      --force-down (allow --down-<n> while a dependent is up), -h"
}

force_down=0
only=
nflags=0
for arg in "$@"; do
    nflags=$((nflags + 1))
    case "$arg" in
    --skip-* | --with-* | --only-* | --down-*)
        kind=${arg#--}
        kind=${kind%%-*}
        n=${arg#--"$kind"-}
        exists "$n" || {
            zz-log e "Unknown option: $arg"
            usage >&2
            exit 1
        }
        case "$kind" in
        skip) state_set "$n" skip ;;
        with) state_set "$n" up ;;
        down) state_set "$n" down ;;
        only) only="$only $n" ;;
        esac
        ;;
    --force-down) force_down=1 ;;
    -h | --help)
        usage
        exit 0
        ;;
    *)
        zz-log e "Unknown option: $arg"
        usage >&2
        exit 1
        ;;
    esac
done

if [ "$nflags" -eq 0 ] && [ -t 0 ]; then
    items=
    set --
    for n in $names; do
        mark=" "
        [ "$(jq -r '.vps.default // false' "$(dir_of "$n")/package.json")" = true ] && mark="*"
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
                zz-log w "[zz-run] Also enabling '$dep' (required by '$n')."
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
                zz-log e "[zz-run] Refusing to bring '$n' down: '$o' depends on it and is still enabled. Also pass --down-$o, or --force-down."
                exit 1
            done
        done
    done
fi

up_names=
for n in $names; do [ "$(state_get "$n")" = up ] && up_names="$up_names $n"; done
[ -n "$up_names$(for n in $names; do [ "$(state_get "$n")" = down ] && echo "$n"; done)" ] || {
    zz-log w "[zz-run] Nothing selected, nothing to do."
    exit 0
}

# --- inputs: "VAR<TAB>description<TAB>required<TAB>default<TAB>name",
# from "vps.inputs" (object keyed by var) and "config.input" (zz-call array).
inputs_of() {
    jq -r --arg n "$1" '
      ((.vps.inputs // {}) | to_entries[]
         | [.key, (.value.description // ""), ((.value.required // false) | tostring), (.value.default // ""), $n] | @tsv),
      ((.config.input // [])[]
         | [.var, (.question // ""), "false", (.default // ""), $n] | @tsv)' "$(dir_of "$1")/package.json"
}

envfile="${ZZ_RUN_ENV_FILE:-}"
if [ -z "$envfile" ]; then
    if [ "$(id -u)" -eq 0 ]; then envfile="/etc/$repo.env"; else envfile="$dir/.env"; fi
fi
if [ -f "$envfile" ]; then
    set -a
    # shellcheck disable=SC1090
    . "$envfile"
    set +a
fi

tab=$(printf '\t')
all_inputs=
for n in $up_names; do
    all_inputs="$all_inputs$(inputs_of "$n")
"
done
all_inputs=$(printf '%s' "$all_inputs" | awk -F'\t' 'NF && !seen[$1]++')

input_status() {
    if [ -n "$(eval "printf '%s' \"\${$1:-}\"")" ]; then
        echo set
    elif [ "$2" = true ]; then
        echo required
    else
        echo optional
    fi
}

if [ -t 0 ] && [ -n "$all_inputs" ]; then
    while :; do
        set --
        unset_count=0
        while IFS="$tab" read -r var desc req def owner; do
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
        row=$(printf '%s\n' "$all_inputs" | awk -F'\t' -v v="$choice" '$1 == v { print; exit }')
        desc=$(printf '%s' "$row" | cut -f2)
        def=$(printf '%s' "$row" | cut -f4)
        current=$(eval "printf '%s' \"\${$choice:-}\"")
        if [ -n "$current" ]; then
            answer=$(zz-prompt "${choice}${desc:+ ($desc)} - enter to keep the current value:")
        else
            answer=$(zz-prompt "${choice}${desc:+ ($desc)}:" "$def")
        fi
        if [ -n "$answer" ]; then
            eval "$choice=\"\$answer\""
            eval "export $choice"
            quoted=$(printf '%s' "$answer" | sed "s/'/'\\\\''/g")
            zz-persist -f "$envfile" "$choice" "'$quoted'"
        fi
    done
fi

# Defaults for the rest; required-but-empty is a warning, like vps-setup.
while IFS="$tab" read -r var desc req def owner; do
    [ -n "$var" ] || continue
    if [ -z "$(eval "printf '%s' \"\${$var:-}\"")" ] && [ -n "$def" ]; then
        eval "$var=\$def"
    fi
    eval "export $var"
    [ "$(input_status "$var" "$req")" = required ] &&
        zz-log w "[zz-run] $var is required by '$owner' but is empty; that step will likely fail without it."
done <<EOF
$all_inputs
EOF

# --- run: down in reverse order first, then up in order.
run_step() {
    d=$(dir_of "$1")
    act=
    [ "$(jq -r 'has("vps")' "$d/package.json")" = true ] && act=$2
    zz-log i "[zz-run] === Running $1 ($d/run.sh${act:+ $act}) ==="
    rc=0
    (cd "$d" && if [ -x run.sh ]; then ./run.sh $act; else bash run.sh $act; fi) || rc=$?
    if [ "$rc" -ne 0 ]; then
        zz-log e "[zz-run] Step '$1' failed (exit $rc). Fix it and re-run just this step with: zz-run $spec --only-$1"
        exit 1
    fi
    zz-log s "[zz-run] === Done: $1 ($2) ==="
}

for n in $(printf '%s\n' "$names" | sed '1!G;h;$!d'); do
    [ "$(state_get "$n")" = down ] && run_step "$n" down
done
for n in $names; do
    [ "$(state_get "$n")" = up ] && run_step "$n" up
done
exit 0
