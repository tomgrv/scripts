#!/bin/sh
# zz-bindir [-t target] — resolve (and create if needed) a writable bin
# directory on PATH. Usage: eval "$(zz-bindir)" — prints `export PATH=...`
# (only when the dir wasn't already on PATH) followed by `dir=<chosen dir>`,
# so the caller both gets PATH extended and can read $dir. Extracted out of
# the historical zz_feature -i bin-linking flow; shared by feature-install
# and zz-use.

# ZZ_BIN_DIR (alias INSTALL_BIN_DIR) overrides the first candidate, /usr/local/bin.
# -s skips one dir when walking PATH: zz-use passes its scratch boot dir,
# which vanishes when it exits.

. zz-colors

# --- arguments
eval "$(
    zz-args "Resolve a writable bin directory on PATH" "$0" "$@" <<help
t target target Extra directory whose bin/ is a candidate (created if needed)
s skip skip PATH directory never to choose (e.g. a scratch dir)
help
)"

# --- candidates: INSTALL_BIN_DIR, ~/.local/bin, then PATH entries, then <target>/bin.
# --- functions
# Register $1 as a candidate; $2=1 when it may be created.
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

# --- candidates
add_candidate "${ZZ_BIN_DIR:-${INSTALL_BIN_DIR:-/usr/local/bin}}" 1
[ -n "$HOME" ] && add_candidate "$HOME/.local/bin" 1

old_ifs=$IFS
IFS=':'
for dir in $PATH; do
    case "$dir" in
    "" | "." | "$PWD" | */node_modules/.bin) continue ;;
    esac
    if [ "$dir" = "$skip" ]; then
        zz-log n "Not installing into {U $dir}: it is skipped (-s)"
        continue
    fi
    add_candidate "$dir"
done
IFS=$old_ifs
[ -n "$target" ] && add_candidate "$target/bin" 1

# --- pick the first writable candidate, else create one
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
    zz-log e "No writable bin directory found" >&2
    echo "exit 1"
    exit 1
fi

# --- output: PATH extension (when needed) and the chosen dir, for the caller to eval
case ":$PATH:" in
*":$link_dir:"*) ;;
*) echo "export PATH='$link_dir':\$PATH" ;;
esac

echo "dir='$link_dir'"
