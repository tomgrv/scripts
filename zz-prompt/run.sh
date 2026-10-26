#!/bin/sh
# zz-prompt [-s] [-e] [-c choices] <question> [default] — interactive input,
# the one reader behind zz-menu, zz-persist and the git-fix-* confirmations.
# The prompt is written to stderr so stdout carries only the entered value
# (or the default when the user just presses Enter). POSIX read (dash-safe).
# When stdin ends (e.g. `curl | sh`, where it is the script pipe) the answer is
# read from /dev/tty if one can be opened; ZZ_PROMPT_TTY=0 turns that off.
#   -s  secret: the answer is not echoed and the default is shown as [***]
#   -e  fail (status 1) when input ends instead of answering with the default
#   -c  choices, e.g. Yn: accept one of these letters (any case), re-ask on
#       anything else; the answer is always printed lowercased

. zz-colors

# --- arguments
eval "$(
    zz-args "Interactive free-form input" "$0" "$@" <<help
s - secret Secret: masked input, default shown as ***
e - eof_fail Exit 1 when input ends (no answer at all)
c choices choices Accepted single letters (uppercase = default), e.g. Yn
- question question Question to ask
- default default Value used when the user just presses Enter
help
)"

# --- parameters
shown=$default
[ -z "$secret" ] || shown=***
if [ -n "$choices" ]; then
    default=$(printf '%s' "$choices" | tr -dc 'A-Z' | tr '[:upper:]' '[:lower:]')
    shown=$choices
fi

# --- functions

# has_tty: a controlling terminal can be read (and is not disabled).
has_tty() { [ "${ZZ_PROMPT_TTY:-1}" != 0 ] && (: </dev/tty) 2>/dev/null; }

# Ask once and read one line into $value ($eof set when input ended). A
# secret is read with echo off, restored even when read fails; echo is
# switched on the terminal when stdin is not one but the answer may come
# from it.
read_answer() {
    local tty_in=
    if [ -n "$default" ] || [ -n "$choices" ]; then
        printf '%b' "${BBlue}#${None} $question ${BBlue}[$shown]${None} " >&2
    else
        printf '%b' "${BBlue}#${None} $question " >&2
    fi
    [ -t 0 ] || ! has_tty || tty_in=/dev/tty
    stty_orig=
    if [ -n "$secret" ]; then
        stty_orig=$(stty -g <"${tty_in:-/dev/fd/0}" 2>/dev/null) || stty_orig=
        [ -z "$stty_orig" ] || stty -echo <"${tty_in:-/dev/fd/0}" 2>/dev/null
    fi
    eof=
    read -r value || eof=1
    if [ -n "$eof" ] && [ -n "$tty_in" ]; then
        eof=
        read -r value <"$tty_in" || eof=1
    fi
    if [ -n "$stty_orig" ]; then
        stty "$stty_orig" <"${tty_in:-/dev/fd/0}" 2>/dev/null
        echo >&2
    fi
}

# --- answer
while :; do
    read_answer
    [ -z "$eof" ] || [ -z "$eof_fail" ] || [ -n "$value" ] || exit 1
    [ -n "$choices" ] || break
    [ -n "$value" ] && [ "${#value}" -eq 1 ] || {
        # Enter (or end of input) takes the default; longer input is invalid.
        [ -z "$value" ] && break
        zz-log w "Please enter a valid option from [${choices}] (default: ${default}):"
        continue
    }
    lower=$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')
    case $(printf '%s' "$choices" | tr '[:upper:]' '[:lower:]') in
    *"$lower"*)
        value=$lower
        break
        ;;
    esac
    zz-log w "Please enter a valid option from [${choices}] (default: ${default}):"
done

[ -z "$value" ] && value=$default
printf '%s\n' "$value"
