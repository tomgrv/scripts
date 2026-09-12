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

is_secret=0

if [ -n "$question" ]; then
    current=""
    [ -n "$file" ] && [ -f "$file" ] && current=$(sed -n "s/^$key=//p" "$file" | tail -n1)
    if [ -z "$current" ] && [ -n "$profile" ] && [ -f "/etc/profile.d/$profile.sh" ]; then
        current=$(sed -n "s/^export $key=//p" "/etc/profile.d/$profile.sh" | tail -n1)
    fi

    [ -n "$secret_default" ] && is_secret=1

    default="${value_default:-$secret_default}"

    if [ -n "$current" ]; then
        is_secret=1
        if [ -n "$secret_default" ]; then
            zz_log i "$key already set: {Purple ***}"
        else
            zz_log i "$key already set: {Purple $current}"
        fi
        default="$current"
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
        [ -z "$answer" ] && answer="$default"
        value="$answer"
    else
        value="$default"
    fi
fi

escaped_value=$(printf '%s' "${value:-}" | sed -e 's/[\\&|]/\\&/g')

is_owner_only_mode() {
    case "$(stat -c '%a' "$1" 2>/dev/null)" in
    *00) return 0 ;;
    *) return 1 ;;
    esac
}

if [ -n "$file" ]; then
    touch "$file"
    if [ "$is_secret" = 1 ] && ! is_owner_only_mode "$file"; then
        zz_log w "$key: {U $file} is not owner-only (mode $(stat -c '%a' "$file" 2>/dev/null)); refusing to persist secret, run {Purple chmod 600 $file} first"
    else
        if grep -q "^$key=" "$file"; then
            sed -i "s|^$key=.*|$key=$escaped_value|" "$file"
        else
            echo "$key=$value" >>"$file"
        fi
        zz_log i "$key persisted to {U $file}"
    fi
fi

if [ -n "$profile" ]; then
    profile_file="/etc/profile.d/$profile.sh"
    if mkdir -p /etc/profile.d 2>/dev/null && touch "$profile_file" 2>/dev/null; then
        if [ "$is_secret" = 1 ] && ! is_owner_only_mode "$profile_file"; then
            zz_log w "$key: {U $profile_file} is not owner-only (mode $(stat -c '%a' "$profile_file" 2>/dev/null)); refusing to persist secret, run {Purple chmod 600 $profile_file} first"
        else
            if grep -q "^export $key=" "$profile_file" 2>/dev/null; then
                sed -i "s|^export $key=.*|export $key=$escaped_value|" "$profile_file"
            else
                echo "export $key=$value" >>"$profile_file"
            fi
            zz_log i "$key persisted to {U $profile_file}"
        fi
    else
        zz_log w "$key: cannot write {U $profile_file}, skipped"
    fi
fi
