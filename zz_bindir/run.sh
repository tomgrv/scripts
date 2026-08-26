#!/bin/sh
# zz_bindir [-t target] — resolve (and create if needed) a writable bin
# directory on PATH. Usage: eval "$(zz_bindir)" — prints `export PATH=...`
# (only when the dir wasn't already on PATH) followed by `dir=<chosen dir>`,
# so the caller both gets PATH extended and can read $dir. Extracted out of
# the historical zz_feature -i bin-linking flow; shared by install-feature
# and zz_use.

. zz_colors

target=""
while getopts :t: opt "$@"; do
    case "$opt" in
    t) target="$OPTARG" ;;
    esac
done

candidates=""
creatable=""

add_candidate() {
    c="$1"
    mk="${2:-0}"
    [ -n "$c" ] || return 0
    case ":$candidates:" in
    *":$c:"*) ;;
    *)
        candidates="${candidates:+$candidates:}$c"
        [ "$mk" = "1" ] && creatable="${creatable:+$creatable:}$c"
        ;;
    esac
}

add_candidate "${INSTALL_BIN_DIR:-/usr/local/bin}" 1
[ -n "$HOME" ] && add_candidate "$HOME/.local/bin" 1

old_ifs=$IFS
IFS=':'
for dir in $PATH; do
    case "$dir" in
    "" | "." | "$PWD" | */node_modules/.bin) continue ;;
    esac
    add_candidate "$dir"
done
IFS=$old_ifs
[ -n "$target" ] && add_candidate "$target/bin" 1

link_dir=""
old_ifs=$IFS
IFS=':'
for c in $candidates; do
    if [ -d "$c" ] && [ -w "$c" ] && [ -x "$c" ]; then
        link_dir="$c"
        break
    fi
done

if [ -z "$link_dir" ]; then
    for c in $creatable; do
        mkdir -p "$c" 2>/dev/null || true
        if [ -d "$c" ] && [ -w "$c" ] && [ -x "$c" ]; then
            link_dir="$c"
            break
        fi
    done
fi
IFS=$old_ifs

if [ -z "$link_dir" ]; then
    zz_log e "No writable bin directory found" >&2
    echo "exit 1"
    exit 1
fi

case ":$PATH:" in
*":$link_dir:"*) ;;
*) echo "export PATH='$link_dir':\$PATH" ;;
esac

echo "dir='$link_dir'"
