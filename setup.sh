#!/bin/sh
#
# setup.sh — one-line bootstrapper: downloads (or reuses a cached copy of)
# the core zz_* scripts from this repo and links them onto PATH.
#
#   curl -fsSL https://raw.githubusercontent.com/tomgrv/scripts/main/setup.sh | sh
#
# That's the only thing that needs fetching up front. Once the core zz_*
# scripts (zz_use foremost) are linked, every other script, core or
# functional, resolves and installs its own further dependencies on demand
# via zz_use, the same way this script resolves its own: from a local
# cache (ZZ_CACHE_DIR, default ~/.cache/zz_scripts) when warm, or a fresh
# download into that cache otherwise. Run `zz_update` afterwards to force
# a fresh download, bypassing the cache.
#
# Deliberately POSIX /bin/sh, no dependency on anything in this repo
# (including zz_use itself, which this script is what makes available in
# the first place) beyond a shell and curl/tar.

set -eu

REPO_URL="${ZZ_SETUP_REPO_URL:-https://github.com/tomgrv/scripts/archive/refs/heads/main.tar.gz}"
CACHE_DIR="${ZZ_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/zz_scripts}"

log() { printf '\033[0;34m[zz-setup]\033[0m %s\n' "$*"; }
ok() { printf '\033[0;32m[zz-setup]\033[0m %s\n' "$*"; }
die() {
    printf '\033[0;31m[zz-setup]\033[0m %s\n' "$*" >&2
    exit 1
}

command -v curl >/dev/null 2>&1 || die "curl is required"
command -v tar >/dev/null 2>&1 || die "tar is required"

# Resolve a writable bin directory on PATH, creating one if needed.
# Mirrors zz_bindir's own candidate order so a script installed by either
# path ends up in the same place.
bindir() {
    for c in "${INSTALL_BIN_DIR:-/usr/local/bin}" "${HOME:-/root}/.local/bin"; do
        if [ -d "$c" ] && [ -w "$c" ]; then
            printf '%s\n' "$c"
            return 0
        fi
    done
    for c in "${INSTALL_BIN_DIR:-/usr/local/bin}" "${HOME:-/root}/.local/bin"; do
        mkdir -p "$c" 2>/dev/null && [ -w "$c" ] && printf '%s\n' "$c" && return 0
    done
    die "No writable bin directory found (set INSTALL_BIN_DIR)"
}

BIN_DIR=$(bindir)
case ":$PATH:" in
*":$BIN_DIR:"*) ;;
*) log "Add {$BIN_DIR} to PATH to use the installed scripts in this shell" ;;
esac

if [ -f "$CACHE_DIR/zz_colors/run.sh" ]; then
    log "Using cached zz_* bundle at ${CACHE_DIR}..."
else
    log "Downloading core zz_* scripts from ${REPO_URL}..."
    TMP_DIR="${CACHE_DIR}.tmp.$$"
    rm -rf "$TMP_DIR"
    mkdir -p "$TMP_DIR"
    trap 'rm -rf "$TMP_DIR"' EXIT
    curl -fsSL "$REPO_URL" | tar -xz -C "$TMP_DIR" --strip-components=1
    [ -f "$TMP_DIR/zz_colors/run.sh" ] || die "Downloaded archive has no zz_* scripts (unexpected repo layout)"
    mkdir -p "$(dirname "$CACHE_DIR")"
    rm -rf "$CACHE_DIR"
    mv "$TMP_DIR" "$CACHE_DIR"
    trap - EXIT
fi

log "Linking core zz_* scripts to ${BIN_DIR}..."
for dir in "$CACHE_DIR"/zz_*/; do
    [ -f "${dir}run.sh" ] || continue
    name=$(basename "$dir")
    # Write to a temp name and `mv` into place (atomic rename) rather than
    # `cp`ing over the target directly, in case a same-named script from a
    # previous install is currently executing.
    cp "${dir}run.sh" "$BIN_DIR/.${name}.$$"
    chmod +x "$BIN_DIR/.${name}.$$"
    mv "$BIN_DIR/.${name}.$$" "$BIN_DIR/$name"
    ok "  $name"
done

ok "Core zz_* scripts installed to ${BIN_DIR}. Any other script (zz_use ... / <verb>-<topic>) resolves its own further dependencies on first use."
