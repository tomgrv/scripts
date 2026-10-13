#!/bin/sh
# zz-setup <org>/<repo>[@<ref>] [args...] — fetch a GitHub repo and run it
# the way vps-setup does for perspikapps/vps:
#   1. shallow clone (or fast-forward) into a fixed directory;
#   2. if the root package.json lists workspaces, propose the runnable ones
#      (skip/up/down menu, dependencies auto-enabled), then list the inputs
#      they declare, offer to set them (persisted to an env file), and run
#      each selected workspace's run.sh;
#   3. otherwise (or with ZZ_SETUP_ENTRY) exec the repo's own installer with
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
# Env: ZZ_SETUP_REF (default main; "@<ref>" wins), ZZ_SETUP_DIR (parent of the
# checkout; default /opt as root, else ~/.local/share), ZZ_SETUP_URL_BASE
# (default https://github.com), ZZ_SETUP_ENTRY, ZZ_SETUP_ENV_FILE (inputs; default
# /etc/<repo>.env as root, else <checkout>/.env, read literally, written by
# zz-persist), ZZ_SETUP_PROFILE (also export persisted inputs from
# /etc/profile.d/<name>.sh).

set -e

. zz-colors

[ -n "$1" ] || {
    zz-log e "Usage: zz-setup <org>/<repo>[@<ref>] [args...]"
    exit 1
}

spec=$1
shift

case "$spec" in
*@*)
    ref=${spec#*@}
    spec=${spec%@*}
    ;;
*) ref=${ZZ_SETUP_REF:-main} ;;
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
url="${ZZ_SETUP_URL_BASE:-https://github.com}/$spec.git"

if [ -n "$ZZ_SETUP_DIR" ]; then
    parent=$ZZ_SETUP_DIR
elif [ "$(id -u)" -eq 0 ]; then
    parent=/opt
else
    parent=$HOME/.local/share
fi
dir="$parent/$repo"

zz-log i "[zz-setup] repo=$spec ref=$ref dir=$dir"
if [ -z "$ZZ_SETUP_REF" ] && [ "$ref" = main ] && [ "${spec#*@}" = "$spec" ]; then
    zz-log w "[zz-setup] No ref given, using 'main'. A plain 'export' before 'sudo zz-setup' is dropped by sudo: put it on the sudo line, e.g. 'sudo ZZ_SETUP_REF=... zz-setup'."
fi

command -v git >/dev/null 2>&1 || zz-install git

if [ -d "$dir/.git" ]; then
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
    echo "Usage: zz-setup <org>/<repo>[@<ref>] [options]"
    echo "       (no options, on a terminal: interactive menu)"
    echo
    for n in $names; do
        printf '  --with-%-20s %s\n' "$n" "$(desc_of "$n")"
    done
    echo
    echo "Also: --skip-<n>, --only-<n> (repeatable, overrides skip/with), --down-<n>,"
    echo "      --down-all, --force-down (allow --down-<n> while a dependent is up),"
    echo "      --status (show each workspace's state and inputs, run nothing), -h"
}

force_down=0
status_only=0
only=
nflags=0
for arg in "$@"; do
    nflags=$((nflags + 1))
    case "$arg" in
    --down-all) for n in $names; do state_set "$n" down; done ;;
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
    --status) status_only=1 ;;
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
                zz-log e "[zz-setup] Refusing to bring '$n' down: '$o' depends on it and is still enabled. Also pass --down-$o, or --force-down."
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
# from "vps.inputs" (object keyed by var) and "config.input" (zz-call array).
inputs_of() {
    jq -r --arg n "$1" '
      ((.vps.inputs // {}) | to_entries[]
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

# Make the env file owner-only: zz-persist only stores a secret in one.
env_secure() { (umask 077 && touch "$envfile") && chmod 600 "$envfile" 2>/dev/null || true; }

# Also export a persisted value in new shells when ZZ_SETUP_PROFILE names a
# /etc/profile.d/<name>.sh snippet (the value is quoted: shells source it).
profile_persist() {
    [ -n "$ZZ_SETUP_PROFILE" ] || return 0
    _q=$(printf '%s' "$2" | sed "s/'/'\\\\''/g")
    zz-persist -p "$ZZ_SETUP_PROFILE" "$1" "'$_q'"
}

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
        # zz-persist asks (masked for secrets), shows the stored value, and
        # writes it; the answer is then read back into this run.
        env_secure
        q="${choice}${desc:+ ($desc)}"
        if [ "$secret" != true ]; then
            if [ -n "$def" ]; then
                zz-persist -f "$envfile" -i "$q" -v "$def" "$choice"
            else
                zz-persist -f "$envfile" -i "$q" "$choice"
            fi
        elif [ -n "$def" ]; then
            zz-persist -f "$envfile" -i "$q" -s "$def" "$choice"
        else
            zz-persist -f "$envfile" -i "$q" -S "$choice"
        fi
        _v=$(env_get "$choice")
        if [ -n "$_v" ]; then
            eval "$choice=\$_v"
            eval "export $choice"
            profile_persist "$choice" "$_v"
        fi
    done
fi

# Resolve every declared input with zz-call: the caller's environment (also
# persisted), then the env file, then the default; nothing is prompted here.
# Required-but-empty is a warning, like vps-setup.
pkgs=
for n in $up_names; do pkgs="$pkgs${pkgs:+:}$(dir_of "$n")/package.json"; done
if [ -n "$pkgs" ]; then
    eval "$(zz-call -n -e -f "$envfile" ${ZZ_SETUP_PROFILE:+-P "$ZZ_SETUP_PROFILE"} -p "$pkgs")"
fi
while IFS="$us" read -r var desc req def owner secret; do
    [ -n "$var" ] || continue
    [ "$(input_status "$var" "$req")" = required ] &&
        zz-log w "[zz-setup] $var is required by '$owner' but is empty; that step will likely fail without it."
done <<EOF
$all_inputs
EOF

# --- run: down in reverse order first, then up in order.
run_step() {
    d=$(dir_of "$1")
    act=
    [ "$(jq -r 'has("vps")' "$d/package.json")" = true ] && act=$2
    zz-log i "[zz-setup] === Running $1 ($d/run.sh${act:+ $act}) ==="
    rc=0
    (cd "$d" && if [ -x run.sh ]; then ./run.sh $act; else bash run.sh $act; fi) || rc=$?
    if [ "$rc" -ne 0 ]; then
        zz-log e "[zz-setup] Step '$1' failed (exit $rc). Fix it and re-run just this step with: zz-setup $spec --only-$1"
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
