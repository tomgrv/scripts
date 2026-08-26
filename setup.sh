#!/bin/sh
#
# setup.sh — one-line bootstrapper: downloads this repo to a temp dir, then
# lets the zz_use it just downloaded install the core zz_* bundle from
# there (its own local-checkout install path, resolving a bin dir and
# linking every zz_* script onto it) and discards the temp dir.
#
#   curl -fsSL https://raw.githubusercontent.com/tomgrv/scripts/main/setup.sh | sh
#
# Pin to a specific tag, branch, or commit instead of main with a
# positional arg (curl ... | sh -s -- v2) or ZZ_SETUP_REPO_REF=v2:
#
#   curl -fsSL .../setup.sh | sh -s -- v2
#
# Deliberately dumb and DRY: this script owns none of the bin-dir
# resolution or linking logic itself — that's zz_use's job, and
# duplicating it here would just be a second copy to keep in sync. Once
# the core zz_* scripts (zz_use foremost) are linked, every other script,
# core or functional, resolves and installs its own further dependencies
# on demand via zz_use — from a local cache (ZZ_CACHE_DIR, default
# ~/.cache/zz_scripts) when warm, or a fresh download into that cache
# otherwise. Run `zz_update` afterwards to force a fresh download,
# bypassing the cache.
#
# Deliberately POSIX /bin/sh, no dependency on anything in this repo
# beyond a shell and curl/tar to get the temp download in place.

set -eu

REPO_REF="${1:-${ZZ_SETUP_REPO_REF:-main}}"
# The default is a separate plain assignment, not inlined into
# ${ZZ_SETUP_REPO_URL:-...}: a literal "}" inside that expansion's default
# text (from "{REF}") terminates the expansion early at parse time,
# regardless of quoting — `${X:-a{REF}.b}` evaluates to `a{REF` with
# literal `.b}` appended after, not the intended default string.
_REPO_URL_DEFAULT='https://github.com/tomgrv/scripts/archive/{REF}.tar.gz'
REPO_URL=$(printf '%s' "${ZZ_SETUP_REPO_URL:-$_REPO_URL_DEFAULT}" | sed "s/{REF}/${REPO_REF}/g")

log() { printf '\033[0;34m[zz-setup]\033[0m %s\n' "$*"; }
die() {
    printf '\033[0;31m[zz-setup]\033[0m %s\n' "$*" >&2
    exit 1
}

command -v curl >/dev/null 2>&1 || die "curl is required"
command -v tar >/dev/null 2>&1 || die "tar is required"

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

log "Downloading ${REPO_URL} to a temp dir..."
curl -fsSL "$REPO_URL" | tar -xz -C "$TMP_DIR" --strip-components=1

[ -f "$TMP_DIR/zz_use/run.sh" ] || die "Downloaded archive has no zz_use/run.sh (unexpected repo layout)"

log "Installing core zz_* scripts via the downloaded zz_use..."
sh "$TMP_DIR/zz_use/run.sh" \
    zz_use zz_update zz_colors zz_log zz_args zz_prompt zz_ask zz_input zz_bindir zz_dispatch zz_npx zz_persist
