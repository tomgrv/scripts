#!/bin/sh
# zz_use — the activator: on-demand dependency management, triggering
# retrieval or install if and only if a command isn't already on PATH.
#
# Usage (each functional script calls this once, up front, for every
# dependency it needs — including the zz_* utility scripts it sources):
#   zz_use zz_log zz_args jq git
#
# Any tool name accepts an optional [org/repo/] prefix and/or @<ref>
# suffix, to pull it from a different GitHub repo and/or pin it to a
# specific tag, branch, or commit instead of this repo's own default
# (ZZ_ORIGIN, ZZ_ORIGIN_REF — see below):
#   zz_use validate-json@v2
#   zz_use someorg/otherscripts/some-tool@v1
# A pinned or other-origin request always (re)installs — the existing
# "already available" skip only applies to a plain, default-origin
# request, since there's no way to tell from an installed script alone
# which repo/ref produced it. Each origin+ref gets its own cache slot (see
# ZZ_CACHE_DIR below), so pinning one script doesn't disturb anything
# already resolved at the default.
#
# Two install paths:
#
#   - zz_* tools: all zz_* scripts in this repo are retrieved and installed
#     together, as a single bundle, via _bootstrap (below) — run
#     unconditionally, up front, at this script's own default origin/ref,
#     since zz_use needs its own zz_log/zz_colors/zz_bindir to report
#     anything at all. When not running from a local checkout, the bundle
#     is fetched once into a local cache directory (ZZ_CACHE_DIR/<ref>,
#     default ~/.cache/zz_scripts/main) and every subsequent bundle
#     install at that ref links from that cache — no repeat network
#     round-trip. Use `zz_update` (or `zz_use --force ...`) to force a
#     fresh download, bypassing the cache.
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
# ZZ_ORIGIN (org/repo) and ZZ_ORIGIN_REF (tag/branch/commit) are the
# default source for any tool name that doesn't specify its own — the
# same two variables setup.sh uses to pick what it bootstraps from, so a
# zz_use call defaults to wherever this install actually came from.
ZZ_ORIGIN="${ZZ_ORIGIN:-tomgrv/scripts}"
ZZ_ORIGIN_REF="${ZZ_ORIGIN_REF:-main}"
# {ORIGIN} and {REF} are substituted with the requested org/repo and
# tag/branch/commit — GitHub's archive endpoint accepts a tag, a branch,
# or a commit SHA interchangeably in the {REF} position.
#
# The default is built as a separate plain assignment, not inlined into
# ${ZZ_USE_REPO_URL:-...}: a literal "}" inside that expansion's default
# text (from "{REF}") terminates the expansion early at parse time,
# regardless of quoting — `${X:-a{REF}.b}` evaluates to `a{REF` with
# literal `.b}` appended after, not the intended default string.
_ZZ_USE_REPO_URL_DEFAULT='https://github.com/{ORIGIN}/archive/{REF}.tar.gz'
ZZ_USE_REPO_URL="${ZZ_USE_REPO_URL:-$_ZZ_USE_REPO_URL_DEFAULT}"
ZZ_CACHE_DIR="${ZZ_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/zz_scripts}"

# Every temp dir this script creates (a fresh cache download, a
# _download_install extraction, _bootstrap's own symlink dir) is cleaned
# up through this single mechanism instead of each having its own EXIT
# trap (which would just clobber each other).
_TMP_DIRS=""
_add_tmp() { _TMP_DIRS="${_TMP_DIRS} $1"; }
# Always returns 0: an EXIT trap's own exit status becomes the shell's
# final exit code when the script ends by falling off the end rather than
# an explicit `exit N` — without this, [ -n "$_TMP_DIRS" ] being false
# (nothing to clean up, the common case) would silently turn every
# otherwise-successful run into a reported failure.
_cleanup() {
    [ -n "$_TMP_DIRS" ] && rm -rf $_TMP_DIRS
    return 0
}
trap _cleanup EXIT

# _BOOTSTRAPPED: the "<origin>@<ref>" already resolved+installed by
# _bootstrap, so a repeat request for the same one (the common case) is an
# instant no-op instead of re-touching disk. A different one requested
# later in the same run re-resolves.
_BOOTSTRAPPED=""

# _bootstrap: the one function in charge of retrieving the zz_* scripts —
# resolving <origin>@<ref> (default: this script's own ZZ_ORIGIN/
# ZZ_ORIGIN_REF) to a local checkout, a warm cache, or a fresh download,
# then installing every zz_*/run.sh from it as a single bundle onto a
# writable bin dir. Called unconditionally, up front, at the default
# origin/ref, before anything else in this script runs — zz_use needs its
# own zz_log/zz_colors/zz_bindir to report anything at all — and again
# later for any pinned or other-origin zz_* request. Every other function
# in this script can therefore assume zz_log is already installed and call
# it directly; the one exception is the log line inside this function
# itself, before that installation has actually happened — that's the
# only spot with a trivial, uncolored fallback logger.
_bootstrap() {
    _origin="${1:-$ZZ_ORIGIN}"
    _ref="${2:-}"
    _key="${_origin}@${_ref}"
    [ "$FORCE" -eq 0 ] && [ "$_key" = "$_BOOTSTRAPPED" ] && return 0

    _blog() {
        command -v zz_log >/dev/null 2>&1 && { zz_log "$@"; return; }
        _lvl="$1" && shift
        [ "$_lvl" = "d" ] && [ -z "${ZZ_DEBUG:-}" ] && return 0
        printf '[%s] %s\n' "$_lvl" "$*" >&2
    }

    if [ "$_origin" = "$ZZ_ORIGIN" ] && [ -z "$_ref" ] && [ -f "${ROOT_DIR}/zz_colors/run.sh" ]; then
        _src="$ROOT_DIR"
    else
        _cache_dir="${ZZ_CACHE_DIR}/${_origin}/${_ref:-$ZZ_ORIGIN_REF}"
        _warm=0
        for _d in "$_cache_dir"/*/; do [ -f "${_d}run.sh" ] && _warm=1 && break; done
        if [ "$FORCE" -eq 1 ] || [ "$_warm" -eq 0 ]; then
            # "|" (not "/") as the sed delimiter: {ORIGIN} always contains
            # "/" (org/repo), and {REF} can too (a branch like
            # "feature/foo").
            _url=$(printf '%s' "$ZZ_USE_REPO_URL" | sed -e "s|{ORIGIN}|${_origin}|g" -e "s|{REF}|${_ref:-$ZZ_ORIGIN_REF}|g")
            _blog i "Retrieving repo scripts ({B ${_origin}@${_ref:-$ZZ_ORIGIN_REF}}) from {U ${_url}}..."
            _tmp="${_cache_dir}.tmp.$$"
            _add_tmp "$_tmp"
            rm -rf "$_tmp"
            mkdir -p "$_tmp"
            curl -fsSL "$_url" | tar -xz -C "$_tmp" --strip-components=1
            _ok=0
            for _d in "$_tmp"/*/; do [ -f "${_d}run.sh" ] && _ok=1 && break; done
            [ "$_ok" -eq 1 ] || { _blog e "Downloaded archive from {B ${_origin}@${_ref:-$ZZ_ORIGIN_REF}} has no <name>/run.sh scripts (unexpected repo layout)"; return 1; }
            mkdir -p "$(dirname "$_cache_dir")"
            rm -rf "$_cache_dir"
            mv "$_tmp" "$_cache_dir"
        else
            _blog d "Using cached repo scripts at {U ${_cache_dir}}"
        fi
        _src="$_cache_dir"
    fi

    # Expose every zz_*/run.sh from _src on PATH under its bare
    # conventional name (zz_colors, zz_log, zz_bindir, ...) via symlinks in
    # a scratch dir, so `command -v zz_bindir`, `zz_log ...` and
    # `. zz_colors` below — including from *inside* zz_bindir's/zz_log's
    # own source, which itself does `. zz_colors` — all just resolve.
    _boot_dir=$(mktemp -d)
    _add_tmp "$_boot_dir"
    for _d in "${_src}"/zz_*/; do
        [ -f "${_d}run.sh" ] || continue
        ln -s "${_d}run.sh" "${_boot_dir}/$(basename "$_d")"
    done
    export PATH="${_boot_dir}:${PATH}"

    _dir=$(_bindir) || { _blog e "No writable bin directory found for zz_* bundle install"; return 1; }
    _ensure_path "$_dir"

    _blog i "Installing zz_* bundle from {U ${_src}} to {U ${_dir}}..."
    for _d in "${_src}"/zz_*/; do
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
        _install_script_config "${_d}config" "${_dir}/config"
    done
    _blog s "zz_* bundle installed to {U ${_dir}}"

    _BOOTSTRAPPED="$_key"
    export _SRC="$_src"
}

# Resolve (and create if needed) a writable bin directory. Delegates to
# the real zz_bindir — bootstrapping the default zz_* set first if it
# isn't already on PATH, so this never has to reimplement zz_bindir's
# candidate-directory logic.
_bindir() {
    _t="$1"
    command -v zz_bindir >/dev/null 2>&1 || _bootstrap || return 1
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

# A handful of scripts (validate-json's "-l true"/"use script folder"
# fallback schema, in particular) resolve sibling data relative to their
# own installed location - a bare bindir/config/<file> next to the script,
# not the run.sh they were copied from. Since several scripts can each
# ship a config/ dir, merge them all into one shared bindir/config/
# instead of a single script "owning" it: copy in whatever isn't already
# there, never overwrite (first script installed wins on a name clash).
_install_script_config() {
    _cfg_src="$1" _cfg_dir="$2"
    [ -d "$_cfg_src" ] || return 0
    mkdir -p "$_cfg_dir"
    for _cfg_file in "$_cfg_src"/*; do
        [ -f "$_cfg_file" ] || continue
        _cfg_dest="$_cfg_dir/$(basename "$_cfg_file")"
        [ -e "$_cfg_dest" ] || cp "$_cfg_file" "$_cfg_dest"
    done
}

# Install a single named script from this or another repo — functional or
# core, requested individually, unlike the core zz_* set which always
# installs as one bundle via _bootstrap. Returns non-zero (silently) when
# <name> isn't a script in that repo at all, so the caller can fall
# through to the apt/config lookup for genuinely external tools.
_install_repo_script() {
    _name="$1"
    _origin="${2:-$ZZ_ORIGIN}"
    _ref="${3:-}"
    _bootstrap "$_origin" "$_ref" || return 1
    [ -f "${_SRC}/${_name}/run.sh" ] || return 1

    _dir=$(_bindir) || { zz_log e "No writable bin directory found for {Purple ${_name}}"; return 1; }
    _ensure_path "$_dir"

    zz_log i "Installing {Purple ${_name}} from {U ${_SRC}/${_name}} to {U ${_dir}}..."
    cp "${_SRC}/${_name}/run.sh" "${_dir}/.${_name}.$$"
    chmod +x "${_dir}/.${_name}.$$"
    mv "${_dir}/.${_name}.$$" "${_dir}/${_name}"
    _install_script_config "${_SRC}/${_name}/config" "${_dir}/config"
    zz_log s "Installed {Purple ${_name}} to {U ${_dir}/${_name}}"
}

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

# Expand {VERSION}/{OS}/{ARCH} in a zz_use.json url/binpath template ({OS}:
# uname -s, lowercased; {ARCH}: uname -m, mapped to amd64/arm64).
_expand() {
    _os=$(uname -s | tr '[:upper:]' '[:lower:]')
    case "$(uname -m)" in
    x86_64 | amd64) _arch=amd64 ;;
    aarch64 | arm64) _arch=arm64 ;;
    *) _arch=$(uname -m) ;;
    esac
    printf '%s' "$1" | sed \
        -e "s/{VERSION}/${2:-}/g" \
        -e "s/{OS}/${_os}/g" \
        -e "s/{ARCH}/${_arch}/g"
}

_download_install() {
    _tool="$1" _url_tpl="$2" _archive="$3" _binpath_tpl="$4" _version="$5"

    _url=$(_expand "$_url_tpl" "$_version")
    _binpath=$(_expand "${_binpath_tpl:-$_tool}" "$_version")

    zz_log i "Downloading {Purple $_tool} from {U $_url}..."
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

    [ -f "$_tmp/$_binpath" ] || { zz_log e "Downloaded archive for {Purple $_tool} has no {U $_binpath}"; return 1; }

    _dir=$(_bindir)
    _ensure_path "$_dir"
    chmod +x "$_tmp/$_binpath"
    cp "$_tmp/$_binpath" "$_dir/$_tool"
    zz_log s "Installed {Purple $_tool} to {U $_dir/$_tool}"
}

# The activator itself: resolve every requested tool, one at a time.
# "[org/repo/]<tool>[@ref]" pulls that one tool from a specific GitHub
# repo and/or pins it to a specific tag/branch/commit instead of this
# repo's own default (ZZ_ORIGIN/ZZ_ORIGIN_REF); the origin/ref are
# stripped from the name for command lookup/config/case matching and
# threaded through to _bootstrap/_install_repo_script. Recurses into
# itself once per concrete match of a glob tool name.
_use() {
    if [ $# -eq 0 ]; then
        zz_log e "Usage: zz_use <tool>[@ref] [tool[@ref]...]"
        return 1
    fi

    for tool_ref in "$@"; do
        case "$tool_ref" in
        *@*)
            _name_part="${tool_ref%%@*}"
            ref="${tool_ref#*@}"
            ;;
        *)
            _name_part="$tool_ref"
            ref=""
            ;;
        esac

        case "$_name_part" in
        */*/*)
            _rest="${_name_part#*/}"
            origin="${_name_part%%/*}/${_rest%%/*}"
            tool="${_rest#*/}"
            ;;
        *)
            origin="$ZZ_ORIGIN"
            tool="$_name_part"
            ;;
        esac

        # A glob tool name (e.g. "zz_*") expands to every matching script
        # folder in the resolved source tree instead of naming one script
        # directly. Bootstrap _SRC first so there's something to match
        # against, then recurse into _use once per concrete match, fully
        # reusing the per-tool logic below (skip-if-present, bundle vs.
        # individual install, error reporting) rather than duplicating it.
        # A glob matching nothing is a soft no-op (warn, don't fail) —
        # unlike a literal unknown tool name, which still errors via the
        # command -v check at the end of this loop.
        case "$tool" in
        *\**)
            # Resolved in a subshell: _bootstrap exports its bootstrap
            # symlink dir onto PATH as a side effect, which would make
            # every matched tool look "already available" to the
            # recursive _use calls below before any of them actually gets
            # installed to a persistent bin dir. Isolating that PATH
            # mutation to the subshell keeps the per-match recursion
            # honest; the disk-level effects (cache download/install)
            # still happen for real.
            _glob_src=$(_bootstrap "$origin" "$ref" 1>&2 && printf '%s' "$_SRC")
            [ -n "$_glob_src" ] || return 1
            _glob_matched=0
            for _gd in "${_glob_src}"/${tool}/; do
                [ -f "${_gd}run.sh" ] || continue
                _glob_matched=1
                _gname=$(basename "$_gd")
                if [ "$origin" = "$ZZ_ORIGIN" ]; then
                    _gexpanded="$_gname"
                else
                    _gexpanded="${origin}/${_gname}"
                fi
                [ -n "$ref" ] && _gexpanded="${_gexpanded}@${ref}"
                _use "$_gexpanded" || return 1
            done
            [ "$_glob_matched" -eq 1 ] || zz_log w "No scripts match {Purple ${tool}} in {U ${_glob_src}}"
            continue
            ;;
        esac

        # A plain, default-origin, unversioned request, not under --force
        # (or --force on a non-zz_ tool, which --force doesn't apply to),
        # can be skipped if already on PATH. A pinned ref and/or a
        # non-default origin always (re)installs: there's no way to tell
        # from an installed script alone which repo/ref produced it, so
        # "already available" can't be trusted to mean "the requested one".
        if [ -z "$ref" ] && [ "$origin" = "$ZZ_ORIGIN" ] && { [ "$FORCE" -eq 0 ] || [ "${tool#zz_}" = "$tool" ]; }; then
            if command -v "$tool" >/dev/null 2>&1; then
                zz_log d "{Purple $tool} already available"
                continue
            fi
        fi

        case "$tool" in
        zz_*)
            _bootstrap "$origin" "$ref" || return 1
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
                    _apt_install "$apt_pkg" || zz_log w "apt install of {Purple $apt_pkg} failed"
                elif [ -n "$url" ]; then
                    archive=$(printf '%s' "$entry" | jq -r '.archive // empty')
                    binpath=$(printf '%s' "$entry" | jq -r '.binpath // empty')
                    version=$(printf '%s' "$entry" | jq -r '.version // empty')
                    _download_install "$tool" "$url" "$archive" "$binpath" "$version" \
                        || zz_log w "Download install of {Purple $tool} failed"
                fi
            elif _install_repo_script "$tool" "$origin" "$ref"; then
                : # a functional (or core, requested by name) script from this or another repo
            else
                _apt_install "$tool" || true
            fi
            ;;
        esac

        if ! command -v "$tool" >/dev/null 2>&1; then
            zz_log e "Unable to provide required dependency: {Purple $tool}"
            return 1
        fi
    done
}

_bootstrap
_use "$@"
