#!/bin/sh
# zz-fetch [-r ref] -d <dir> <url> — get a git repository into <dir>:
# shallow clone when <dir> is absent, fast-forward to <ref> when it is already
# a checkout, or use it as is when it exists and is not a checkout. git is
# installed through zz-install when missing. What git prints is forwarded as
# operation output (zz-log o), apart from the script's own log lines.

. zz-colors

# --- arguments
eval "$(zz-args "Shallow clone or update a git repository" "$0" "$@" <<help
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

# Run a command, forwarding its output as operation output; keeps its status.
op() {
    _rc=0
    _out=$("$@" 2>&1) || _rc=$?
    [ -z "$_out" ] || printf '%s\n' "$_out" | zz-log o
    return "$_rc"
}

# --- fetch
command -v git >/dev/null 2>&1 || zz-install git || exit 1

if [ -d "$dir/.git" ]; then
    # Existing checkout: move it to the requested ref, dropping local changes.
    zz-log i "Updating {U $dir} to $ref..."
    op git -C "$dir" fetch --depth 1 origin -- "$ref" &&
        op git -C "$dir" checkout -q -f -B "$ref" FETCH_HEAD &&
        op git -C "$dir" reset -q --hard FETCH_HEAD
elif [ -d "$dir" ]; then
    zz-log i "{U $dir} exists and is not a git checkout; using it in place."
else
    zz-log i "Cloning $url ($ref) into {U $dir}..."
    mkdir -p "$(dirname "$dir")" &&
        op git clone -q --depth 1 --branch "$ref" "$url" "$dir"
fi
