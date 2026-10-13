#!/bin/sh
# zz-run <org>/<repo>[@<ref>] [args...] — fetch a GitHub repo and run its
# setup entrypoint, the way vps-setup does for perspikapps/vps: shallow
# clone (or fast-forward an existing checkout) into a fixed directory, then
# exec the repo's own installer with the remaining arguments.
#
# Entrypoint, first match wins: $ZZ_RUN_ENTRY (relative to the checkout),
# <repo>-setup/run.sh, setup.sh, run.sh.
#
# Env: ZZ_RUN_REF (default main; "@<ref>" wins), ZZ_RUN_DIR (parent of the
# checkout; default /opt as root, else ~/.local/share), ZZ_RUN_URL_BASE
# (default https://github.com), ZZ_RUN_ENTRY.

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

entry=
for cand in "$ZZ_RUN_ENTRY" "$repo-setup/run.sh" setup.sh run.sh; do
    if [ -n "$cand" ] && [ -f "$dir/$cand" ]; then
        entry=$cand
        break
    fi
done

[ -n "$entry" ] || {
    zz-log e "[zz-run] No entrypoint found in $dir (tried $repo-setup/run.sh, setup.sh, run.sh)."
    exit 1
}

zz-log i "[zz-run] Running {Purple $entry}..."
cd "$dir"
exec sh -c '[ -x "$0" ] && exec "$0" "$@" || exec bash "$0" "$@"' "$dir/$entry" "$@"
