#!/bin/sh
#
# setup.sh — one-line bootstrapper: temp-downloads only the core zz_*
# scripts from this repo and links them onto PATH, then discards the
# download. That's the only thing that needs fetching up front — once the
# core zz_* scripts (zz_use foremost) are linked, every other script,
# core or functional, resolves and installs its own further dependencies
# on demand via zz_use. No persistent checkout is kept.
#
#   curl -fsSL https://raw.githubusercontent.com/tomgrv/scripts/main/setup.sh | sh
#
# Deliberately POSIX /bin/sh, no dependency on anything in this repo
# (including zz_use itself, which this script is what makes available in
# the first place) beyond a shell and curl/tar.

set -eu

REPO_URL="${ZZ_SETUP_REPO_URL:-https://github.com/tomgrv/scripts/archive/refs/heads/main.tar.gz}"

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

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

log "Downloading core zz_* scripts from ${REPO_URL}..."
curl -fsSL "$REPO_URL" | tar -xz -C "$TMP_DIR" --strip-components=1

[ -f "$TMP_DIR/zz_colors/run.sh" ] || die "Downloaded archive has no zz_* scripts (unexpected repo layout)"

log "Linking core zz_* scripts to ${BIN_DIR}..."
for dir in "$TMP_DIR"/zz_*/; do
    [ -f "${dir}run.sh" ] || continue
    name=$(basename "$dir")
    cp "${dir}run.sh" "$BIN_DIR/$name"
    chmod +x "$BIN_DIR/$name"
    ok "  $name"
done

rm -rf "$TMP_DIR"
trap - EXIT

ok "Core zz_* scripts installed to ${BIN_DIR}. Any other script (zz_use ... / <verb>-<topic>) resolves its own further dependencies on first use."
