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

# --- parameters: options, source and cache settings.
FORCE=0
EXEC_TOOL=""

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
default_repo_url='https://github.com/{ORIGIN}/archive/{REF}.tar.gz'
ZZ_USE_REPO_URL="${ZZ_USE_REPO_URL:-$default_repo_url}"
ZZ_CACHE_DIR="${ZZ_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/zz_scripts}"
# Minutes before a cached archive for a mutable ref (a branch like "main",
# or npm's "latest") is refetched; 0 = never expire. Immutable refs (a
# version tag or commit sha) never expire.
ZZ_CACHE_TTL="${ZZ_CACHE_TTL:-1440}"

# --- functions: resolve a source, install scripts and tools, then _use.

# Every temp dir this script creates is cleaned up through this single
# mechanism instead of each having its own EXIT trap (which would clobber
# each other).
tmp_dirs=""
_add_tmp() { tmp_dirs="${tmp_dirs} $1"; }
# Always returns 0, so an empty $tmp_dirs (nothing to clean up) doesn't
# turn an otherwise-successful run into a reported failure.
_cleanup() {
    [ -n "$tmp_dirs" ] && rm -rf $tmp_dirs
    return 0
}
trap _cleanup EXIT

# src: the resolved source tree of the origin+ref last passed to
# _resolve_src. src_map remembers every origin+ref already resolved this
# run ("<origin>@<ref>|<dir>" lines), so switching back and forth between
# origins (a pinned script whose peers live at the default origin, say)
# neither re-downloads under --force nor stacks another boot dir on PATH.
# boot_dir is the one scratch dir (created on first use, shared by every
# origin) holding their zz-* symlinks: it must never count as "installed"
# (it vanishes when this process exits) nor as an install target.
src=""
src_map=""
boot_dir=""

# Every function declares its variables `local`, so _use recursing (through
# _install_peer_deps) cannot clobber its caller's. Only the globals above
# are shared: src in particular changes under any call that resolves a
# source, so read it right after the _resolve_src that set it.

# True if <tool> is on PATH outside the scratch boot dir — i.e. actually
# installed, not merely exposed for the lifetime of this process. Sets
# have_path to where it was found.
have_path=""
_have() {
    local dir old_ifs

    old_ifs=$IFS
    IFS=':'
    for dir in $PATH; do
        [ -n "$dir" ] || continue
        [ "$dir" = "$boot_dir" ] && continue
        if [ -f "$dir/$1" ] && [ -x "$dir/$1" ]; then
            IFS=$old_ifs
            have_path="$dir/$1"
            return 0
        fi
    done
    IFS=$old_ifs
    return 1
}

# Install a system package through zz-install (it picks the package manager
# and escalates through sudo). Resolves the default source first when
# zz-install isn't on PATH yet, like _bindir does.
_pkg_install() {
    command -v zz-install >/dev/null 2>&1 || _resolve_src || return 1
    zz-install "$1"
}

# jq is needed to read zz-use.json and npm registry metadata: install it
# straight through the package manager (never through _use, which needs jq
# itself) when it's missing.
_ensure_jq() {
    command -v jq >/dev/null 2>&1 && return 0
    _pkg_install jq >/dev/null 2>&1 || true
    command -v jq >/dev/null 2>&1
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
    local dir

    for dir in "$1"/*/; do [ -f "${dir}run.sh" ] && return 0; done
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
# src on success; <url> may be empty when fresh.
_fetch_archive() {
    local cache_dir url desc tmp

    cache_dir="$1" url="$2" desc="$3"
    if [ -n "$url" ]; then
        zz-log d "Retrieving ${desc} from {U ${url}}"
        tmp="${cache_dir}.tmp.$$"
        _add_tmp "$tmp"
        rm -rf "$tmp"
        mkdir -p "$tmp/x"
        if curl -fsSL "$url" -o "$tmp/a.tar.gz" \
            && tar -xzf "$tmp/a.tar.gz" -C "$tmp/x" --strip-components=1 \
            && _cache_warm "$tmp/x"; then
            mkdir -p "$(dirname "$cache_dir")"
            rm -rf "$cache_dir"
            mv "$tmp/x" "$cache_dir"
        elif _cache_warm "$cache_dir"; then
            zz-log w "Could not refresh ${desc}"
            zz-log - "Using the stale cache at {U ${cache_dir}}"
        else
            zz-log e "Could not retrieve ${desc}"
            zz-log - "The download failed, or it holds no <name>/run.sh script"
            return 1
        fi
    else
        zz-log d "Using cached ${desc} at {U ${cache_dir}}"
    fi
    src="$cache_dir"
}

# Fetch (or reuse the cache for) an npm-registry origin, scoped
# ("@scope/pkg") or unscoped ("pkg") alike. <ref> is a dist-tag or exact
# version (default "latest"). Cached under its own origin+ref slot like a
# GitHub archive (_fetch_archive above), just fetched from the npm
# registry's tarball. Sets src on success.
_resolve_npm() {
    local origin="$1" ref="$2" # npm package name; dist-tag or exact version (both mandatory, ref may be empty)
    local cache_dir meta_url npm_origin_enc npm_ref tarball

    _ensure_jq || {
        printf '[e] npm origin %s requires jq on PATH\n' "$origin" >&2
        return 1
    }
    npm_ref="${ref:-latest}"
    cache_dir="${ZZ_CACHE_DIR}/${origin}/${npm_ref}"
    tarball=""
    if [ "$FORCE" -eq 1 ] || ! _cache_fresh "$cache_dir" "$npm_ref"; then
        npm_origin_enc=$(printf '%s' "$origin" | sed 's#/#%2f#g')
        meta_url="https://registry.npmjs.org/${npm_origin_enc}/${npm_ref}"
        tarball=$(curl -fsSL "$meta_url" 2>/dev/null | jq -r '.dist.tarball // empty' 2>/dev/null) || tarball=""
        if [ -z "$tarball" ]; then
            _cache_warm "$cache_dir" || {
                zz-log e "Could not resolve the npm tarball for {Purple ${origin}@${npm_ref}}"
                zz-log - "Looked it up at {U ${meta_url}}"
                return 1
            }
            zz-log w "Could not refresh {Purple ${origin}@${npm_ref}}"
            zz-log - "Using the stale cache"
        fi
    fi
    _fetch_archive "$cache_dir" "$tarball" "npm package ({B ${origin}@${npm_ref}})"
}

# Resolve src for <origin> (default ZZ_ORIGIN) at <ref> (default
# ZZ_ORIGIN_REF): a local checkout (ROOT_DIR) when running from within
# this repo at the default origin/ref, otherwise the local cache for
# that origin+ref (refreshed first when missing, expired or under
# --force). Then exposes every zz-*/run.sh in it on PATH under its bare
# name (zz-colors, zz-log, ...) via symlinks in a scratch dir, so
# `zz-log ...` and `. zz-colors` resolve normally from here on. Each
# origin+ref is resolved at most once per run (src_map).
_resolve_src() {
    local cache_dir dir gh_ref git_root req_origin req_ref src_hit src_key sub url

    req_origin="${1:-$ZZ_ORIGIN}"
    req_ref="${2:-}"
    src_key="${req_origin}@${req_ref}"
    src_hit=$(printf '%s\n' "$src_map" | awk -F'|' -v k="$src_key" '$1 == k { print $2; exit }')
    if [ -n "$src_hit" ]; then
        src="$src_hit"
        return 0
    fi

    if [ "$req_origin" = "$ZZ_ORIGIN" ] && [ -z "$req_ref" ] && [ -f "${ROOT_DIR}/zz-colors/run.sh" ]; then
        src="$ROOT_DIR"
    else
        case "$req_origin" in
        . | .. | ./* | ../* | /*)
            # Local-path scheme: resolved relative to the caller's cwd (or
            # absolute), no cache/download. Plain stderr, not zz-log: this
            # can be the very first thing zz-use resolves, before zz-log
            # is on PATH.
            src=$(cd "$req_origin" 2>/dev/null && pwd) || {
                printf '[e] Local repo path %s not found\n' "$req_origin" >&2
                return 1
            }
            ;;
        '$'*)
            # Git-root scheme ("$" or "$<subpath>"): same no-cache handling
            # as a local path, anchored at the repo root instead of cwd.
            git_root=$(git rev-parse --show-toplevel 2>/dev/null) || {
                printf '[e] %s: not inside a git repository\n' "$req_origin" >&2
                return 1
            }
            sub="${req_origin#\$}"
            case "$sub" in /*) sub="${sub#/}" ;; esac
            if [ -z "$sub" ]; then
                src="$git_root"
            else
                src=$(cd "${git_root}/${sub}" 2>/dev/null && pwd) || {
                    printf '[e] Git-root path %s not found (root: %s)\n' "$req_origin" "$git_root" >&2
                    return 1
                }
            fi
            ;;
        @*)
            # npm scheme, scoped package (e.g. "@myscope/pkg").
            _resolve_npm "$req_origin" "$req_ref" || return 1
            ;;
        */*)
            # GitHub-archive scheme: "org/repo" — always has a "/", unlike
            # an unscoped npm name (caught by the "*)" arm below).
            gh_ref="${req_ref:-$ZZ_ORIGIN_REF}"
            cache_dir="${ZZ_CACHE_DIR}/${req_origin}/${gh_ref}"
            url=""
            if [ "$FORCE" -eq 1 ] || ! _cache_fresh "$cache_dir" "$gh_ref"; then
                # "|" (not "/") as the sed delimiter: {ORIGIN} and {REF}
                # can themselves contain "/" (org/repo, or a branch name
                # like "feature/foo"), which would break s///.
                url=$(printf '%s' "$ZZ_USE_REPO_URL" | sed -e "s|{ORIGIN}|${req_origin}|g" -e "s|{REF}|${gh_ref}|g")
            fi
            _fetch_archive "$cache_dir" "$url" "repo scripts ({B ${req_origin}@${gh_ref}})" || return 1
            ;;
        *)
            # npm scheme, unscoped package (e.g. "mypkg") — no "/" at all.
            _resolve_npm "$req_origin" "$req_ref" || return 1
            ;;
        esac
    fi

    if [ -z "$boot_dir" ]; then
        boot_dir=$(mktemp -d)
        _add_tmp "$boot_dir"
        export PATH="${boot_dir}:${PATH}"
    fi
    # -f: a later origin's zz-* shadows an earlier one's, as a newer dir
    # prepended to PATH would.
    for dir in "${src}"/zz-*/; do
        [ -f "${dir}run.sh" ] || continue
        ln -sf "${dir}run.sh" "${boot_dir}/$(basename "$dir")"
    done

    src_map="${src_map}
${src_key}|${src}"
}

# _bindir runs before anything captured via $(...) could cache it, so it
# sets bindir (memoized for the whole run) instead of printing it, and
# extends this script's own PATH so a tool installed just now is found by
# later checks. Delegates to the real zz-bindir, resolving the default
# source first if zz-bindir isn't on PATH yet — callers re-resolve their
# own source afterwards, since that can change src.
bindir=""
_bindir() {
    local dir

    [ -n "$bindir" ] && return 0
    command -v zz-bindir >/dev/null 2>&1 || _resolve_src || return 1
    dir=""
    eval "$(zz-bindir -s "$boot_dir")" || return 1
    [ -n "$dir" ] || return 1
    bindir="$dir"
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
    local cfg_dest cfg_dir cfg_file cfg_src

    cfg_src="$1" cfg_dir="$2"
    [ -d "$cfg_src" ] || return 0
    mkdir -p "$cfg_dir"
    for cfg_file in "$cfg_src"/*; do
        [ -f "$cfg_file" ] || continue
        cfg_dest="$cfg_dir/$(basename "$cfg_file")"
        [ -e "$cfg_dest" ] || cp "$cfg_file" "$cfg_dest"
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
# may resolve another source and change src). peer_seen guards
# against reprocessing the same spec twice (two siblings sharing one, or
# a glob install) and against a cycle recursing forever.
peer_seen=""
_install_peer_deps() {
    local pd_name pd_origin pd_ref peer peer_json peers specs

    pd_name="$1" pd_origin="${2:-$ZZ_ORIGIN}" pd_ref="${3:-}"
    _resolve_src "$pd_origin" "$pd_ref" || return 1
    peer_json="${src}/${pd_name}/package.json"
    [ -f "$peer_json" ] || return 0
    if command -v jq >/dev/null 2>&1; then
        peers=$(jq -r '.peerDependencies // {} | keys[]' "$peer_json")
    else
        peers=$(sed -n '/"peerDependencies"[[:space:]]*:/,/}/p' "$peer_json" | grep -o '"[^"]*"[[:space:]]*:' | sed -e 's/"[[:space:]]*:$//' -e 's/^"//' | grep -v '^peerDependencies$')
    fi
    specs=""
    for peer in $peers; do
        case "$peer" in
        "@tomgrv/scripts-"*) peer="${peer#@tomgrv/scripts-}" ;;
        esac
        if [ "$pd_origin" != "$ZZ_ORIGIN" ] || [ -n "$pd_ref" ]; then
            case "$peer" in
            */* | @*) ;;
            *) [ -f "${src}/${peer}/run.sh" ] && peer="${pd_origin}/${peer}${pd_ref:+@${pd_ref}}" ;;
            esac
        fi
        case " $peer_seen " in
        *" $peer "*) continue ;;
        esac
        peer_seen="${peer_seen} ${peer}"
        specs="${specs} ${peer}"
    done
    [ -n "$specs" ] || return 0
    # Word-split on purpose: specs never contain whitespace.
    # shellcheck disable=SC2086
    _use $specs
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
    local dir from name origin ref

    name="$1"
    origin="${2:-$ZZ_ORIGIN}"
    ref="${3:-}"
    _resolve_src "$origin" "$ref" || return 1
    [ -f "${src}/${name}/run.sh" ] || return 1

    _bindir || {
        zz-log e "No writable bin directory found for {Purple ${name}}"
        return 1
    }
    # _bindir may have resolved the default source: switch back.
    _resolve_src "$origin" "$ref" || return 1
    dir="$bindir"

    # Say where it comes from: org/repo@ref, or the path for a local origin.
    case "$origin" in
    ./* | ../* | /* | \$*) from="$origin" ;;
    *) from="${origin}@${ref:-$ZZ_ORIGIN_REF}" ;;
    esac
    # Write to a temp file and `mv` into place rather than `cp` over the
    # target directly: <name> can be zz-use itself (e.g. under
    # zz-update), and an in-place cp can truncate a script the shell is
    # still mid-read on. mv (same filesystem) is an atomic rename instead.
    cp "${src}/${name}/run.sh" "${dir}/.${name}.$$"
    chmod +x "${dir}/.${name}.$$"
    mv "${dir}/.${name}.$$" "${dir}/${name}"
    _install_script_config "${src}/${name}/config" "${dir}/config"
    mkdir -p "${dir}/.zz_use"
    printf '%s@%s\n' "$origin" "$ref" >"$(_stamp_path "${dir}/${name}" "$name")"
    zz-log s "Installed {Purple ${name}} from {B ${from}} to {U ${dir}/${name}}"
}

# The activator itself: resolve every requested tool, one at a time.
# "[org/repo/]<tool>[@ref]" pulls that tool from a specific repo and/or
# pins it to a tag/branch/commit instead of ZZ_ORIGIN/ZZ_ORIGIN_REF.
#
# Recursion (peers) may change src, so each iteration installs its peers as
# its very last step, reading nothing afterwards.
_use() {
    local apt_pkg at_sigil dir entry field g_name g_names g_origin g_ref name_part origin peers_pending ref rest_ref stamp tool tool_ref url val

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
            at_sigil="@"
            rest_ref="${tool_ref#@}"
            ;;
        *)
            at_sigil=""
            rest_ref="$tool_ref"
            ;;
        esac
        case "$rest_ref" in
        *@*)
            name_part="${at_sigil}${rest_ref%%@*}"
            ref="${rest_ref#*@}"
            ;;
        *)
            name_part="${at_sigil}${rest_ref}"
            ref=""
            ;;
        esac

        # The origin prefix is everything before <tool>'s own last "/" —
        # one rule for every scheme. A tool name with no "/" at all
        # defaults to ZZ_ORIGIN.
        case "$name_part" in
        */*)
            origin="${name_part%/*}"
            tool="${name_part##*/}"
            ;;
        *)
            origin="$ZZ_ORIGIN"
            tool="$name_part"
            ;;
        esac

        # A glob tool name (e.g. "zz-*") expands to every matching script
        # folder in the source tree. Each match installs unconditionally.
        # The match list and origin/ref are captured up front: installing
        # a match's peers recurses into _use and may change src. A glob
        # matching nothing warns rather than failing.
        case "$tool" in
        *\**)
            _resolve_src "$origin" "$ref" || return 1
            g_origin="$origin" g_ref="$ref"
            g_names=""
            for dir in "${src}"/${tool}/; do
                [ -f "${dir}run.sh" ] || continue
                g_names="${g_names} $(basename "$dir")"
            done
            if [ -z "$g_names" ]; then
                zz-log w "No script matches {Purple ${tool}} in {U ${src}}"
                continue
            fi
            for g_name in $g_names; do
                _install_repo_script "$g_name" "$g_origin" "$g_ref" || return 1
            done
            for g_name in $g_names; do
                peer_seen="${peer_seen} ${g_name}"
            done
            # One peer pass once every match is installed; the matches
            # are marked seen above so their peers don't reinstall them.
            for g_name in $g_names; do
                _install_peer_deps "$g_name" "$g_origin" "$g_ref" || return 1
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
        if [ "$FORCE" -eq 0 ] || { [ "${tool#zz-}" = "$tool" ] && [ "$tool" != "zz" ]; }; then
            if [ -z "$ref" ] && [ "$origin" = "$ZZ_ORIGIN" ]; then
                if _have "$tool"; then
                    zz-log d "{Purple $tool} already available"
                    continue
                fi
            elif [ "$FORCE" -eq 0 ] && _have "$tool"; then
                case "$origin" in
                . | .. | ./* | ../* | /* | '$'*) ;;
                *)
                    stamp=$(_stamp_path "$have_path" "$tool")
                    if [ "$(cat "$stamp" 2>/dev/null)" = "${origin}@${ref}" ]; then
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

        peers_pending=0
        if [ -n "$entry" ]; then
            apt_pkg=$(printf '%s' "$entry" | jq -r '.apt // empty')
            url=$(printf '%s' "$entry" | jq -r '.url // empty')

            if [ -n "$apt_pkg" ]; then
                _pkg_install "$apt_pkg" || zz-log w "Could not install {Purple $apt_pkg} as a package"
            elif [ -n "$url" ]; then
                # zz-install downloads, verifies and installs the binary
                # (sha256: one hash, or an object keyed "<os>_<arch>").
                set -- -u "$url"
                for field in archive:a binpath:b version:v; do
                    val=$(printf '%s' "$entry" | jq -r ".${field%:*} // empty")
                    [ -z "$val" ] || set -- "$@" "-${field#*:}" "$val"
                done
                val=$(printf '%s' "$entry" | jq -r '.sha256 // empty | if type == "object" then tojson else . end')
                [ -z "$val" ] || set -- "$@" -s "$val"
                zz-install "$@" "$tool" || zz-log w "Could not download {Purple $tool}"
                # zz-install ran in a child: put the bin dir on our PATH for _have.
                _bindir || true
            fi
        elif _install_repo_script "$tool" "$origin" "$ref"; then
            peers_pending=1
        else
            _pkg_install "$tool" || true
        fi

        if ! _have "$tool"; then
            zz-log e "Cannot provide {Purple $tool}"
            zz-log - "It is not installed, and no source could install it"
            return 1
        fi

        if [ "$peers_pending" -eq 1 ]; then
            _install_peer_deps "$tool" "$origin" "$ref" || return 1
        fi
    done
}

# --- arguments. A pre-pass keeps what zz-args (getopts) cannot express:
# -f/--force may sit anywhere (hoisted in front of the tools), and -x/--exec
# <tool> ends parsing: everything after it is the exec'd tool's own argv
# (kept quoted in tail, never parsed). Errors use plain stderr: zz-log may
# not be resolved yet.
opts=""
tools=""
tail=""
_quote() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\''/g")"; }
while [ $# -gt 0 ]; do
    case "$1" in
    -x | --exec)
        shift
        EXEC_TOOL="${1:-}"
        if [ -z "$EXEC_TOOL" ]; then
            printf '[e] -x/--exec requires a tool name\n' >&2
            exit 1
        fi
        shift
        for arg in "$@"; do tail="$tail $(_quote "$arg")"; done
        break
        ;;
    --force) opts="$opts -f" ;;
    --help) opts="$opts -h" ;;
    --*)
        printf '[e] Unknown option: %s\n' "$1" >&2
        exit 1
        ;;
    -?) opts="$opts $1" ;;
    *) tools="$tools $(_quote "$1")" ;;
    esac
    shift
done

# zz-args (and its zz-colors) must be on PATH: resolve the default source
# when they are not, as _bindir does for zz-bindir.
case " $opts " in *" -f "*) FORCE=1 ;; esac
command -v zz-args >/dev/null 2>&1 || _resolve_src || exit 1

# Declares the options and collects the tools back onto "$@".
_parse() {
    local force_flag exec_tool tools

    eval "$(
        zz-args "Install tools on demand, only if missing" "zz-use" "$@" <<help
f - force_flag Reinstall even when already on PATH
x tool exec_tool Install <tool> and exec into it with the remaining arguments as its argv
# tools tools Tools to install: [origin/]<tool>[@ref]
help
    )" || return 1
    [ -z "$force_flag" ] || FORCE=1
    _use "$@" ${EXEC_TOOL:+"$EXEC_TOOL"}
}

# -x/--exec: install EXEC_TOOL alongside the tools, then exec into it with
# the saved tail as its argv.
eval "_parse $opts $tools" || exit 1
if [ -n "$EXEC_TOOL" ]; then
    # Same leading-"@" vs trailing-"@ref" split as in _use: an npm-origin
    # exec target (e.g. "@myscope/pkg/tool@1.2.3") must not have its
    # command name mangled by splitting on the scope's own "@".
    case "$EXEC_TOOL" in
    @*)
        exec_rest="${EXEC_TOOL#@}"
        case "$exec_rest" in *@*) exec_rest="${exec_rest%%@*}" ;; esac
        exec_name="@${exec_rest}"
        ;;
    *)
        exec_name="${EXEC_TOOL%%@*}"
        ;;
    esac
    case "$exec_name" in */*) exec_name="${exec_name##*/}" ;; esac
    eval "set -- $tail"
    # exec skips the EXIT trap, and the exec'd tool (which may call zz-use
    # again) must not inherit the boot dir as if it were a real PATH dir.
    if [ -n "$boot_dir" ]; then
        new_path=""
        IFS=':'
        for dir in $PATH; do
            [ "$dir" = "$boot_dir" ] || new_path="${new_path:+$new_path:}$dir"
        done
        unset IFS
        PATH="$new_path"
        _cleanup
    fi
    exec "$exec_name" "$@"
fi
