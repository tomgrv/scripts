#!/bin/sh
# zz-persist — upsert a KEY=VALUE pair into an env-style file and/or an
# <ZZ_PROFILE_DIR>/<profile>.sh snippet (default /etc/profile.d), so the value
# survives a new shell or a script re-run.
#   - the env file holds the value literally (read, never sourced);
#   - the profile snippet is sourced by shells, so a value with anything but
#     plain characters is single-quoted there and cannot run code;
#   - a secret (-s) is asked masked (zz-prompt -s), never logged, and written
#     only to owner-only files (zz-prompt -c offers to chmod 600 on a terminal).
set -e

. zz-colors

# --- arguments
eval "$(
    zz-args "Persist a key=value pair durably" $0 "$@" <<help
        f file      file        Upsert KEY=VALUE into this .env-style file
        p name      profile     Export KEY=VALUE from <ZZ_PROFILE_DIR>/<profile>.sh
        i question  question    Ask for the value with this prompt (terminal only, else the default is used)
        v default   value_default   Default offered by -i (the stored value, if any, wins)
        s -         secret      The value is a secret: masked prompt, never logged, written only to owner-only files
        q -         quiet       Do not log the write (internal state)
        - key       key         Variable name
        - value     value       Variable value
help
)"

# --- parameters
profile_dir=${ZZ_PROFILE_DIR:-/etc/profile.d}

if [ -z "$key" ]; then
    zz-log e "Usage: zz-persist [-f file] [-p profile] [-s] [-i question [-v default]] <key> [value]"
    exit 1
fi

# A name is letters, digits and underscores, not starting with a digit
# (so a single letter is fine: [A-Za-z_][A-Za-z0-9_]* would demand two).
case "$key" in
"" | [0-9]* | *[!A-Za-z0-9_]*)
    zz-log e "Invalid key name: {Purple $key}"
    exit 1
    ;;
esac

if [ -z "$file" ] && [ -z "$profile" ]; then
    zz-log e "At least one of -f or -p is required"
    exit 1
fi

is_secret=0
[ -n "$secret" ] && is_secret=1

# --- functions

# quote_value <value>: single-quote a value for a sourced file, unless it is
# made of plain characters (keeps the common `export KEY=value` form).
quote_value() {
    local text="$1" # value to write (mandatory)

    case "$text" in
    *[!A-Za-z0-9_./:@%+=,-]*) printf "'%s'" "$(printf '%s' "$text" | sed "s/'/'\\\\''/g")" ;;
    *) printf '%s' "$text" ;;
    esac
}

# read_current <file> <prefix>: last value of a "prefix" line in a file, if
# any; a single-quoted value (written by quote_value) is unquoted.
read_current() {
    local target="$1" # file to read (mandatory)
    local prefix="$2" # line prefix, e.g. "KEY=" (mandatory)
    local line

    [ ! -f "$target" ] && return 0
    line=$(sed -n "s/^$prefix//p" "$target" | tail -n1)
    case "$line" in
    \'*\') printf '%s' "$line" | sed "s/^'//;s/'\$//;s/'\\\\''/'/g" ;;
    *) printf '%s' "$line" ;;
    esac
}

# is_owner_only_mode <file>: a secret may only be written into a file that no
# one but its owner can read.
is_owner_only_mode() {
    local target="$1" # file to test (mandatory)

    case "$(stat -c '%a' "$target" 2>/dev/null)" in
    *00) return 0 ;;
    *) return 1 ;;
    esac
}

# upsert_line <file> <prefix> <value>: upsert "<prefix><value>" in a file: the
# first matching line is replaced, further ones dropped, else the line is
# appended. awk reads both through the environment so no character in the
# value is interpreted.
upsert_line() {
    local target="$1" # file to update (mandatory)
    local prefix="$2" # line prefix (mandatory)
    local text="$3"   # value as it is written (mandatory)
    local tmp

    tmp=$(mktemp)
    P=$prefix V=$text awk '
        BEGIN { p = ENVIRON["P"]; v = ENVIRON["V"] }
        index($0, p) == 1 { if (!done) print p v; done = 1; next }
        { print }
        END { if (!done) print p v }
    ' "$target" >"$tmp"
    # cat, not mv: keeps the target file's owner and mode.
    cat "$tmp" >"$target"
    rm -f "$tmp"
}

# persist_line <file> <prefix> <value>: persist one line to a target.
persist_line() {
    local target="$1" # file to write (mandatory)
    local prefix="$2" # line prefix, e.g. "$key=" (mandatory)
    local text="$3"   # value as it is written (mandatory)

    if [ "$is_secret" = 1 ] && ! is_owner_only_mode "$target"; then
        # On a terminal, offer the fix instead of only refusing.
        if [ -t 0 ] && [ "$(zz-prompt -c yN "$key: $target is not owner-only; chmod 600 it?")" = y ]; then
            chmod 600 "$target"
        else
            zz-log w "$key: {U $target} is not owner-only (mode $(stat -c '%a' "$target" 2>/dev/null)); refusing to persist secret, run {Purple chmod 600 $target} first"
            return
        fi
    fi
    upsert_line "$target" "$prefix" "$text"
    [ -n "$quiet" ] || zz-log i "$key persisted to {U $target}"
}

# --- value: ask when -i, else take the argument
if [ -n "$question" ]; then
    current=$(read_current "$file" "$key=")
    [ -z "$current" ] && [ -n "$profile" ] && current=$(read_current "$profile_dir/$profile.sh" "export $key=")

    default="${current:-$value_default}"

    if [ -n "$current" ]; then
        if [ "$is_secret" = 1 ]; then
            zz-log i "$key already set: {Purple ***}"
        else
            zz-log i "$key already set: {Purple $current}"
        fi
    fi

    # Asked by zz-prompt (masked with -s); off a terminal the default is used.
    if [ -t 0 ]; then
        if [ "$is_secret" = 1 ]; then
            value=$(zz-prompt -s "  ${question}" "$default")
        else
            value=$(zz-prompt "  ${question}" "$default")
        fi
    else
        value="$default"
    fi
fi

# One line per pair: a newline would corrupt the file (and, in a profile, run).
case "${value:-}" in
*'
'*)
    zz-log e "$key: a multi-line value cannot be persisted"
    exit 1
    ;;
esac

# --- env file: always owner-only (it may hold credentials next to plain settings)
if [ -n "$file" ]; then
    [ -e "$file" ] || (umask 077 && touch "$file")
    persist_line "$file" "$key=" "${value:-}"
fi

# --- profile snippet: owner-only for a secret, else every shell must read it
if [ -n "$profile" ]; then
    profile_file="$profile_dir/$profile.sh"
    [ "$is_secret" = 1 ] && umask 077
    if mkdir -p "$profile_dir" 2>/dev/null && touch "$profile_file" 2>/dev/null; then
        persist_line "$profile_file" "export $key=" "$(quote_value "${value:-}")"
    else
        zz-log w "$key: cannot write {U $profile_file}, skipped"
    fi
fi
