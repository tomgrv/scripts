#!/bin/sh
# zz_use — the activator: on-demand dependency management, triggering
# retrieval or install if and only if a command isn't already on PATH.
#
# Usage (each functional script calls this once, up front, for every
# dependency it needs — including the zz_* utility scripts it sources):
#   zz_use zz_log zz_args jq git
#
# Any tool name accepts an optional @<ref> suffix to pin it to a specific
# tag, branch, or commit of this repo instead of the default branch (main):
#   zz_use validate-json@v2
# A @<ref> request always (re)installs — the existing "already available"
# skip only applies to unversioned requests, since there's no way to tell
# from an installed script alone which ref it came from. Each ref gets its
# own cache slot (see ZZ_CACHE_DIR below), so pinning one script to an
# older tag doesn't disturb anything already resolved at main.
#
# Two install paths:
#
#   - zz_* tools: all zz_* scripts in this repo are retrieved and installed
#     together, as a single bundle, the first time any one of them is
#     missing — not one at a time. (They ship together and are cheap to
#     install as a set; installing them individually would mean N
#     downloads/copies for what is really one artifact.) When not running
#     from a local checkout, the bundle is fetched once into a local cache
#     directory (ZZ_CACHE_DIR/<ref>, default ~/.cache/zz_scripts/main) and
#     every subsequent bundle install at that ref links from that cache —
#     no repeat network round-trip. Use `zz_update` (or `zz_use --force
#     ...`) to force a fresh download, bypassing the cache.
#
#   - Any other tool:
#     1. A functional script from this same repo (e.g. `zz_use load-json`
#        installs load-json/run.sh) — installed individually (not as a
#        bundle: unlike the core zz_* set, functional scripts aren't all
#        needed together), from the same local-checkout/cache/download
#        source a zz_* bundle install would use.
#     2. Otherwise, looked up in config/zz_use.json (ZZ_USE_CONFIG to
#        override):
#          {"apt": "<pkg>"}  -> apt-get install -y <pkg> (sudo if not root)
#          {"url": "...", "archive": "tar.gz"|"tar.xz"|"zip"|"raw",
#           "binpath": "..."} -> download, extract if needed, resolve a
#           writable bin dir, and install the binary as <tool>. Templates
#           support {VERSION}, {OS} (uname -s, lowercased), {ARCH}
#           (uname -m, mapped to amd64/arm64).
#     3. No config entry -> fall back to `apt-get install -y <tool>` (same
#        name) when apt-get is available. (@<ref> has no meaning for an
#        apt package; it's simply ignored if this is the path taken.)
#
# Still not found on PATH afterwards -> error, exit 1.
#
# Idempotent: safe to call on every script invocation — resolved tools are
# skipped in ~0ms via `command -v`, unless --force or @<ref> is given.
#
# DRY by construction: zz_use never reimplements what zz_bindir/zz_log/etc.
# already do. Bootstrapping them before they're installed doesn't mean
# hand-rolling fallback versions of their logic — it means resolving the
# "tarball context" (_resolve_src below: a checkout, a warm cache, or a
# freshly downloaded tarball are all just a directory of zz_*/run.sh
# siblings) and exposing those real files on PATH under their conventional
# names, so every later `command -v zz_bindir`/`zz_log`/`. zz_colors`
# throughout this script — and inside zz_bindir/zz_log's own source, which
# itself does `. zz_colors` — just finds and runs the real thing.

set -e

FORCE=0
case "${1:-}" in
--force | -f)
    FORCE=1
    shift
    ;;
esac

# Follow symlinks (an installed/linked "zz_use" on PATH is a symlink to this
# file) so SCRIPT_DIR/ROOT_DIR resolve to the real checkout, not the link's
# directory.
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

ZZ_USE_CONFIG="${ZZ_USE_CONFIG:-${SCRIPT_DIR}/config/zz_use.json}"
# {REF} is substituted with the requested tag/branch/commit (default
# "main") — GitHub's archive endpoint accepts a tag, a branch, or a commit
# SHA interchangeably in that same position.
#
# The default is built as a separate plain assignment, not inlined into
# ${ZZ_USE_REPO_URL:-...}: a literal "}" inside that expansion's default
# text (from "{REF}") terminates the expansion early at parse time,
# regardless of quoting — `${X:-a{REF}.b}` evaluates to `a{REF` with
# literal `.b}` appended after, not the intended default string.
_ZZ_USE_REPO_URL_DEFAULT='https://github.com/tomgrv/scripts/archive/{REF}.tar.gz'
ZZ_USE_REPO_URL="${ZZ_USE_REPO_URL:-$_ZZ_USE_REPO_URL_DEFAULT}"
ZZ_CACHE_DIR="${ZZ_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/zz_scripts}"

# Every temp dir this script creates (a fresh cache download, a
# _download_install extraction, the bootstrap symlink dir) is cleaned up
# through this single mechanism instead of each having its own EXIT trap
# (which would just clobber each other).
_TMP_DIRS=""
_add_tmp() { _TMP_DIRS="${_TMP_DIRS} $1"; }
_cleanup() { [ -n "$_TMP_DIRS" ] && rm -rf $_TMP_DIRS; }
trap _cleanup EXIT

# zz_log may itself not be installed yet, and _SRC (below) may not be
# resolved yet either (e.g. this is the very first log line of the run,
# before any tool has been processed) — that's the one spot with no real
# script to defer to, so it's the one spot with an actual (trivial,
# uncolored) fallback.
_zzu_log() {
    if command -v zz_log >/dev/null 2>&1; then
        zz_log "$@"
    else
        lvl="$1" && shift
        printf '[%s] %s\n' "$lvl" "$*" >&2
    fi
}

if [ $# -eq 0 ]; then
    _zzu_log e "Usage: zz_use <tool>[@ref] [tool[@ref]...]"
    exit 1
fi

# _SRC: the resolved tarball-context directory for _SRC_REF (set by
# _resolve_src). _SRC_RESOLVED guards against re-resolving the same ref
# more than once per run; a different ref requested later in the same run
# re-resolves (and switches _SRC to it).
_SRC=""
_SRC_REF=""
_SRC_RESOLVED=0

# Resolve _SRC for <ref> (default: main) — a local checkout (ROOT_DIR, when
# zz_use is running from within this repo and no specific ref was asked
# for), otherwise the local cache for that ref (refreshed first when
# missing or under --force) — then expose every zz_*/run.sh in it on PATH
# under its bare conventional name (zz_colors, zz_log, zz_bindir, ...) via
# symlinks in a scratch dir. That's what lets `command -v zz_bindir`,
# `zz_log ...`, and `. zz_colors` (including from *inside* zz_bindir's and
# zz_log's own source) all just resolve normally from here on, with zero
# reimplementation of what those scripts do.
_resolve_src() {
    _req_ref="${1:-}"
    if [ "$_SRC_RESOLVED" -eq 1 ] && [ "$_SRC_REF" = "$_req_ref" ]; then
        return 0
    fi

    if [ -z "$_req_ref" ] && ls -d "${ROOT_DIR}"/zz_*/ >/dev/null 2>&1 && [ -f "${ROOT_DIR}/zz_colors/run.sh" ]; then
        _SRC="$ROOT_DIR"
    else
        _cache_dir="${ZZ_CACHE_DIR}/${_req_ref:-main}"
        if [ "$FORCE" -eq 1 ] || [ ! -f "${_cache_dir}/zz_colors/run.sh" ]; then
            _refresh_cache "$_req_ref" "$_cache_dir" || return 1
        else
            _zzu_log - "Using cached repo scripts at {U ${_cache_dir}}"
        fi
        _SRC="$_cache_dir"
    fi

    _bootstrap_dir=$(mktemp -d)
    _add_tmp "$_bootstrap_dir"
    for _d in "${_SRC}"/zz_*/; do
        [ -f "${_d}run.sh" ] || continue
        ln -s "${_d}run.sh" "${_bootstrap_dir}/$(basename "$_d")"
    done
    export PATH="${_bootstrap_dir}:${PATH}"

    _SRC_REF="$_req_ref"
    _SRC_RESOLVED=1
}

# Refresh <cache_dir> from ZZ_USE_REPO_URL at <ref> (default: main).
# Extracts into a sibling temp dir first and swaps it in with `mv`, so a
# script currently running out of the old cache is never left reading a
# half-written directory.
_refresh_cache() {
    _req_ref="${1:-main}"
    _cache_dir="$2"
    _url=$(printf '%s' "$ZZ_USE_REPO_URL" | sed "s/{REF}/${_req_ref}/g")
    _zzu_log i "Retrieving repo scripts ({B ${_req_ref}}) from {U ${_url}}..."
    _tmp="${_cache_dir}.tmp.$$"
    _add_tmp "$_tmp"
    rm -rf "$_tmp"
    mkdir -p "$_tmp"
    curl -fsSL "$_url" | tar -xz -C "$_tmp" --strip-components=1
    [ -f "$_tmp/zz_colors/run.sh" ] || { _zzu_log e "Downloaded archive has no zz_* scripts (unexpected repo layout)"; return 1; }
    mkdir -p "$(dirname "$_cache_dir")"
    rm -rf "$_cache_dir"
    mv "$_tmp" "$_cache_dir"
}

# Resolve (and create if needed) a writable bin directory. Delegates to
# the real zz_bindir — resolving _SRC first (if it isn't already on PATH)
# makes that possible without reimplementing its candidate-directory logic
# here too.
_bindir() {
    _t="$1"
    command -v zz_bindir >/dev/null 2>&1 || _resolve_src || return 1
    eval "$(zz_bindir ${_t:+-t "$_t"})"
    printf '%s\n' "$dir"
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

# Install every zz_*/ folder's run.sh from _SRC at <ref> (default: main) at
# once, as a single bundle, linked onto the bin dir under its folder name
# (e.g. zz_log/run.sh -> <bindir>/zz_log).
_install_zz_bundle() {
    _ref="${1:-}"
    _resolve_src "$_ref" || return 1
    _dir=$(_bindir) || { _zzu_log e "No writable bin directory found for zz_* bundle install"; return 1; }
    _ensure_path "$_dir"

    _zzu_log i "Installing zz_* bundle from {U ${_SRC}} to {U ${_dir}}..."
    for _d in "${_SRC}"/zz_*/; do
        [ -f "${_d}run.sh" ] || continue
        _name=$(basename "$_d")
        # Write to a temp file and `mv` it into place rather than `cp`ing
        # over the target directly: one of these names can be zz_use
        # itself (e.g. under zz_update, which force-refreshes the whole
        # core set including zz_use), and an in-place cp can truncate a
        # script the shell is still mid-read on. mv (same filesystem) is
        # an atomic rename instead.
        cp "${_d}run.sh" "${_dir}/.${_name}.$$"
        chmod +x "${_dir}/.${_name}.$$"
        mv "${_dir}/.${_name}.$$" "${_dir}/${_name}"
    done
    _zzu_log s "zz_* bundle installed to {U ${_dir}}"
}

# Install a single named script from _SRC at <ref> (default: main) —
# functional or core, requested individually, unlike the core zz_* set
# which always installs as one bundle. Returns non-zero (silently) when
# <name> isn't a script in this repo at all, so the caller can fall
# through to the apt/config lookup for genuinely external tools.
_install_repo_script() {
    _name="$1"
    _ref="${2:-}"
    _resolve_src "$_ref" || return 1
    [ -f "${_SRC}/${_name}/run.sh" ] || return 1

    _dir=$(_bindir) || { _zzu_log e "No writable bin directory found for {Purple ${_name}}"; return 1; }
    _ensure_path "$_dir"

    _zzu_log i "Installing {Purple ${_name}} from {U ${_SRC}/${_name}} to {U ${_dir}}..."
    cp "${_SRC}/${_name}/run.sh" "${_dir}/.${_name}.$$"
    chmod +x "${_dir}/.${_name}.$$"
    mv "${_dir}/.${_name}.$$" "${_dir}/${_name}"
    _zzu_log s "Installed {Purple ${_name}} to {U ${_dir}/${_name}}"
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
    _add_tmp "$_tmp"

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
}

# The activator itself: resolve every requested tool, one at a time.
# "<tool>@<ref>" pins that one tool to a specific tag/branch/commit of this
# repo; ref is stripped from the name for command lookup/config/case
# matching and threaded through to the bundle/repo-script installers.
_use() {
    _zz_bundle_installed_for="__none__"

    for tool_ref in "$@"; do
        case "$tool_ref" in
        *@*)
            tool="${tool_ref%%@*}"
            ref="${tool_ref#*@}"
            ;;
        *)
            tool="$tool_ref"
            ref=""
            ;;
        esac

        # An unversioned request, not under --force (or --force on a
        # non-zz_ tool, which --force doesn't apply to), can be skipped if
        # already on PATH. A @<ref> request always (re)installs: there's
        # no way to tell from an installed script alone which ref it came
        # from, so "already available" can't be trusted to mean "at the
        # requested ref".
        if [ -z "$ref" ] && { [ "$FORCE" -eq 0 ] || [ "${tool#zz_}" = "$tool" ]; }; then
            if command -v "$tool" >/dev/null 2>&1; then
                _zzu_log - "{Purple $tool} already available"
                continue
            fi
        fi

        case "$tool" in
        zz_*)
            if [ "$_zz_bundle_installed_for" != "$ref" ]; then
                _install_zz_bundle "$ref"
                _zz_bundle_installed_for="$ref"
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
            elif _install_repo_script "$tool" "$ref"; then
                : # a functional (or core, requested by name) script from this repo
            else
                _apt_install "$tool" || true
            fi
            ;;
        esac

        if ! command -v "$tool" >/dev/null 2>&1; then
            _zzu_log e "Unable to provide required dependency: {Purple $tool}"
            return 1
        fi
    done
}

_use "$@"
