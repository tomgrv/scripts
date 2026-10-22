#!/bin/sh
# zz-fetch [-r ref] -d <dir> <url> — get a git repository into <dir>:
# shallow clone when <dir> is absent, fast-forward to <ref> when it is already
# a checkout, or use it as is when it exists and is not a checkout. git is
# installed through zz-install when missing. What git prints is forwarded as
# operation output (zz-log o), apart from the script's own log lines.

. zz-colors

# --- arguments
eval "$(
    zz-args "Shallow clone or update a git repository" "$0" "$@" <<help
r ref ref Branch or tag to fetch (default main)
d dir dir Directory of the checkout (parent created if needed)
- url url Repository URL
help
)"

# --- parameters
[ -n "$url" ] && [ -n "$dir" ] || {
    zz-log e "Usage: zz-fetch [-r ref] -d <dir> <url> (-h for help)"
    exit 1
}
ref=${ref:-main}

# --- functions

# run_op <command> [args...]: run a command, forwarding its output as
# operation output; keeps its status.
run_op() {
    local rc=0
    local out

    out=$("$@" 2>&1) || rc=$?
    [ -z "$out" ] || printf '%s\n' "$out" | zz-log o
    return "$rc"
}

# --- fetch
command -v git >/dev/null 2>&1 || zz-install git || exit 1

if [ -d "$dir/.git" ]; then
    # Existing checkout: move it to the requested ref, dropping local changes.
    zz-log - "Updating {U $dir} to {B $ref}"
    run_op git -C "$dir" fetch --depth 1 origin -- "$ref" \
        && run_op git -C "$dir" checkout -q -f -B "$ref" FETCH_HEAD \
        && run_op git -C "$dir" reset -q --hard FETCH_HEAD
elif [ -d "$dir" ]; then
    zz-log n "{U $dir} is not a git checkout, using it as is"
else
    zz-log - "Cloning into {U $dir}"
    mkdir -p "$(dirname "$dir")" \
        && run_op git clone -q --depth 1 --branch "$ref" "$url" "$dir"
fi
