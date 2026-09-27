#!/bin/sh
# zz_use — the activator: on-demand dependency management, installing a
# tool only if it isn't already on PATH.
#
# Usage: a functional script names only the tools it can't get any other
# way (an external tool like jq/curl, or a pinned/other-origin script);
# peerDependencies declared in its own package.json are installed
# automatically and recursively once the script itself installs (see
# _install_peer_deps) — a script with nothing beyond that needs no
# zz_use call at all.
#
# A tool name accepts an optional origin prefix ("whatever comes before
# <tool>'s own last /") and/or an @<ref> suffix to pin a version, instead
# of this repo's own default (ZZ_ORIGIN/ZZ_ORIGIN_REF):
#   zz_use validate-json@v2
#   zz_use someorg/otherscripts/some-tool@v1
#   zz_use ./some-dir/some-tool     # local path, relative to caller's cwd
#   zz_use $some-dir/some-tool      # relative to the git repo's top level
#   zz_use @myscope/pkg/some-tool   # scoped npm package
#   zz_use mypkg/some-tool          # unscoped npm package
# A pinned or non-default-origin request always (re)installs, since an
# already-installed script carries no record of which origin/ref produced
# it; each origin+ref gets its own cache slot (ZZ_CACHE_DIR) so pinning
# one script doesn't disturb anything already resolved at the default.
# A local ("./", "../", "/") or git-root ("$") origin is symlinked in
# place with no cache/download, so edits to a sibling checkout show up
# immediately.
#
# Resolution order for a single tool name (a glob like "zz_*" expands to
# every match in the source tree first — how setup.sh installs the whole
# core set in one call):
#   1. A script from this repo — from a local checkout when running from
#      one, otherwise the local cache (ZZ_CACHE_DIR/<origin>/<ref>,
#      default ~/.cache/zz_scripts). `zz_update`/`--force` bypasses the
#      cache.
#   2. Otherwise config/zz_use.json (ZZ_USE_CONFIG to override):
#        {"apt": "<pkg>"} -> apt-get install
#        {"url": "...", "archive": ..., "binpath": "..."} -> download,
#        extract, install the binary. Templates support {VERSION}, {OS},
#        {ARCH}.
#   3. Fall back to `apt-get install -y <tool>`.
# Still not on PATH afterwards -> error, exit 1.
#
# Idempotent: resolved tools are skipped in ~0ms via `command -v`, unless
# --force or @<ref> is given.
#
# -x/--exec <tool> [arg...]: install <tool> and exec straight into it,
# replacing this process, with everything after <tool> as its argv. Tool
# names given before -x are resolved first as ordinary dependencies.
#
# zz_use relies on zz_log (and its siblings) already being on PATH —
# setup.sh's `zz_use "zz_*"` call puts the whole core set there first.

set -e

# One left-to-right scan for every option (--force/-f, -x/--exec), so
# --force is recognized anywhere, not just as literal $1. Errors here use
# plain stderr, not zz_log: this runs before any tool, zz_log included,
# is resolved. Non-option args are single-quoted into _before (restored
# via `eval set --` further down). Everything from -x's <tool> onward is
# left untouched in "$@", to become the exec'd tool's own argv.
FORCE=0
EXEC_TOOL=""
_before=""

while [ $# -gt 0 ]; do
    case "$1" in
    --force | -f)
        FORCE=1
        shift
        ;;
    -x | --exec)
        shift
        EXEC_TOOL="${1:-}"
        if [ -z "$EXEC_TOOL" ]; then
            printf '[e] -x/--exec requires a tool name\n' >&2
            exit 1
        fi
        shift
        break
        ;;
    -*)
        printf '[e] Unknown option: %s\n' "$1" >&2
        exit 1
        ;;
    *)
        _before="${_before} '$(printf '%s' "$1" | sed "s/'/'\\\\''/g")'"
        shift
        ;;
    esac
done

# Follow symlinks (an installed "zz_use" on PATH is a symlink to this
# file) so SCRIPT_DIR/ROOT_DIR resolve to the real checkout.
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

ZZ_USE_CONFIG="${ZZ_USE_CONFIG:-${SCRIPT_DIR}/config/zz_use.json}"
# Default source for any tool name that doesn't specify its own origin —
# the same variables setup.sh uses to bootstrap, so zz_use defaults to
# wherever this install came from.
ZZ_ORIGIN="${ZZ_ORIGIN:-tomgrv/scripts}"
ZZ_ORIGIN_REF="${ZZ_ORIGIN_REF:-main}"
# Built as a separate assignment, not inlined into ${ZZ_USE_REPO_URL:-...}:
# a literal "}" in the default text (from "{REF}") would terminate that
# expansion early at parse time regardless of quoting.
_ZZ_USE_REPO_URL_DEFAULT='https://github.com/{ORIGIN}/archive/{REF}.tar.gz'
ZZ_USE_REPO_URL="${ZZ_USE_REPO_URL:-$_ZZ_USE_REPO_URL_DEFAULT}"
ZZ_CACHE_DIR="${ZZ_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/zz_scripts}"

# Every temp dir this script creates is cleaned up through this single
# mechanism instead of each having its own EXIT trap (which would clobber
# each other).
_TMP_DIRS=""
_add_tmp() { _TMP_DIRS="${_TMP_DIRS} $1"; }
# Always returns 0, so an empty $_TMP_DIRS (nothing to clean up) doesn't
# turn an otherwise-successful run into a reported failure.
_cleanup() {
    [ -n "$_TMP_DIRS" ] && rm -rf $_TMP_DIRS
    return 0
}
trap _cleanup EXIT

# _SRC: the resolved source tree for _SRC_ORIGIN/_SRC_REF (set by
# _resolve_src). _SRC_RESOLVED guards against re-resolving the same
# origin+ref more than once per run, even under --force (which only
# needs one fresh download per origin+ref, not one per tool requested at
# it). A different origin+ref requested later in the run re-resolves.
_SRC=""
_SRC_ORIGIN=""
_SRC_REF=""
_SRC_RESOLVED=0

# True if <cache_dir> already holds a fetched, well-formed archive (a
# <name>/run.sh directly under it) — shared warm-cache test for every
# origin that downloads and caches.
_cache_warm() {
    for _cw_d in "$1"/*/; do [ -f "${_cw_d}run.sh" ] && return 0; done
    return 1
}

# Fetch <url> (a tar.gz archive whose single top-level dir is stripped)
# into <cache_dir> unless already warm (or --force), verifying it has
# <name>/run.sh scripts before replacing any existing cache. Shared by
# every origin below. Sets _SRC on success; <url> may be empty when
# already warm.
_fetch_archive() {
    _cache_dir="$1" _url="$2" _desc="$3"
    if [ "$FORCE" -eq 1 ] || ! _cache_warm "$_cache_dir"; then
        zz_log i "Retrieving ${_desc} from {U ${_url}}..."
        _tmp="${_cache_dir}.tmp.$$"
        _add_tmp "$_tmp"
        rm -rf "$_tmp"
        mkdir -p "$_tmp"
        curl -fsSL "$_url" | tar -xz -C "$_tmp" --strip-components=1
        _cache_warm "$_tmp" || { zz_log e "Downloaded archive for ${_desc} has no <name>/run.sh scripts (unexpected repo layout)"; return 1; }
        mkdir -p "$(dirname "$_cache_dir")"
        rm -rf "$_cache_dir"
        mv "$_tmp" "$_cache_dir"
    else
        zz_log d "Using cached ${_desc} at {U ${_cache_dir}}"
    fi
    _SRC="$_cache_dir"
}

# Fetch (or reuse the cache for) an npm-registry origin, scoped
# ("@scope/pkg") or unscoped ("pkg") alike. <ref> is a dist-tag or exact
# version (default "latest"). Cached under its own origin+ref slot like a
# GitHub archive (_fetch_archive above), just fetched from the npm
# registry's tarball. Sets _SRC on success.
_resolve_npm() {
    command -v jq >/dev/null 2>&1 || { printf '[e] npm origin %s requires jq on PATH\n' "$_req_origin" >&2; return 1; }
    _npm_ref="${_req_ref:-latest}"
    _cache_dir="${ZZ_CACHE_DIR}/${_req_origin}/${_npm_ref}"
    _tarball=""
    if [ "$FORCE" -eq 1 ] || ! _cache_warm "$_cache_dir"; then
        _npm_origin_enc=$(printf '%s' "$_req_origin" | sed 's#/#%2f#g')
        _meta_url="https://registry.npmjs.org/${_npm_origin_enc}/${_npm_ref}"
        _tarball=$(curl -fsSL "$_meta_url" | jq -r '.dist.tarball // empty')
        [ -n "$_tarball" ] || { zz_log e "Could not resolve npm tarball for {Purple ${_req_origin}@${_npm_ref}} from {U ${_meta_url}}"; return 1; }
    fi
    _fetch_archive "$_cache_dir" "$_tarball" "npm package ({B ${_req_origin}@${_npm_ref}})"
}

# Resolve _SRC for <origin> (default ZZ_ORIGIN) at <ref> (default
# ZZ_ORIGIN_REF): a local checkout (ROOT_DIR) when running from within
# this repo at the default origin/ref, otherwise the local cache for
# that origin+ref (refreshed first when missing or under --force). Then
# exposes every zz_*/run.sh in it on PATH under its bare name (zz_colors,
# zz_log, ...) via symlinks in a scratch dir, so `zz_log ...` and
# `. zz_colors` resolve normally from here on.
_resolve_src() {
    _req_origin="${1:-$ZZ_ORIGIN}"
    _req_ref="${2:-}"
    if [ "$_SRC_RESOLVED" -eq 1 ] && [ "$_SRC_ORIGIN" = "$_req_origin" ] && [ "$_SRC_REF" = "$_req_ref" ]; then
        return 0
    fi

    if [ "$_req_origin" = "$ZZ_ORIGIN" ] && [ -z "$_req_ref" ] && [ -f "${ROOT_DIR}/zz_colors/run.sh" ]; then
        _SRC="$ROOT_DIR"
    else
        case "$_req_origin" in
        . | .. | ./* | ../* | /*)
            # Local-path scheme: resolved relative to the caller's cwd (or
            # absolute), no cache/download — picks up a sibling checkout
            # as-is via symlink. Plain stderr, not zz_log: this can be the
            # very first thing zz_use resolves, before zz_log is on PATH.
            _SRC=$(cd "$_req_origin" 2>/dev/null && pwd) || { printf '[e] Local repo path %s not found\n' "$_req_origin" >&2; return 1; }
            ;;
        '$'*)
            # Git-root scheme ("$" or "$<subpath>"): same no-cache handling
            # as a local path, anchored at the repo root instead of cwd.
            _git_root=$(git rev-parse --show-toplevel 2>/dev/null) || { printf '[e] %s: not inside a git repository\n' "$_req_origin" >&2; return 1; }
            _sub="${_req_origin#\$}"
            case "$_sub" in /*) _sub="${_sub#/}" ;; esac
            if [ -z "$_sub" ]; then
                _SRC="$_git_root"
            else
                _SRC=$(cd "${_git_root}/${_sub}" 2>/dev/null && pwd) || { printf '[e] Git-root path %s not found (root: %s)\n' "$_req_origin" "$_git_root" >&2; return 1; }
            fi
            ;;
        @*)
            # npm scheme, scoped package (e.g. "@myscope/pkg").
            _resolve_npm || return 1
            ;;
        */*)
            # GitHub-archive scheme: "org/repo" — always has a "/", unlike
            # an unscoped npm name (caught by the "*)" arm below).
            _cache_dir="${ZZ_CACHE_DIR}/${_req_origin}/${_req_ref:-$ZZ_ORIGIN_REF}"
            _url=""
            if [ "$FORCE" -eq 1 ] || ! _cache_warm "$_cache_dir"; then
                # "|" (not "/") as the sed delimiter: {ORIGIN} and {REF}
                # can themselves contain "/" (org/repo, or a branch name
                # like "feature/foo"), which would break s///.
                _url=$(printf '%s' "$ZZ_USE_REPO_URL" | sed -e "s|{ORIGIN}|${_req_origin}|g" -e "s|{REF}|${_req_ref:-$ZZ_ORIGIN_REF}|g")
            fi
            _fetch_archive "$_cache_dir" "$_url" "repo scripts ({B ${_req_origin}@${_req_ref:-$ZZ_ORIGIN_REF}})" || return 1
            ;;
        *)
            # npm scheme, unscoped package (e.g. "mypkg") — no "/" at all.
            _resolve_npm || return 1
            ;;
        esac
    fi

    _boot_dir=$(mktemp -d)
    _add_tmp "$_boot_dir"
    for _d in "${_SRC}"/zz_*/; do
        [ -f "${_d}run.sh" ] || continue
        ln -s "${_d}run.sh" "${_boot_dir}/$(basename "$_d")"
    done
    export PATH="${_boot_dir}:${PATH}"

    _SRC_ORIGIN="$_req_origin"
    _SRC_REF="$_req_ref"
    _SRC_RESOLVED=1
}

# Resolve (and create if needed) a writable bin directory. Delegates to
# the real zz_bindir, resolving _SRC first if it isn't already on PATH.
_bindir() {
    _t="$1"
    command -v zz_bindir >/dev/null 2>&1 || _resolve_src || return 1
    eval "$(zz_bindir ${_t:+-t "$_t"})"
    printf '%s\n' "$dir"
}

# _bindir runs inside a subshell whenever captured via $(...), so its PATH
# extension never reaches this script's own environment — re-apply it
# here so a tool installed just now is found by later `command -v` checks.
_ensure_path() {
    case ":$PATH:" in
    *":$1:"*) ;;
    *) export PATH="$1:$PATH" ;;
    esac
}

# Some scripts (validate-json's "-l true" fallback schema, in particular)
# resolve sibling data relative to their installed location, not their
# source run.sh. Since several scripts can ship a config/ dir, merge them
# all into one shared bindir/config/: copy in whatever isn't already
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

# Install every dependency <name> declares in its own package.json's
# peerDependencies — sibling repo scripts and external tools alike,
# recursively, through the ordinary _use resolution path. Runs against
# the *source* package.json in _SRC, before install.
#
# _PEER_SEEN guards against reprocessing the same dependency twice (two
# siblings sharing one, or a glob install) and against a cycle recursing
# forever, since the dependency causing the cycle isn't on PATH yet for
# _use's own "already available" skip to catch.
_PEER_SEEN=""
_install_peer_deps() {
    _peer_json="${_SRC}/$1/package.json"
    [ -f "$_peer_json" ] || return 0
    if command -v jq >/dev/null 2>&1; then
        _peers=$(jq -r '.peerDependencies // {} | keys[]' "$_peer_json")
    else
        _peers=$(sed -n '/"peerDependencies"[[:space:]]*:/,/}/p' "$_peer_json" | grep -o '"[^"]*"[[:space:]]*:' | sed -e 's/"[[:space:]]*:$//' -e 's/^"//' | grep -v '^peerDependencies$')
    fi
    for _peer in $_peers; do
        case "$_peer" in
        "@tomgrv/scripts-"*) _peer="${_peer#@tomgrv/scripts-}" ;;
        esac
        case " $_PEER_SEEN " in
        *" $_peer "*) continue ;;
        esac
        _PEER_SEEN="${_PEER_SEEN} ${_peer}"
        _use "$_peer" || return 1
    done
}

# Install a single named script from this or another repo. Returns
# non-zero (silently) when <name> isn't a script in that repo at all, so
# the caller can fall through to the apt/config lookup for external tools.
_install_repo_script() {
    _name="$1"
    _origin="${2:-$ZZ_ORIGIN}"
    _ref="${3:-}"
    _resolve_src "$_origin" "$_ref" || return 1
    [ -f "${_SRC}/${_name}/run.sh" ] || return 1

    _dir=$(_bindir) || { zz_log e "No writable bin directory found for {Purple ${_name}}"; return 1; }
    _ensure_path "$_dir"

    zz_log i "Installing {Purple ${_name}} from {U ${_SRC}/${_name}} to {U ${_dir}}..."
    # Write to a temp file and `mv` into place rather than `cp` over the
    # target directly: <_name> can be zz_use itself (e.g. under
    # zz_update), and an in-place cp can truncate a script the shell is
    # still mid-read on. mv (same filesystem) is an atomic rename instead.
    cp "${_SRC}/${_name}/run.sh" "${_dir}/.${_name}.$$"
    chmod +x "${_dir}/.${_name}.$$"
    mv "${_dir}/.${_name}.$$" "${_dir}/${_name}"
    _install_script_config "${_SRC}/${_name}/config" "${_dir}/config"
    zz_log s "Installed {Purple ${_name}} to {U ${_dir}/${_name}}"
    _install_peer_deps "$_name" || return 1
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
# "[org/repo/]<tool>[@ref]" pulls that tool from a specific repo and/or
# pins it to a tag/branch/commit instead of ZZ_ORIGIN/ZZ_ORIGIN_REF.
_use() {
    if [ $# -eq 0 ]; then
        # Plain stderr, not zz_log: this can run before zz_log itself has
        # been resolved.
        printf '[e] Usage: zz_use <tool>[@ref] [tool[@ref]...]\n' >&2
        return 1
    fi

    for tool_ref in "$@"; do
        # This repo's own packages are named "@tomgrv/scripts-<tool>", so
        # unwrap that scoped-npm shape back to the plain name up front, or
        # it'd be mistaken for an actual npm-registry package by the "@*"
        # arm below.
        case "$tool_ref" in
        "@tomgrv/scripts-"*) tool_ref="${tool_ref#@tomgrv/scripts-}" ;;
        esac

        # A leading "@" is the npm scheme sigil (e.g. "@myscope/pkg"), not
        # the "@ref" pin suffix — stripped and re-prepended around the
        # *@* split below so e.g. "@myscope/pkg/tool@1.2.3" still pins to
        # "1.2.3" instead of splitting on the scope's own "@".
        case "$tool_ref" in
        @*)
            _at_sigil="@"
            _rest_ref="${tool_ref#@}"
            ;;
        *)
            _at_sigil=""
            _rest_ref="$tool_ref"
            ;;
        esac
        case "$_rest_ref" in
        *@*)
            _name_part="${_at_sigil}${_rest_ref%%@*}"
            ref="${_rest_ref#*@}"
            ;;
        *)
            _name_part="${_at_sigil}${_rest_ref}"
            ref=""
            ;;
        esac

        # The origin prefix is everything before <tool>'s own last "/" —
        # one rule for every scheme. A tool name with no "/" at all
        # defaults to ZZ_ORIGIN.
        case "$_name_part" in
        */*)
            origin="${_name_part%/*}"
            tool="${_name_part##*/}"
            ;;
        *)
            origin="$ZZ_ORIGIN"
            tool="$_name_part"
            ;;
        esac

        # A glob tool name (e.g. "zz_*") expands to every matching script
        # folder in the source tree. Each match installs unconditionally:
        # _resolve_src's own symlink step puts every zz_* name on PATH as
        # a side effect, so the "already available" skip below can't be
        # trusted here. A glob matching nothing warns rather than failing.
        case "$tool" in
        *\**)
            _resolve_src "$origin" "$ref" || return 1
            _glob_matched=0
            for _gd in "${_SRC}"/${tool}/; do
                [ -f "${_gd}run.sh" ] || continue
                _glob_matched=1
                _install_repo_script "$(basename "$_gd")" "$origin" "$ref" || return 1
            done
            [ "$_glob_matched" -eq 1 ] || zz_log w "No scripts match {Purple ${tool}} in {U ${_SRC}}"
            continue
            ;;
        esac

        # A plain, default-origin, unversioned request (or --force on a
        # non-zz_ tool, which --force doesn't apply to) can be skipped if
        # already on PATH. A pinned ref or non-default origin always
        # (re)installs, since an installed script carries no record of
        # which repo/ref produced it.
        if [ -z "$ref" ] && [ "$origin" = "$ZZ_ORIGIN" ] && { [ "$FORCE" -eq 0 ] || [ "${tool#zz_}" = "$tool" ]; }; then
            if command -v "$tool" >/dev/null 2>&1; then
                zz_log d "{Purple $tool} already available"
                continue
            fi
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
        elif _install_repo_script "$tool" "$origin" "$ref"; then
            :
        else
            _apt_install "$tool" || true
        fi

        if ! command -v "$tool" >/dev/null 2>&1; then
            zz_log e "Unable to provide required dependency: {Purple $tool}"
            return 1
        fi
    done
}

# -x/--exec: install EXEC_TOOL alongside the dependencies collected into
# _before, then exec into it, remaining "$@" becoming its argv. Falls
# through to the plain _use call below when -x wasn't given.
if [ -n "$EXEC_TOOL" ]; then
    eval "_use $_before \"\$EXEC_TOOL\"" || exit 1
    # Same leading-"@" vs trailing-"@ref" split as in _use: an npm-origin
    # exec target (e.g. "@myscope/pkg/tool@1.2.3") must not have its
    # command name mangled by splitting on the scope's own "@".
    case "$EXEC_TOOL" in
    @*)
        _exec_rest="${EXEC_TOOL#@}"
        case "$_exec_rest" in *@*) _exec_rest="${_exec_rest%%@*}" ;; esac
        _exec_name="@${_exec_rest}"
        ;;
    *)
        _exec_name="${EXEC_TOOL%%@*}"
        ;;
    esac
    case "$_exec_name" in */*) _exec_name="${_exec_name##*/}" ;; esac
    exec "$_exec_name" "$@"
fi

eval "_use $_before"
