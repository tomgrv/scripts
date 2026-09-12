#!/bin/sh
# zz_persist — upsert a KEY=VALUE pair into an env-style file and/or an
# /etc/profile.d/<profile>.sh snippet, so the value survives a new shell
# or a script re-run.
set -e

zz_use zz_colors zz_args
. zz_colors

eval $(
    zz_args "Persist a key=value pair durably" $0 "$@" <<-help
        f file      file        Upsert KEY=VALUE into this .env-style file
        p name      profile     Export KEY=VALUE from /etc/profile.d/<profile>.sh
        i question  question    Ask interactively for the value with this prompt (terminal only)
        v default   value_default   Default value for a non-secret interactive prompt
        s default   secret_default  Default value for a secret interactive prompt (masked)
        - key       key         Variable name
        - value     value       Variable value
help
)

if [ -z "$key" ]; then
    zz_log e "Usage: zz_persist [-f file] [-p profile] [-i question [-v default|-s default]] <key> [value]"
    exit 1
fi

case "$key" in
[A-Za-z_][A-Za-z0-9_]*) ;;
*)
    zz_log e "Invalid key name: {Purple $key}"
    exit 1
    ;;
esac

if [ -z "$file" ] && [ -z "$profile" ]; then
    zz_log e "At least one of -f or -p is required"
    exit 1
fi

# Read an existing KEY= or export KEY= line's value from a file, if any.
read_current() {
    [ -f "$1" ] && sed -n "s/^$2//p" "$1" | tail -n1
}

is_secret=0

if [ -n "$question" ]; then
    current=$(read_current "$file" "$key=")
    [ -z "$current" ] && [ -n "$profile" ] && current=$(read_current "/etc/profile.d/$profile.sh" "export $key=")

    [ -n "$secret_default" ] && is_secret=1
    [ -n "$current" ] && is_secret=1

    default="${current:-${value_default:-$secret_default}}"

    if [ -n "$current" ]; then
        if [ "$is_secret" = 1 ]; then
            zz_log i "$key already set: {Purple ***}"
        else
            zz_log i "$key already set: {Purple $current}"
        fi
    fi

    if [ -t 0 ]; then
        prompt="  ${question}"
        if [ -n "$default" ]; then
            if [ "$is_secret" = 1 ]; then
                prompt="${prompt} [***]: "
            else
                prompt="${prompt} [${default}]: "
            fi
        fi
        printf '%s' "$prompt"
        if [ "$is_secret" = 1 ]; then
            stty_orig=$(stty -g 2>/dev/null) || stty_orig=""
            [ -n "$stty_orig" ] && stty -echo 2>/dev/null
            read -r answer
            [ -n "$stty_orig" ] && stty "$stty_orig" 2>/dev/null
            echo
        else
            read -r answer
        fi
        value="${answer:-$default}"
    else
        value="$default"
    fi
fi

escaped_value=$(printf '%s' "${value:-}" | sed -e 's/[\\&|]/\\&/g')

# A secret may only be written into a file that no one but its owner can read.
is_owner_only_mode() {
    case "$(stat -c '%a' "$1" 2>/dev/null)" in
    *00) return 0 ;;
    *) return 1 ;;
    esac
}

# Upsert a "prefix<value>" line into a file, refusing to write a secret
# unless the file is owner-only. $1=target file $2=line prefix (e.g. "$key=")
persist_line() {
    target="$1"
    prefix="$2"

    if [ "$is_secret" = 1 ] && ! is_owner_only_mode "$target"; then
        zz_log w "$key: {U $target} is not owner-only (mode $(stat -c '%a' "$target" 2>/dev/null)); refusing to persist secret, run {Purple chmod 600 $target} first"
        return
    fi

    if grep -q "^$prefix" "$target" 2>/dev/null; then
        sed -i "s|^$prefix.*|$prefix$escaped_value|" "$target"
    else
        echo "$prefix$value" >>"$target"
    fi
    zz_log i "$key persisted to {U $target}"
}

if [ -n "$file" ]; then
    touch "$file"
    persist_line "$file" "$key="
fi

if [ -n "$profile" ]; then
    profile_file="/etc/profile.d/$profile.sh"
    if mkdir -p /etc/profile.d 2>/dev/null && touch "$profile_file" 2>/dev/null; then
        persist_line "$profile_file" "export $key="
    else
        zz_log w "$key: cannot write {U $profile_file}, skipped"
    fi
fi
