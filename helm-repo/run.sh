#!/bin/sh
# helm-repo <name> <url> [<name> <url>...] — add Helm repositories (replacing an alias
# whose URL changed) and refresh them, failing with a message that names the URL.

. zz-colors

if [ "$#" -lt 2 ] || [ $(($# % 2)) -ne 0 ]; then
    zz-log e "Usage: helm-repo <name> <url> [<name> <url>...]"
    exit 1
fi

names=""
while [ "$#" -gt 0 ]; do
    name="$1" url="$2"
    shift 2
    case "$url" in
        http://* | https://*) ;;
        *) zz-log e "Helm repository $name: the URL must be http(s) (got '$url')." && exit 1 ;;
    esac
    helm repo add "$name" "$url" --force-update >/dev/null || {
        zz-log e "Could not add the Helm repository $url."
        exit 1
    }
    names="$names $name"
done
# shellcheck disable=SC2086
helm repo update $names >/dev/null || {
    zz-log e "Could not fetch the chart index of:$names (check the URL and any access it needs)."
    exit 1
}
