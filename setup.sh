#!/bin/sh
#
# setup.sh — one-line bootstrapper: downloads this repo to a temp dir, then
# lets the zz-use it just downloaded install the core zz-* bundle from
# there (its own local-checkout install path, resolving a bin dir and
# linking every zz-* script onto it) and discards the temp dir.
#
#   curl -fsSL https://raw.githubusercontent.com/tomgrv/scripts/main/setup.sh | sh
#
# Pin to a specific tag, branch, or commit instead of main with
# ZZ_ORIGIN_REF=v2. Bootstrap from a different org/repo entirely with
# ZZ_ORIGIN=someorg/otherscripts. Both are exported for the zz-use this script hands off to (and anything
# it execs), so every zz-use call afterwards defaults to this same origin
# — "wherever this install actually came from" — rather than a hardcoded
# tomgrv/scripts:
#
#   curl -fsSL .../setup.sh | ZZ_ORIGIN_REF=v2 sh
#
# Every positional arg is passed as-is to `zz-use -x`: the first is the tool
# to install and exec, the rest are its argv.
#
#   curl -fsSL .../setup.sh | sh -s -- some-tool --some-flag
#
# Deliberately dumb and DRY: this script owns none of the bin-dir
# resolution or linking logic itself — that's zz-use's job, and
# duplicating it here would just be a second copy to keep in sync. Once
# the core zz-* scripts (zz-use foremost) are linked, every other script,
# core or functional, resolves and installs its own further dependencies
# on demand via zz-use — from a local cache (ZZ_CACHE_DIR, default
# ~/.cache/zz_scripts) when warm, or a fresh download into that cache
# otherwise. Run `zz-use -f 'zz-*'` afterwards to force a fresh download,
# bypassing the cache.
#
# Deliberately POSIX /bin/sh, no dependency on anything in this repo
# beyond a shell and curl/tar to get the temp download in place.

set -eu

export ZZ_ORIGIN="${ZZ_ORIGIN:-tomgrv/scripts}"
export ZZ_ORIGIN_REF="${ZZ_ORIGIN_REF:-main}"
# The default is a separate plain assignment, not inlined into
# ${ZZ_SETUP_REPO_URL:-...}: a literal "}" inside that expansion's default
# text (from "{ORIGIN}"/"{REF}") terminates the expansion early at parse
# time, regardless of quoting — `${X:-a{REF}.b}` evaluates to `a{REF`
# with literal `.b}` appended after, not the intended default string.
# Both substitutions use "|" as the sed delimiter instead of "/": ORIGIN
# always contains "/" (org/repo), and REF can too (a branch name like
# "feature/foo") — either would break the s/// syntax with "/" as the
# delimiter.
_REPO_URL_DEFAULT='https://github.com/{ORIGIN}/archive/{REF}.tar.gz'
REPO_URL=$(printf '%s' "${ZZ_SETUP_REPO_URL:-$_REPO_URL_DEFAULT}" | sed -e "s|{ORIGIN}|${ZZ_ORIGIN}|g" -e "s|{REF}|${ZZ_ORIGIN_REF}|g")

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

[ -f "$TMP_DIR/zz-use/run.sh" ] || die "Downloaded archive has no zz-use/run.sh (unexpected repo layout)"

log "Installing core zz-* scripts via the downloaded zz-use..."
sh "$TMP_DIR/zz-use/run.sh" "zz-*" zz

# Child, not exec: the temp dir cleanup trap must still run afterwards. Under
# `curl | sh` stdin is the script pipe, so hand the child the terminal (when
# there is one) for its prompts; this shell keeps reading the script from stdin.
if [ "$#" -gt 0 ]; then
    # sudo gives its command a pty it only feeds from sudo's own stdin: with the
    # script piped in, prompts show up but typed answers never arrive.
    if [ ! -t 0 ] && [ -n "${SUDO_USER:-}" ] && (: </dev/tty) 2>/dev/null; then
        log "Piped into sudo, typed answers may not reach the prompts; if it hangs, use:"
        log "  sudo ZZ_ORIGIN_REF=${ZZ_ORIGIN_REF} sh -c \"\$(curl -fsSL https://raw.githubusercontent.com/${ZZ_ORIGIN}/${ZZ_ORIGIN_REF}/setup.sh)\" setup $*"
    fi
    if (: </dev/tty) 2>/dev/null; then
        sh "$TMP_DIR/zz-use/run.sh" -x "$@" </dev/tty
    else
        sh "$TMP_DIR/zz-use/run.sh" -x "$@"
    fi
fi
