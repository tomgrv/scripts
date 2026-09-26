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
# The [org/repo/] prefix also accepts a local path — "./some-dir/" or
# "/abs/path/" — instead of a GitHub "org/repo": the checkout is used
# directly, relative to the current working directory, with no cache and
# no download — just symlinked into place the same way this repo's own
# zz_* scripts are, so edits to a local sibling checkout show up on the
# next call with no re-fetch:
#   zz_use ./local-scripts/some-tool
# Like any other non-default origin, a local-path request always
# (re)installs — never skipped as "already available".
#
# Every tool, zz_* core or functional, installs the same way, one at a
# time (a glob name such as "zz_*" just expands to every match and
# recurses — that's how setup.sh gets the whole core set in place up
# front, in one call, before anything else runs):
#
#   1. A script from this same repo (e.g. `zz_use load-json` installs
#      load-json/run.sh, `zz_use zz_log` installs zz_log/run.sh) — from a
#      local checkout when running from one, otherwise a local cache
#      (ZZ_CACHE_DIR/<origin>/<ref>, default ~/.cache/zz_scripts), fetched
#      fresh into that cache the first time it's needed. Use `zz_update`
#      (or `zz_use --force ...`) to force a fresh download, bypassing the
#      cache.
#   2. Otherwise, looked up in config/zz_use.json (ZZ_USE_CONFIG to
#      override):
#        {"apt": "<pkg>"}  -> apt-get install -y <pkg> (sudo if not root)
#        {"url": "...", "archive": "tar.gz"|"tar.xz"|"zip"|"raw",
#         "binpath": "..."} -> download, extract if needed, resolve a
#         writable bin dir, and install the binary as <tool>. Templates
#         support {VERSION}, {OS} (uname -s, lowercased), {ARCH}
#         (uname -m, mapped to amd64/arm64).
#   3. No config entry -> fall back to `apt-get install -y <tool>` (same
#      name) when apt-get is available. (@<ref> has no meaning for an
#      apt package; it's simply ignored if this is the path taken.)
#
# Still not found on PATH afterwards -> error, exit 1.
#
# Idempotent: safe to call on every script invocation — resolved tools are
# skipped in ~0ms via `command -v`, unless --force or @<ref> is given.
#
# -x/--exec <tool> [arg...]: install <tool> (through the same resolution
# path as any other tool) and exec straight into it, replacing this
# process, with every argument after <tool> passed through as its argv.
# Any tool names given before -x are resolved first, as ordinary
# dependencies:
#   zz_use zz_log jq -x validate-json some-file.json
# installs zz_log and jq as usual, then installs and execs
# `validate-json some-file.json`.
#
# zz_use relies on zz_log (and its own siblings) already being on PATH —
# setup.sh's `zz_use "zz_*"` call is what puts the whole core set there in
# the first place; this script doesn't re-derive that bootstrapping.

set -e

# A single left-to-right scan handles every option zz_use recognizes
# (--force/-f, -x/--exec) and rejects any other -leading word, instead of
# splitting that job between a "just the first arg" check for --force and
# a separate loop for everything else — the split let --force go
# unrecognized (and get rejected as an "unknown option") whenever it
# wasn't literally $1, e.g. `zz_use zz_log --force`. Any error printed
# here uses plain stderr, not zz_log: this whole scan runs before any
# tool — zz_log included — has been resolved, unlike every other error in
# this script. Every non-option arg is single-quoted and appended to
# _before (restored with `eval set --` further down), so it survives
# intact even if it contains spaces or quotes. Everything from -x's
# <tool> onward is left in "$@" as-is: <tool> is threaded straight to
# `_use`, and whatever follows it is never parsed by zz_use at all — it
# stays in "$@" untouched, ready to become the exec'd tool's own argv.
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
# _download_install extraction, _resolve_src's own symlink dir) is cleaned
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

# _SRC: the resolved source tree for _SRC_ORIGIN/_SRC_REF (set by
# _resolve_src). _SRC_RESOLVED guards against re-resolving the same
# origin+ref more than once per run — even under --force, which only
# needs to force *one* fresh download per origin+ref, not one per tool
# requested at it (zz_update alone names 13 core tools at the same
# default origin/ref). A different origin+ref requested later in the
# same run re-resolves (and switches _SRC to it).
_SRC=""
_SRC_ORIGIN=""
_SRC_REF=""
_SRC_RESOLVED=0

# Resolve _SRC for <origin> (default: ZZ_ORIGIN) at <ref> (default:
# ZZ_ORIGIN_REF) — a local checkout (ROOT_DIR, when zz_use is running from
# within this repo, the requested origin is this repo's own default, and
# no specific ref was asked for), otherwise the local cache for that
# origin+ref (refreshed first when missing or under --force) — then
# expose every zz_*/run.sh in it on PATH under its bare conventional name
# (zz_colors, zz_log, zz_bindir, ...) via symlinks in a scratch dir.
# That's what lets `zz_log ...` and `. zz_colors` — including from
# *inside* a functional script's own source — all just resolve normally
# from here on, with zero reimplementation of what those scripts do.
_resolve_src() {
    _req_origin="${1:-$ZZ_ORIGIN}"
    _req_ref="${2:-}"
    if [ "$_SRC_RESOLVED" -eq 1 ] && [ "$_SRC_ORIGIN" = "$_req_origin" ] && [ "$_SRC_REF" = "$_req_ref" ]; then
        return 0
    fi

    _local_origin=0
    case "$_req_origin" in
    ./* | ../* | /*) _local_origin=1 ;;
    esac

    if [ "$_req_origin" = "$ZZ_ORIGIN" ] && [ -z "$_req_ref" ] && [ -f "${ROOT_DIR}/zz_colors/run.sh" ]; then
        _SRC="$ROOT_DIR"
    elif [ "$_local_origin" -eq 1 ]; then
        # A local-path origin: resolved directly relative to the caller's
        # cwd, no cache dir and no curl/tar — the whole point is to pick up
        # a sibling checkout as-is (and its future edits) via symlink,
        # exactly like ROOT_DIR above.
        # Plain stderr, not zz_log: this can be the very first thing
        # zz_use ever resolves (see the usage-error comment above), so
        # zz_log itself may not be on PATH yet.
        _SRC=$(cd "$_req_origin" 2>/dev/null && pwd) || { printf '[e] Local repo path %s not found\n' "$_req_origin" >&2; return 1; }
    else
        _cache_dir="${ZZ_CACHE_DIR}/${_req_origin}/${_req_ref:-$ZZ_ORIGIN_REF}"
        _warm=0
        for _d in "$_cache_dir"/*/; do [ -f "${_d}run.sh" ] && _warm=1 && break; done
        if [ "$FORCE" -eq 1 ] || [ "$_warm" -eq 0 ]; then
            # "|" (not "/") as the sed delimiter: {ORIGIN} always contains
            # "/" (org/repo), and {REF} can too (a branch name like
            # "feature/foo") — either would break the s/// syntax with "/".
            _url=$(printf '%s' "$ZZ_USE_REPO_URL" | sed -e "s|{ORIGIN}|${_req_origin}|g" -e "s|{REF}|${_req_ref:-$ZZ_ORIGIN_REF}|g")
            zz_log i "Retrieving repo scripts ({B ${_req_origin}@${_req_ref:-$ZZ_ORIGIN_REF}}) from {U ${_url}}..."
            _tmp="${_cache_dir}.tmp.$$"
            _add_tmp "$_tmp"
            rm -rf "$_tmp"
            mkdir -p "$_tmp"
            curl -fsSL "$_url" | tar -xz -C "$_tmp" --strip-components=1
            _ok=0
            for _d in "$_tmp"/*/; do [ -f "${_d}run.sh" ] && _ok=1 && break; done
            [ "$_ok" -eq 1 ] || { zz_log e "Downloaded archive from {B ${_req_origin}@${_req_ref:-$ZZ_ORIGIN_REF}} has no <name>/run.sh scripts (unexpected repo layout)"; return 1; }
            mkdir -p "$(dirname "$_cache_dir")"
            rm -rf "$_cache_dir"
            mv "$_tmp" "$_cache_dir"
        else
            zz_log d "Using cached repo scripts at {U ${_cache_dir}}"
        fi
        _SRC="$_cache_dir"
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
# core, always individually: nothing in this repo needs to be installed as
# a group any more (setup.sh already puts the whole core set in place up
# front via a "zz_*" glob call). Returns non-zero (silently) when <name>
# isn't a script in that repo at all, so the caller can fall through to
# the apt/config lookup for genuinely external tools.
_install_repo_script() {
    _name="$1"
    _origin="${2:-$ZZ_ORIGIN}"
    _ref="${3:-}"
    _resolve_src "$_origin" "$_ref" || return 1
    [ -f "${_SRC}/${_name}/run.sh" ] || return 1

    _dir=$(_bindir) || { zz_log e "No writable bin directory found for {Purple ${_name}}"; return 1; }
    _ensure_path "$_dir"

    zz_log i "Installing {Purple ${_name}} from {U ${_SRC}/${_name}} to {U ${_dir}}..."
    # Write to a temp file and `mv` it into place rather than `cp`ing over
    # the target directly: <_name> can be zz_use itself (e.g. under
    # zz_update, which force-refreshes the core scripts one by one,
    # including zz_use), and an in-place cp can truncate a script the
    # shell is still mid-read on. mv (same filesystem) is an atomic
    # rename instead.
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
# threaded through to _resolve_src/_install_repo_script.
_use() {
    if [ $# -eq 0 ]; then
        # Plain stderr, not zz_log: the very first call into _use can
        # happen before any tool (zz_log included) has been resolved.
        printf '[e] Usage: zz_use <tool>[@ref] [tool[@ref]...]\n' >&2
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
        # directly — this is how setup.sh puts the whole core zz_* set in
        # place with a single `zz_use "zz_*"` call. Each match is installed
        # for real, unconditionally: _resolve_src's own symlink step (see
        # above) puts every zz_* name on PATH as a side effect, so the
        # ordinary "already available" skip below can't be trusted here —
        # it would make every match after the first look already installed
        # and skip the one thing this glob call exists to do. A glob
        # matching nothing is a soft no-op (warn, don't fail) — unlike a
        # literal unknown tool name, which still errors out below.
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

        if ! command -v "$tool" >/dev/null 2>&1; then
            zz_log e "Unable to provide required dependency: {Purple $tool}"
            return 1
        fi
    done
}

# -x/--exec: install EXEC_TOOL alongside the dependencies collected into
# _before, then exec into it — replacing this process, remaining "$@"
# (never touched by the parsing loop above) becoming its argv. Falls
# through to the plain _use call below when -x wasn't given.
if [ -n "$EXEC_TOOL" ]; then
    eval "_use $_before \"\$EXEC_TOOL\"" || exit 1
    _exec_name="${EXEC_TOOL%%@*}"
    case "$_exec_name" in */*) _exec_name="${_exec_name##*/}" ;; esac
    exec "$_exec_name" "$@"
fi

eval "_use $_before"
