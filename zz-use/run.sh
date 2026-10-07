#!/bin/sh
# zz-use — the activator: on-demand dependency management, installing a
# tool only if it isn't already on PATH.
#
# Usage: a functional script names only the tools it can't get any other
# way (an external tool like jq/curl, or a pinned/other-origin script);
# peerDependencies declared in its own package.json are installed
# automatically and recursively once the script itself installs (see
# _install_peer_deps) — a script with nothing beyond that needs no
# zz-use call at all.
#
# A tool name accepts an optional origin prefix ("whatever comes before
# <tool>'s own last /") and/or an @<ref> suffix to pin a version, instead
# of this repo's own default (ZZ_ORIGIN/ZZ_ORIGIN_REF):
#   zz-use json-validate@v2
#   zz-use someorg/otherscripts/some-tool@v1
#   zz-use ./some-dir/some-tool     # local path, relative to caller's cwd
#   zz-use $some-dir/some-tool      # relative to the git repo's top level
#   zz-use @myscope/pkg/some-tool   # scoped npm package
#   zz-use mypkg/some-tool          # unscoped npm package
# A pinned or non-default-origin request always (re)installs, since an
# already-installed script carries no record of which origin/ref produced
# it; each origin+ref gets its own cache slot (ZZ_CACHE_DIR) so pinning
# one script doesn't disturb anything already resolved at the default.
# A local ("./", "../", "/") or git-root ("$") origin is symlinked in
# place with no cache/download, so edits to a sibling checkout show up
# immediately.
#
# Resolution order for a single tool name (a glob like "zz-*" expands to
# every match in the source tree first — how setup.sh installs the whole
# core set in one call):
#   1. A script from this repo — from a local checkout when running from
#      one, otherwise the local cache (ZZ_CACHE_DIR/<origin>/<ref>,
#      default ~/.cache/zz_scripts). `zz-update`/`--force` bypasses the
#      cache.
#   2. Otherwise config/zz-use.json (ZZ_USE_CONFIG to override):
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
# zz-use relies on zz-log (and its siblings) already being on PATH —
# setup.sh's `zz-use "zz-*"` call puts the whole core set there first.

set -e

# One left-to-right scan for every option (--force/-f, -x/--exec), so
# --force is recognized anywhere, not just as literal $1. Errors here use
# plain stderr, not zz-log: this runs before any tool, zz-log included,
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

# Follow symlinks (an installed "zz-use" on PATH is a symlink to this
# file) so SCRIPT_DIR/ROOT_DIR resolve to the real checkout.
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

ZZ_USE_CONFIG="${ZZ_USE_CONFIG:-${SCRIPT_DIR}/config/zz-use.json}"
# Default source for any tool name that doesn't specify its own origin —
# the same variables setup.sh uses to bootstrap, so zz-use defaults to
# wherever this install came from.
ZZ_ORIGIN="${ZZ_ORIGIN:-tomgrv/scripts}"
ZZ_ORIGIN_REF="${ZZ_ORIGIN_REF:-main}"
# Built as a separate assignment, not inlined into ${ZZ_USE_REPO_URL:-...}:
# a literal "}" in the default text (from "{REF}") would terminate that
# expansion early at parse time regardless of quoting.
_ZZ_USE_REPO_URL_DEFAULT='https://github.com/{ORIGIN}/archive/{REF}.tar.gz'
ZZ_USE_REPO_URL="${ZZ_USE_REPO_URL:-$_ZZ_USE_REPO_URL_DEFAULT}"
ZZ_CACHE_DIR="${ZZ_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/zz_scripts}"
# Minutes before a cached archive for a mutable ref (a branch like "main",
# or npm's "latest") is refetched; 0 = never expire. Immutable refs (a
# version tag or commit sha) never expire.
ZZ_CACHE_TTL="${ZZ_CACHE_TTL:-1440}"

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

# _SRC: the resolved source tree of the origin+ref last passed to
# _resolve_src. _SRC_MAP remembers every origin+ref already resolved this
# run ("<origin>@<ref>|<dir>" lines), so switching back and forth between
# origins (a pinned script whose peers live at the default origin, say)
# neither re-downloads under --force nor stacks another boot dir on PATH.
# _BOOT_DIRS lists those scratch boot dirs, whose zz-* symlinks must never
# count as "installed" (they vanish when this process exits).
_SRC=""
_SRC_MAP=""
_BOOT_DIRS=""

# POSIX sh has no `local`: every variable below is global, and _use
# recurses (through _install_peer_deps). Callers therefore never read one
# of _use's own variables back after a call that may recurse into it.

# True if <tool> is on PATH outside the scratch boot dirs — i.e. actually
# installed, not merely exposed for the lifetime of this process. Sets
# _HAVE_PATH to where it was found.
_HAVE_PATH=""
_have() {
    _h_old_ifs=$IFS
    IFS=':'
    for _h_d in $PATH; do
        [ -n "$_h_d" ] || continue
        case " $_BOOT_DIRS " in *" $_h_d "*) continue ;; esac
        if [ -f "$_h_d/$1" ] && [ -x "$_h_d/$1" ]; then
            IFS=$_h_old_ifs
            _HAVE_PATH="$_h_d/$1"
            return 0
        fi
    done
    IFS=$_h_old_ifs
    return 1
}

# Run a command as root: directly, through sudo, or fail.
_as_root() {
    if [ "$(id -u)" = "0" ]; then
        "$@"
    elif command -v sudo >/dev/null 2>&1; then
        sudo "$@"
    else
        zz-log e "{Purple $1} requires root/sudo, neither available"
        return 1
    fi
}

# Install a system package with whichever package manager exists. The
# apt index is refreshed at most once per run.
_APT_UPDATED=0
_pkg_install() {
    _pkg="$1"
    if command -v apt-get >/dev/null 2>&1; then
        zz-log i "Installing {Purple $_pkg} via apt-get..."
        if [ "$_APT_UPDATED" -eq 0 ]; then
            _as_root apt-get update -qq || return 1
            _APT_UPDATED=1
        fi
        _as_root apt-get install -y -qq "$_pkg"
    elif command -v apk >/dev/null 2>&1; then
        zz-log i "Installing {Purple $_pkg} via apk..."
        _as_root apk add --no-cache -q "$_pkg"
    elif command -v dnf >/dev/null 2>&1; then
        zz-log i "Installing {Purple $_pkg} via dnf..."
        _as_root dnf install -y -q "$_pkg"
    elif command -v brew >/dev/null 2>&1; then
        zz-log i "Installing {Purple $_pkg} via brew..."
        brew install -q "$_pkg"
    else
        return 1
    fi
}

# jq is needed to read zz-use.json and npm registry metadata: install it
# straight through the package manager (never through _use, which would
# clobber the caller's variables) when it's missing.
_ensure_jq() {
    command -v jq >/dev/null 2>&1 && return 0
    _pkg_install jq >/dev/null 2>&1 || true
    command -v jq >/dev/null 2>&1
}

# Verify <file> against an expected sha256 (no-op when none is given).
_verify_sha256() {
    _vs_file="$1" _vs_sum="$2"
    [ -n "$_vs_sum" ] || return 0
    if command -v sha256sum >/dev/null 2>&1; then
        _vs_got=$(sha256sum "$_vs_file" | cut -d' ' -f1)
    elif command -v shasum >/dev/null 2>&1; then
        _vs_got=$(shasum -a 256 "$_vs_file" | cut -d' ' -f1)
    else
        zz-log e "No sha256sum/shasum available to verify {U $_vs_file}"
        return 1
    fi
    [ "$_vs_got" = "$_vs_sum" ] || {
        zz-log e "Checksum mismatch for {U $_vs_file}: expected $_vs_sum, got $_vs_got"
        return 1
    }
}

# True if <ref> names something that never moves: a version tag
# (v1.2.3 / 1.2.3) or a commit sha.
_ref_immutable() {
    case "$1" in
    v[0-9]* | [0-9]*.[0-9]*) return 0 ;;
    esac
    printf '%s' "$1" | grep -Eq '^[0-9a-f]{7,40}$'
}

# True if <cache_dir> already holds a fetched, well-formed archive (a
# <name>/run.sh directly under it) — shared warm-cache test for every
# origin that downloads and caches.
_cache_warm() {
    for _cw_d in "$1"/*/; do [ -f "${_cw_d}run.sh" ] && return 0; done
    return 1
}

# True if <cache_dir> is warm and, for a mutable <ref>, younger than
# ZZ_CACHE_TTL minutes.
_cache_fresh() {
    _cache_warm "$1" || return 1
    [ "$ZZ_CACHE_TTL" -eq 0 ] && return 0
    _ref_immutable "$2" && return 0
    [ -n "$(find "$1" -maxdepth 0 -mmin "-${ZZ_CACHE_TTL}" 2>/dev/null)" ]
}

# Fetch <url> (a tar.gz archive whose single top-level dir is stripped)
# into <cache_dir> unless fresh (or --force), verifying it has
# <name>/run.sh scripts before replacing any existing cache. Downloads to
# a file first (sh has no pipefail, so `curl | tar` would hide a curl
# failure). A failed refresh falls back to a stale-but-warm cache. Sets
# _SRC on success; <url> may be empty when fresh.
_fetch_archive() {
    _cache_dir="$1" _url="$2" _desc="$3"
    if [ -n "$_url" ]; then
        zz-log i "Retrieving ${_desc} from {U ${_url}}..."
        _tmp="${_cache_dir}.tmp.$$"
        _add_tmp "$_tmp"
        rm -rf "$_tmp"
        mkdir -p "$_tmp/x"
        if curl -fsSL "$_url" -o "$_tmp/a.tar.gz" \
            && tar -xzf "$_tmp/a.tar.gz" -C "$_tmp/x" --strip-components=1 \
            && _cache_warm "$_tmp/x"; then
            mkdir -p "$(dirname "$_cache_dir")"
            rm -rf "$_cache_dir"
            mv "$_tmp/x" "$_cache_dir"
        elif _cache_warm "$_cache_dir"; then
            zz-log w "Could not refresh ${_desc}; using stale cache at {U ${_cache_dir}}"
        else
            zz-log e "Could not retrieve ${_desc} (download failed or no <name>/run.sh scripts)"
            return 1
        fi
    else
        zz-log d "Using cached ${_desc} at {U ${_cache_dir}}"
    fi
    _SRC="$_cache_dir"
}

# Fetch (or reuse the cache for) an npm-registry origin, scoped
# ("@scope/pkg") or unscoped ("pkg") alike. <ref> is a dist-tag or exact
# version (default "latest"). Cached under its own origin+ref slot like a
# GitHub archive (_fetch_archive above), just fetched from the npm
# registry's tarball. Sets _SRC on success.
_resolve_npm() {
    _ensure_jq || { printf '[e] npm origin %s requires jq on PATH\n' "$_req_origin" >&2; return 1; }
    _npm_ref="${_req_ref:-latest}"
    _cache_dir="${ZZ_CACHE_DIR}/${_req_origin}/${_npm_ref}"
    _tarball=""
    if [ "$FORCE" -eq 1 ] || ! _cache_fresh "$_cache_dir" "$_npm_ref"; then
        _npm_origin_enc=$(printf '%s' "$_req_origin" | sed 's#/#%2f#g')
        _meta_url="https://registry.npmjs.org/${_npm_origin_enc}/${_npm_ref}"
        _tarball=$(curl -fsSL "$_meta_url" 2>/dev/null | jq -r '.dist.tarball // empty' 2>/dev/null) || _tarball=""
        if [ -z "$_tarball" ]; then
            _cache_warm "$_cache_dir" || { zz-log e "Could not resolve npm tarball for {Purple ${_req_origin}@${_npm_ref}} from {U ${_meta_url}}"; return 1; }
            zz-log w "Could not refresh {Purple ${_req_origin}@${_npm_ref}}; using stale cache"
        fi
    fi
    _fetch_archive "$_cache_dir" "$_tarball" "npm package ({B ${_req_origin}@${_npm_ref}})"
}

# Resolve _SRC for <origin> (default ZZ_ORIGIN) at <ref> (default
# ZZ_ORIGIN_REF): a local checkout (ROOT_DIR) when running from within
# this repo at the default origin/ref, otherwise the local cache for
# that origin+ref (refreshed first when missing, expired or under
# --force). Then exposes every zz-*/run.sh in it on PATH under its bare
# name (zz-colors, zz-log, ...) via symlinks in a scratch dir, so
# `zz-log ...` and `. zz-colors` resolve normally from here on. Each
# origin+ref is resolved at most once per run (_SRC_MAP).
_resolve_src() {
    _req_origin="${1:-$ZZ_ORIGIN}"
    _req_ref="${2:-}"
    _src_key="${_req_origin}@${_req_ref}"
    _src_hit=$(printf '%s\n' "$_SRC_MAP" | awk -F'|' -v k="$_src_key" '$1 == k { print $2; exit }')
    if [ -n "$_src_hit" ]; then
        _SRC="$_src_hit"
        return 0
    fi

    if [ "$_req_origin" = "$ZZ_ORIGIN" ] && [ -z "$_req_ref" ] && [ -f "${ROOT_DIR}/zz-colors/run.sh" ]; then
        _SRC="$ROOT_DIR"
    else
        case "$_req_origin" in
        . | .. | ./* | ../* | /*)
            # Local-path scheme: resolved relative to the caller's cwd (or
            # absolute), no cache/download. Plain stderr, not zz-log: this
            # can be the very first thing zz-use resolves, before zz-log
            # is on PATH.
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
            _gh_ref="${_req_ref:-$ZZ_ORIGIN_REF}"
            _cache_dir="${ZZ_CACHE_DIR}/${_req_origin}/${_gh_ref}"
            _url=""
            if [ "$FORCE" -eq 1 ] || ! _cache_fresh "$_cache_dir" "$_gh_ref"; then
                # "|" (not "/") as the sed delimiter: {ORIGIN} and {REF}
                # can themselves contain "/" (org/repo, or a branch name
                # like "feature/foo"), which would break s///.
                _url=$(printf '%s' "$ZZ_USE_REPO_URL" | sed -e "s|{ORIGIN}|${_req_origin}|g" -e "s|{REF}|${_gh_ref}|g")
            fi
            _fetch_archive "$_cache_dir" "$_url" "repo scripts ({B ${_req_origin}@${_gh_ref}})" || return 1
            ;;
        *)
            # npm scheme, unscoped package (e.g. "mypkg") — no "/" at all.
            _resolve_npm || return 1
            ;;
        esac
    fi

    _boot_dir=$(mktemp -d)
    _add_tmp "$_boot_dir"
    _BOOT_DIRS="${_BOOT_DIRS} ${_boot_dir}"
    for _d in "${_SRC}"/zz-*/; do
        [ -f "${_d}run.sh" ] || continue
        ln -s "${_d}run.sh" "${_boot_dir}/$(basename "$_d")"
    done
    export PATH="${_boot_dir}:${PATH}"

    _SRC_MAP="${_SRC_MAP}
${_src_key}|${_SRC}"
}

# _bindir runs before anything captured via $(...) could cache it, so it
# sets _ZZ_BINDIR (memoized for the whole run) instead of printing it, and
# extends this script's own PATH so a tool installed just now is found by
# later checks. Delegates to the real zz-bindir, resolving the default
# source first if zz-bindir isn't on PATH yet — callers re-resolve their
# own source afterwards, since that can change _SRC.
_ZZ_BINDIR=""
_bindir() {
    [ -n "$_ZZ_BINDIR" ] && return 0
    command -v zz-bindir >/dev/null 2>&1 || _resolve_src || return 1
    dir=""
    eval "$(zz-bindir)" || return 1
    [ -n "$dir" ] || return 1
    _ZZ_BINDIR="$dir"
    case ":$PATH:" in
    *":$dir:"*) ;;
    *) export PATH="$dir:$PATH" ;;
    esac
}

# Some scripts (json-validate's "-l true" fallback schema, in particular)
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
# the *source* package.json in the source of <origin>@<ref>. A peer that
# exists as a script in that same source is requested from it (so a
# pinned or other-origin script gets its siblings from the same place);
# any other peer resolves as a plain name. npm packages a script only
# runs through npx belong in "dependencies", which is ignored here.
#
# Every peer spec is computed before the first recursive _use call (which
# clobbers globals, this function's own included). _PEER_SEEN guards
# against reprocessing the same spec twice (two siblings sharing one, or
# a glob install) and against a cycle recursing forever.
_PEER_SEEN=""
_install_peer_deps() {
    _pd_name="$1" _pd_origin="${2:-$ZZ_ORIGIN}" _pd_ref="${3:-}"
    _resolve_src "$_pd_origin" "$_pd_ref" || return 1
    _peer_json="${_SRC}/${_pd_name}/package.json"
    [ -f "$_peer_json" ] || return 0
    if command -v jq >/dev/null 2>&1; then
        _peers=$(jq -r '.peerDependencies // {} | keys[]' "$_peer_json")
    else
        _peers=$(sed -n '/"peerDependencies"[[:space:]]*:/,/}/p' "$_peer_json" | grep -o '"[^"]*"[[:space:]]*:' | sed -e 's/"[[:space:]]*:$//' -e 's/^"//' | grep -v '^peerDependencies$')
    fi
    _specs=""
    for _peer in $_peers; do
        case "$_peer" in
        "@tomgrv/scripts-"*) _peer="${_peer#@tomgrv/scripts-}" ;;
        esac
        if [ "$_pd_origin" != "$ZZ_ORIGIN" ] || [ -n "$_pd_ref" ]; then
            case "$_peer" in
            */* | @*) ;;
            *) [ -f "${_SRC}/${_peer}/run.sh" ] && _peer="${_pd_origin}/${_peer}${_pd_ref:+@${_pd_ref}}" ;;
            esac
        fi
        case " $_PEER_SEEN " in
        *" $_peer "*) continue ;;
        esac
        _PEER_SEEN="${_PEER_SEEN} ${_peer}"
        _specs="${_specs} ${_peer}"
    done
    [ -n "$_specs" ] || return 0
    # Word-split on purpose: specs never contain whitespace.
    # shellcheck disable=SC2086
    _use $_specs
}

# Where the stamp recording which <origin>@<ref> produced an installed
# <tool> lives: bindir/.zz_use/<tool>, next to the tool itself.
_stamp_path() {
    printf '%s/.zz_use/%s' "$(dirname "$1")" "$2"
}

# Install a single named script from this or another repo. Returns
# non-zero (silently) when <name> isn't a script in that repo at all, so
# the caller can fall through to the apt/config lookup for external tools.
# Does not install peers: the caller does, once it's done reading its own
# variables (see _install_peer_deps).
_install_repo_script() {
    _name="$1"
    _origin="${2:-$ZZ_ORIGIN}"
    _ref="${3:-}"
    _resolve_src "$_origin" "$_ref" || return 1
    [ -f "${_SRC}/${_name}/run.sh" ] || return 1

    _bindir || { zz-log e "No writable bin directory found for {Purple ${_name}}"; return 1; }
    # _bindir may have resolved the default source: switch back.
    _resolve_src "$_origin" "$_ref" || return 1
    _dir="$_ZZ_BINDIR"

    zz-log i "Installing {Purple ${_name}} from {U ${_SRC}/${_name}} to {U ${_dir}}..."
    # Write to a temp file and `mv` into place rather than `cp` over the
    # target directly: <_name> can be zz-use itself (e.g. under
    # zz-update), and an in-place cp can truncate a script the shell is
    # still mid-read on. mv (same filesystem) is an atomic rename instead.
    cp "${_SRC}/${_name}/run.sh" "${_dir}/.${_name}.$$"
    chmod +x "${_dir}/.${_name}.$$"
    mv "${_dir}/.${_name}.$$" "${_dir}/${_name}"
    _install_script_config "${_SRC}/${_name}/config" "${_dir}/config"
    mkdir -p "${_dir}/.zz_use"
    printf '%s@%s\n' "$_origin" "$_ref" >"$(_stamp_path "${_dir}/${_name}" "$_name")"
    zz-log s "Installed {Purple ${_name}} to {U ${_dir}/${_name}}"
}

# Expand {VERSION}/{OS}/{ARCH} in a zz-use.json url/binpath template ({OS}:
# uname -s, lowercased; {ARCH}: uname -m, mapped to amd64/arm64).
_platform() {
    _os=$(uname -s | tr '[:upper:]' '[:lower:]')
    case "$(uname -m)" in
    x86_64 | amd64) _arch=amd64 ;;
    aarch64 | arm64) _arch=arm64 ;;
    *) _arch=$(uname -m) ;;
    esac
}
_expand() {
    _platform
    printf '%s' "$1" | sed \
        -e "s/{VERSION}/${2:-}/g" \
        -e "s/{OS}/${_os}/g" \
        -e "s/{ARCH}/${_arch}/g"
}

# Download <url_tpl> to a file (never piped: sh has no pipefail), verify
# its optional sha256, then extract and install the binary.
_download_install() {
    _tool="$1" _url_tpl="$2" _archive="$3" _binpath_tpl="$4" _version="$5" _sha="$6"

    _url=$(_expand "$_url_tpl" "$_version")
    _binpath=$(_expand "${_binpath_tpl:-$_tool}" "$_version")

    zz-log i "Downloading {Purple $_tool} from {U $_url}..."
    _tmp=$(mktemp -d)
    _add_tmp "$_tmp"
    mkdir -p "$_tmp/x"
    curl -fsSL "$_url" -o "$_tmp/dl" || { zz-log e "Download of {U $_url} failed"; return 1; }
    _verify_sha256 "$_tmp/dl" "$_sha" || return 1

    case "$_archive" in
    tar.gz | tgz) tar -xzf "$_tmp/dl" -C "$_tmp/x" || return 1 ;;
    tar.xz) tar -xJf "$_tmp/dl" -C "$_tmp/x" || return 1 ;;
    zip) unzip -q "$_tmp/dl" -d "$_tmp/x" || return 1 ;;
    raw | "" | *)
        mv "$_tmp/dl" "$_tmp/x/$_tool"
        _binpath="$_tool"
        ;;
    esac

    [ -f "$_tmp/x/$_binpath" ] || { zz-log e "Downloaded archive for {Purple $_tool} has no {U $_binpath}"; return 1; }

    _bindir || { zz-log e "No writable bin directory found for {Purple ${_tool}}"; return 1; }
    chmod +x "$_tmp/x/$_binpath"
    cp "$_tmp/x/$_binpath" "$_ZZ_BINDIR/$_tool"
    zz-log s "Installed {Purple $_tool} to {U $_ZZ_BINDIR/$_tool}"
}

# The activator itself: resolve every requested tool, one at a time.
# "[org/repo/]<tool>[@ref]" pulls that tool from a specific repo and/or
# pins it to a tag/branch/commit instead of ZZ_ORIGIN/ZZ_ORIGIN_REF.
#
# Recursion (peers) clobbers every variable below, so each iteration
# installs its peers as its very last step, reading nothing afterwards.
_use() {
    if [ $# -eq 0 ]; then
        # Plain stderr, not zz-log: this can run before zz-log itself has
        # been resolved.
        printf '[e] Usage: zz-use <tool>[@ref] [tool[@ref]...]\n' >&2
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

        # A glob tool name (e.g. "zz-*") expands to every matching script
        # folder in the source tree. Each match installs unconditionally.
        # The match list and origin/ref are captured up front: installing
        # a match's peers recurses into _use and clobbers the rest. A glob
        # matching nothing warns rather than failing.
        case "$tool" in
        *\**)
            _resolve_src "$origin" "$ref" || return 1
            _g_origin="$origin" _g_ref="$ref"
            _g_names=""
            for _gd in "${_SRC}"/${tool}/; do
                [ -f "${_gd}run.sh" ] || continue
                _g_names="${_g_names} $(basename "$_gd")"
            done
            if [ -z "$_g_names" ]; then
                zz-log w "No scripts match {Purple ${tool}} in {U ${_SRC}}"
                continue
            fi
            for _g_name in $_g_names; do
                _install_repo_script "$_g_name" "$_g_origin" "$_g_ref" || return 1
            done
            for _g_name in $_g_names; do
                _PEER_SEEN="${_PEER_SEEN} ${_g_name}"
            done
            # One peer pass once every match is installed; the matches
            # are marked seen above so their peers don't reinstall them.
            for _g_name in $_g_names; do
                _install_peer_deps "$_g_name" "$_g_origin" "$_g_ref" || return 1
            done
            continue
            ;;
        esac

        # A plain, default-origin, unversioned request (or --force on a
        # non-zz- tool, which --force doesn't apply to) can be skipped if
        # actually installed. A pinned ref or non-default origin is
        # skipped only when the stamp left by its last install names the
        # same origin@ref (local and git-root origins always reinstall, so
        # edits to a sibling checkout are picked up).
        if [ "$FORCE" -eq 0 ] || [ "${tool#zz-}" = "$tool" ]; then
            if [ -z "$ref" ] && [ "$origin" = "$ZZ_ORIGIN" ]; then
                if _have "$tool"; then
                    zz-log d "{Purple $tool} already available"
                    continue
                fi
            elif [ "$FORCE" -eq 0 ] && _have "$tool"; then
                case "$origin" in
                . | .. | ./* | ../* | /* | '$'*) ;;
                *)
                    _stamp=$(_stamp_path "$_HAVE_PATH" "$tool")
                    if [ "$(cat "$_stamp" 2>/dev/null)" = "${origin}@${ref}" ]; then
                        zz-log d "{Purple $tool} already installed from {B ${origin}@${ref}}"
                        continue
                    fi
                    ;;
                esac
            fi
        fi

        entry=""
        if [ -f "$ZZ_USE_CONFIG" ] && grep -q "\"${tool}\"[[:space:]]*:" "$ZZ_USE_CONFIG" && _ensure_jq; then
            entry=$(jq -c --arg t "$tool" '.[$t] // empty' "$ZZ_USE_CONFIG" 2>/dev/null)
        fi

        _peers_pending=0
        if [ -n "$entry" ]; then
            apt_pkg=$(printf '%s' "$entry" | jq -r '.apt // empty')
            url=$(printf '%s' "$entry" | jq -r '.url // empty')

            if [ -n "$apt_pkg" ]; then
                _pkg_install "$apt_pkg" || zz-log w "Package install of {Purple $apt_pkg} failed"
            elif [ -n "$url" ]; then
                _platform
                archive=$(printf '%s' "$entry" | jq -r '.archive // empty')
                binpath=$(printf '%s' "$entry" | jq -r '.binpath // empty')
                version=$(printf '%s' "$entry" | jq -r '.version // empty')
                # sha256: one hash, or an object keyed "<os>_<arch>".
                sha=$(printf '%s' "$entry" | jq -r --arg k "${_os}_${_arch}" \
                    '.sha256 // empty | if type == "object" then .[$k] // empty else . end')
                _download_install "$tool" "$url" "$archive" "$binpath" "$version" "$sha" \
                    || zz-log w "Download install of {Purple $tool} failed"
            fi
        elif _install_repo_script "$tool" "$origin" "$ref"; then
            _peers_pending=1
        else
            _pkg_install "$tool" || true
        fi

        if ! _have "$tool"; then
            zz-log e "Unable to provide required dependency: {Purple $tool}"
            return 1
        fi

        if [ "$_peers_pending" -eq 1 ]; then
            _install_peer_deps "$tool" "$origin" "$ref" || return 1
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
