#!/bin/sh
# zz-persist — upsert a KEY=VALUE pair into an env-style file and/or an
# <ZZ_PROFILE_DIR>/<profile>.sh snippet (default /etc/profile.d), so the value
# survives a new shell or a script re-run.
#   - the env file holds the value literally (read, never sourced);
#   - the profile snippet is sourced by shells, so a value with anything but
#     plain characters is single-quoted there and cannot run code;
#   - -r prints the stored value, -x the export lines of several keys at once,
#     -u removes the key, -g generates a value
#     (kept once stored) and prints it, so a caller needs no random/read helper;
#   - a secret (-s) is asked masked (zz-prompt -s), never logged, and written
#     only to owner-only files (zz-prompt -c offers to chmod 600 on a terminal);
#   - -S is a secret in the shared secrets file ($ZZ_SECRETS_FILE, default
#     /root/.zz-secrets.env), so a caller names neither the file nor -s;
#   - -o prints the value (given, else stored) and never blanks a stored one.
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
        g length    generate    Value of this many random letters/digits when none is given or stored (printed on stdout)
        t type      gen_type    With -g: the characters, alnum (default) or hex
        S -         store_secret    A secret in the shared secrets file: implies -s, and -f when none is given
        o -         print_value Print the value (given, else stored); a stored value is kept when none is given
        r -         show        Print the stored value of the key, else the -v default (no write)
        u -         remove      Remove the key, or each key of a quoted list (no write)
        l -         line        The key is a whole line: append it to the file unless it is already there
        x -         exports     The key is a list of names: print an export line for each one that is stored (no write)
        - key       key         Variable name
        - value     value       Variable value
help
)"

# --- parameters
profile_dir=${ZZ_PROFILE_DIR:-/etc/profile.d}
if [ -n "$store_secret" ]; then
    secret=1
    [ -n "$file" ] || file=${ZZ_SECRETS_FILE:-/root/.zz-secrets.env}
fi

if [ -z "$key" ]; then
    zz-log e "Usage: zz-persist [-f file] [-p profile] [-s] [-i question [-v default]] [-g length] [-r | -u] <key> [value]"
    exit 1
fi

# -l: the "key" is a whole line (an export, an authorized key...), added once.
if [ -n "$line" ]; then
    [ -n "$file" ] || {
        zz-log e "-l needs -f <file>"
        exit 1
    }
    [ -e "$file" ] || touch "$file"
    grep -qxF -- "$key" "$file" || printf '%s\n' "$key" >>"$file"
    exit 0
fi

# A name is letters, digits and underscores, not starting with a digit
# (so a single letter is fine: [A-Za-z_][A-Za-z0-9_]* would demand two).
[ -n "$exports$remove" ] || case "$key" in
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

# remove_line <file> <prefix>: drop every "<prefix>..." line from a file.
remove_line() {
    local target="$1" # file to update (mandatory)
    local prefix="$2" # line prefix (mandatory)
    local tmp

    tmp=$(mktemp)
    P=$prefix awk 'BEGIN { p = ENVIRON["P"] } index($0, p) != 1 { print }' "$target" >"$tmp"
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
        if zz-interactive && [ "$(zz-prompt -c yN "$key: $target is not owner-only; chmod 600 it?")" = y ]; then
            chmod 600 "$target"
        else
            zz-log w "$key: {U $target} is not owner-only (mode $(stat -c '%a' "$target" 2>/dev/null)); refusing to persist secret, run {Purple chmod 600 $target} first"
            return
        fi
    fi
    upsert_line "$target" "$prefix" "$text"
    [ -n "$quiet" ] || zz-log i "$key persisted to {U $target}"
}

# -x: the "key" is a space-separated list of names; one process reads them all.
if [ -n "$exports" ]; then
    [ -n "$file" ] || [ -n "$profile" ] || {
        zz-log e "At least one of -f or -p is required"
        exit 1
    }
    for name in $key; do
        case "$name" in
        [0-9]* | *[!A-Za-z0-9_]*)
            zz-log e "Invalid key name: {Purple $name}"
            exit 1
            ;;
        esac
    done
    # One awk pass over the file (and the profile snippet, for what the file lacks): the last
    # "NAME=value" line wins, a quoted value is unquoted as read_current does, and the export
    # line is quoted for eval. \047 is a single quote.
    profile_file=
    [ -z "$profile" ] || profile_file=$profile_dir/$profile.sh
    set --
    [ ! -f "$file" ] || set -- "$file"
    [ -z "$profile_file" ] || [ ! -f "$profile_file" ] || set -- "$@" "$profile_file"
    NAMES=$key PROFILE_FILE=$profile_file awk '
        function squote(v,   out, i) {   # a single quote becomes the four characters '\'' for eval
            while ((i = index(v, "\047")) > 0) { out = out substr(v, 1, i - 1) "\047\\\047\047"; v = substr(v, i + 1) }
            return out v
        }
        function unquote(v) {
            if (v ~ /^\047.*\047$/) { v = substr(v, 2, length(v) - 2); gsub(/\047\\\047\047/, "\047", v) }
            return v
        }
        BEGIN { n = split(ENVIRON["NAMES"], order, " "); for (i = 1; i <= n; i++) want[order[i]] = 1 }
        { line = $0; pre = (FILENAME == ENVIRON["PROFILE_FILE"] && ENVIRON["PROFILE_FILE"] != "") ? 1 : 0
          if (pre) { if (substr(line, 1, 7) != "export ") next; line = substr(line, 8) }
          eq = index(line, "="); if (eq < 2) next
          k = substr(line, 1, eq - 1); if (k in want) val[pre, k] = substr(line, eq + 1) }
        END { for (i = 1; i <= n; i++) {
                  v = unquote(val[0, order[i]]); if (v == "") v = unquote(val[1, order[i]])
                  if (v != "") printf "export %s=\047%s\047\n", order[i], squote(v) } }
    ' "$@" /dev/null
    exit 0
fi

# --- -r: print the stored value; -u: remove the key
if [ -n "$show" ]; then
    current=$(read_current "$file" "$key=")
    [ -z "$current" ] && [ -n "$profile" ] && current=$(read_current "$profile_dir/$profile.sh" "export $key=")
    printf '%s' "${current:-$value_default}"
    exit 0
fi

if [ -n "$remove" ]; then
    for name in $key; do
        case "$name" in
        "" | [0-9]* | *[!A-Za-z0-9_]*)
            zz-log e "Invalid key name: {Purple $name}"
            exit 1
            ;;
        esac
        [ -z "$file" ] || { [ ! -f "$file" ] || remove_line "$file" "$name="; }
        [ -z "$profile" ] || { [ ! -f "$profile_dir/$profile.sh" ] || remove_line "$profile_dir/$profile.sh" "export $name="; }
    done
    [ -n "$quiet" ] || zz-log i "$key removed"
    exit 0
fi

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
    if zz-interactive; then
        if [ "$is_secret" = 1 ]; then
            value=$(zz-prompt -s "  ${question}" "$default")
        else
            value=$(zz-prompt "  ${question}" "$default")
        fi
    else
        value="$default"
    fi
fi

# -g/-o: no value given or asked: keep the stored one; -g then generates one (letters and digits, or hex)
if { [ -n "$generate" ] || [ -n "$print_value" ]; } && [ -z "${value:-}" ]; then
    value=$(read_current "$file" "$key=")
    [ -z "$value" ] && [ -n "$profile" ] && value=$(read_current "$profile_dir/$profile.sh" "export $key=")
    if [ -z "$value" ] && [ -n "$generate" ]; then
        # || true: head closing early sends tr/od a SIGPIPE that set -e would report.
        case "${gen_type:-alnum}" in
        hex) value=$(od -An -tx1 /dev/urandom | tr -d ' \n' | head -c "$generate" || true) ;;
        alnum) value=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c "$generate" || true) ;;
        *)
            zz-log e "-t is alnum or hex (got '$gen_type')"
            exit 1
            ;;
        esac
    fi
    # nothing given, stored or generated: nothing to write, and nothing to blank
    [ -n "$value" ] || exit 0
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

# --- -g/-o: the value (new or kept) is the caller's result
[ -z "$generate$print_value" ] || printf '%s' "$value"
