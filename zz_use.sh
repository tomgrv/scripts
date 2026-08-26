#!/bin/sh
# zz_use — on-demand dependency management: apt install or binary download +
# bin-linking, if and only if a command isn't already on PATH.
#
# Usage (each functional script calls this once, up front, for every
# external command it needs):
#   zz_use jq git curl
#
# For each <tool>:
#   1. `command -v <tool>` — already available, nothing to do.
#   2. Look up <tool> in config/zz_use.json (ZZ_USE_CONFIG to override):
#      - {"apt": "<pkg>"}  -> apt-get install -y <pkg> (sudo if not root)
#      - {"url": "...", "archive": "tar.gz"|"tar.xz"|"zip"|"raw",
#         "binpath": "..."} -> download, extract if needed, resolve a
#         writable bin dir via zz_bindir, and install the binary as <tool>.
#      URL/binpath templates support {VERSION}, {OS} (uname -s, lowercased),
#      {ARCH} (uname -m, mapped to amd64/arm64).
#   3. No config entry: fall back to `apt-get install -y <tool>` (same name)
#      when apt-get is available.
#   4. Still not found on PATH afterwards -> error, exit 1.
#
# Idempotent: safe to call on every script invocation — resolved tools are
# skipped in ~0ms via `command -v`.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=zz_wrap.sh
. "${SCRIPT_DIR}/zz_wrap.sh" 2>/dev/null || . zz_wrap

ZZ_USE_CONFIG="${ZZ_USE_CONFIG:-${SCRIPT_DIR}/config/zz_use.json}"

if [ $# -eq 0 ]; then
    zz_log e "Usage: zz_use <tool> [tool...]"
    exit 1
fi

_apt_install() {
    _pkg="$1"
    if ! command -v apt-get >/dev/null 2>&1; then
        return 1
    fi
    zz_log i "Installing {Purple $_pkg} via apt-get..."
    if [ "$(id -u)" = "0" ]; then
        apt-get update -qq && apt-get install -y -qq "$_pkg"
    elif command -v sudo >/dev/null 2>&1; then
        sudo apt-get update -qq && sudo apt-get install -y -qq "$_pkg"
    else
        zz_log e "apt-get requires root/sudo, neither available"
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
    # $1=template $2=version
    printf '%s' "$1" | sed \
        -e "s/{VERSION}/${2:-}/g" \
        -e "s/{OS}/$(_uname_os)/g" \
        -e "s/{ARCH}/$(_uname_arch)/g"
}

_download_install() {
    _tool="$1" _url_tpl="$2" _archive="$3" _binpath_tpl="$4" _version="$5"

    _url=$(_expand "$_url_tpl" "$_version")
    _binpath=$(_expand "${_binpath_tpl:-$_tool}" "$_version")

    zz_log i "Downloading {Purple $_tool} from {U $_url}..."
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

    [ -f "$_tmp/$_binpath" ] || { zz_log e "Downloaded archive for {Purple $_tool} has no {U $_binpath}"; return 1; }

    _dir=$(zz_bindir)
    chmod +x "$_tmp/$_binpath"
    cp "$_tmp/$_binpath" "$_dir/$_tool"
    zz_log s "Installed {Purple $_tool} to {U $_dir/$_tool}"

    rm -rf "$_tmp"
    trap - EXIT
}

for tool in "$@"; do
    if command -v "$tool" >/dev/null 2>&1; then
        zz_log - "{Purple $tool} already available"
        continue
    fi

    entry=""
    if [ -f "$ZZ_USE_CONFIG" ] && command -v jq >/dev/null 2>&1; then
        entry=$(jq -c --arg t "$tool" '.[$t] // empty' "$ZZ_USE_CONFIG" 2>/dev/null)
    fi

    if [ -n "$entry" ]; then
        apt_pkg=$(printf '%s' "$entry" | jq -r '.apt // empty')
        url=$(printf '%s' "$entry" | jq -r '.url // empty')

        if [ -n "$apt_pkg" ]; then
            _apt_install "$apt_pkg" || zz_log w "apt install of {Purple $apt_pkg} failed"
        elif [ -n "$url" ]; then
            archive=$(printf '%s' "$entry" | jq -r '.archive // empty')
            binpath=$(printf '%s' "$entry" | jq -r '.binpath // empty')
            version=$(printf '%s' "$entry" | jq -r '.version // empty')
            _download_install "$tool" "$url" "$archive" "$binpath" "$version" \
                || zz_log w "Download install of {Purple $tool} failed"
        fi
    else
        _apt_install "$tool" || true
    fi

    if ! command -v "$tool" >/dev/null 2>&1; then
        zz_log e "Unable to provide required dependency: {Purple $tool}"
        exit 1
    fi
done
