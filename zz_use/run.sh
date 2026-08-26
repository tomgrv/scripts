#!/bin/sh
# zz_use — the activator: on-demand dependency management, triggering
# retrieval or install if and only if a command isn't already on PATH.
#
# Usage (each functional script calls this once, up front, for every
# dependency it needs — including the zz_* utility scripts it sources):
#   zz_use zz_log zz_args jq git
#
# Two install paths:
#
#   - zz_* tools: all zz_* scripts in this repo are retrieved and installed
#     together, as a single bundle, the first time any one of them is
#     missing — not one at a time. (They ship together and are cheap to
#     install as a set; installing them individually would mean N
#     downloads/copies for what is really one artifact.)
#
#   - Any other tool: looked up in config/zz_use.json (ZZ_USE_CONFIG to
#     override):
#       {"apt": "<pkg>"}  -> apt-get install -y <pkg> (sudo if not root)
#       {"url": "...", "archive": "tar.gz"|"tar.xz"|"zip"|"raw",
#        "binpath": "..."} -> download, extract if needed, resolve a
#        writable bin dir, and install the binary as <tool>. Templates
#        support {VERSION}, {OS} (uname -s, lowercased), {ARCH} (uname -m,
#        mapped to amd64/arm64).
#     No config entry -> fall back to `apt-get install -y <tool>` (same
#     name) when apt-get is available.
#
# Still not found on PATH afterwards -> error, exit 1.
#
# Idempotent: safe to call on every script invocation — resolved tools are
# skipped in ~0ms via `command -v`.

set -e

# Follow symlinks (an installed/linked "zz_use" on PATH is a symlink to this
# file) so SCRIPT_DIR/ROOT_DIR resolve to the real checkout, not the link's
# directory.
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# zz_log may itself not be installed yet on a first-ever bootstrap: fall
# back to plain stderr output rather than depending on it circularly.
_zzu_log() {
    if command -v zz_log >/dev/null 2>&1; then
        zz_log "$@"
    else
        lvl="$1" && shift
        printf '[%s] %s\n' "$lvl" "$*" >&2
    fi
}

ZZ_USE_CONFIG="${ZZ_USE_CONFIG:-${SCRIPT_DIR}/config/zz_use.json}"
ZZ_USE_REPO_URL="${ZZ_USE_REPO_URL:-https://github.com/tomgrv/scripts/archive/refs/heads/main.tar.gz}"

if [ $# -eq 0 ]; then
    _zzu_log e "Usage: zz_use <tool> [tool...]"
    exit 1
fi

_bindir() {
    _t="$1"
    if command -v zz_bindir >/dev/null 2>&1; then
        eval "$(zz_bindir ${_t:+-t "$_t"})"
        printf '%s\n' "$dir"
        return 0
    fi
    # Bootstrap fallback, mirroring zz_bindir's own default candidate order.
    for c in "${INSTALL_BIN_DIR:-/usr/local/bin}" "${HOME:-/root}/.local/bin"; do
        if [ -d "$c" ] && [ -w "$c" ]; then
            case ":$PATH:" in
            *":$c:"*) ;;
            *) export PATH="$c:$PATH" ;;
            esac
            printf '%s\n' "$c"
            return 0
        fi
    done
    mkdir -p "${INSTALL_BIN_DIR:-/usr/local/bin}" 2>/dev/null && printf '%s\n' "${INSTALL_BIN_DIR:-/usr/local/bin}" && return 0
    return 1
}

# _bindir runs (and exports PATH) inside a subshell whenever it's captured
# via $(...), so its PATH extension never reaches this script's own
# environment. Re-apply it here so a tool installed just now is actually
# found by this script's own `command -v` checks below.
_ensure_path() {
    case ":$PATH:" in
    *":$1:"*) ;;
    *) export PATH="$1:$PATH" ;;
    esac
}

# Install every zz_*/ folder's run.sh in this repo at once, as a single
# bundle, linked onto the bin dir under its folder name (e.g. zz_log/run.sh
# -> <bindir>/zz_log).
_install_zz_bundle() {
    _dir=$(_bindir) || { _zzu_log e "No writable bin directory found for zz_* bundle install"; return 1; }
    _ensure_path "$_dir"

    if ls -d "${ROOT_DIR}"/zz_*/ >/dev/null 2>&1 && [ -f "${ROOT_DIR}/zz_colors/run.sh" ]; then
        _zzu_log i "Installing zz_* bundle from {U ${ROOT_DIR}} to {U ${_dir}}..."
        for _d in "${ROOT_DIR}"/zz_*/; do
            [ -f "${_d}run.sh" ] || continue
            _name=$(basename "$_d")
            cp "${_d}run.sh" "${_dir}/${_name}"
            chmod +x "${_dir}/${_name}"
        done
    else
        _zzu_log i "Retrieving zz_* bundle from {U ${ZZ_USE_REPO_URL}}..."
        _tmp=$(mktemp -d)
        trap 'rm -rf "$_tmp"' EXIT
        curl -fsSL "$ZZ_USE_REPO_URL" | tar -xz -C "$_tmp" --strip-components=1
        for _d in "${_tmp}"/zz_*/; do
            [ -f "${_d}run.sh" ] || continue
            _name=$(basename "$_d")
            cp "${_d}run.sh" "${_dir}/${_name}"
            chmod +x "${_dir}/${_name}"
        done
        rm -rf "$_tmp"
        trap - EXIT
    fi
    _zzu_log s "zz_* bundle installed to {U ${_dir}}"
}

_apt_install() {
    _pkg="$1"
    if ! command -v apt-get >/dev/null 2>&1; then
        return 1
    fi
    _zzu_log i "Installing {Purple $_pkg} via apt-get..."
    if [ "$(id -u)" = "0" ]; then
        apt-get update -qq && apt-get install -y -qq "$_pkg"
    elif command -v sudo >/dev/null 2>&1; then
        sudo apt-get update -qq && sudo apt-get install -y -qq "$_pkg"
    else
        _zzu_log e "apt-get requires root/sudo, neither available"
        return 1
    fi
}

_uname_os() {
    uname -s | tr '[:upper:]' '[:lower:]'
}

_uname_arch() {
    case "$(uname -m)" in
    x86_64 | amd64) echo amd64 ;;
    aarch64 | arm64) echo arm64 ;;
    *) uname -m ;;
    esac
}

_expand() {
    printf '%s' "$1" | sed \
        -e "s/{VERSION}/${2:-}/g" \
        -e "s/{OS}/$(_uname_os)/g" \
        -e "s/{ARCH}/$(_uname_arch)/g"
}

_download_install() {
    _tool="$1" _url_tpl="$2" _archive="$3" _binpath_tpl="$4" _version="$5"

    _url=$(_expand "$_url_tpl" "$_version")
    _binpath=$(_expand "${_binpath_tpl:-$_tool}" "$_version")

    _zzu_log i "Downloading {Purple $_tool} from {U $_url}..."
    _tmp=$(mktemp -d)
    trap 'rm -rf "$_tmp"' EXIT

    case "$_archive" in
    tar.gz | tgz)
        curl -fsSL "$_url" | tar -xz -C "$_tmp"
        ;;
    tar.xz)
        curl -fsSL "$_url" | tar -xJ -C "$_tmp"
        ;;
    zip)
        curl -fsSL "$_url" -o "$_tmp/a.zip" && unzip -q "$_tmp/a.zip" -d "$_tmp"
        ;;
    raw | "" | *)
        curl -fsSL "$_url" -o "$_tmp/$_tool"
        chmod +x "$_tmp/$_tool"
        _binpath="$_tool"
        ;;
    esac

    [ -f "$_tmp/$_binpath" ] || { _zzu_log e "Downloaded archive for {Purple $_tool} has no {U $_binpath}"; return 1; }

    _dir=$(_bindir)
    _ensure_path "$_dir"
    chmod +x "$_tmp/$_binpath"
    cp "$_tmp/$_binpath" "$_dir/$_tool"
    _zzu_log s "Installed {Purple $_tool} to {U $_dir/$_tool}"

    rm -rf "$_tmp"
    trap - EXIT
}

_zz_bundle_installed=0

for tool in "$@"; do
    if command -v "$tool" >/dev/null 2>&1; then
        _zzu_log - "{Purple $tool} already available"
        continue
    fi

    case "$tool" in
    zz_*)
        if [ "$_zz_bundle_installed" -eq 0 ]; then
            _install_zz_bundle
            _zz_bundle_installed=1
        fi
        ;;
    *)
        entry=""
        if [ -f "$ZZ_USE_CONFIG" ] && command -v jq >/dev/null 2>&1; then
            entry=$(jq -c --arg t "$tool" '.[$t] // empty' "$ZZ_USE_CONFIG" 2>/dev/null)
        fi

        if [ -n "$entry" ]; then
            apt_pkg=$(printf '%s' "$entry" | jq -r '.apt // empty')
            url=$(printf '%s' "$entry" | jq -r '.url // empty')

            if [ -n "$apt_pkg" ]; then
                _apt_install "$apt_pkg" || _zzu_log w "apt install of {Purple $apt_pkg} failed"
            elif [ -n "$url" ]; then
                archive=$(printf '%s' "$entry" | jq -r '.archive // empty')
                binpath=$(printf '%s' "$entry" | jq -r '.binpath // empty')
                version=$(printf '%s' "$entry" | jq -r '.version // empty')
                _download_install "$tool" "$url" "$archive" "$binpath" "$version" \
                    || _zzu_log w "Download install of {Purple $tool} failed"
            fi
        else
            _apt_install "$tool" || true
        fi
        ;;
    esac

    if ! command -v "$tool" >/dev/null 2>&1; then
        _zzu_log e "Unable to provide required dependency: {Purple $tool}"
        exit 1
    fi
done
