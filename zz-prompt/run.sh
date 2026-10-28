#!/bin/sh
# zz-prompt [-s] [-e] [-c choices] <question> [default] — interactive input,
# the one reader behind zz-menu, zz-persist and the git-fix-* confirmations.
# The prompt is written to stderr so stdout carries only the entered value
# (or the default when the user just presses Enter). POSIX read (dash-safe).
# When stdin is not a terminal (e.g. `curl | sh`, where it is the script pipe,
# which never reports end of input while its writer lives) the answer is read
# from /dev/tty if one can be opened; ZZ_PROMPT_TTY=0 turns that off.
#   -s  secret: the answer is not echoed and the default is shown as [***]
#   -e  fail (status 1) when input ends instead of answering with the default
#   ZZ_PROMPT_ANSWERS=<file>  scripted answers, one line per prompt (an empty line is a bare Enter;
#       an exhausted file is end of input): the same for zz-menu, which asks through zz-prompt
#   -c  choices, e.g. Yn: accept one of these letters (any case), re-ask on
#       anything else; the answer is always printed lowercased
#   -k  single key: on a terminal the answer is one keypress, no Enter needed
#       (-c implies it); anywhere else a normal line is read
# The prompt line is "<mark> <question> <hint> ", both set by the environment:
#   ZZ_PROMPT_MARK  leading mark (default #)
#   ZZ_PROMPT_HINT  printf format of the hint, given the default or the choices
#                   (default [%s]; empty: no hint)

. zz-colors

# --- arguments
eval "$(
    zz-args "Interactive free-form input" "$0" "$@" <<help
s - secret Secret: masked input, default shown as ***
e - eof_fail Exit 1 when input ends (no answer at all)
c choices choices Accepted single letters (uppercase = default), e.g. Yn
k - key_flag Single keypress on a terminal, no Enter needed (-c implies it)
- question question Question to ask
- default default Value used when the user just presses Enter
help
)"

# --- parameters
shown=$default
[ -z "$secret" ] || shown=***
hint=${ZZ_PROMPT_HINT-[%s]}
if [ -n "$choices" ]; then
    default=$(printf '%s' "$choices" | tr -dc 'A-Z' | tr '[:upper:]' '[:lower:]')
    shown=$choices
fi
# No default and no choices: nothing to show.
[ -n "$default$choices" ] || hint=

# --- functions

# has_tty: a controlling terminal can be read (and is not disabled).
has_tty() { [ "${ZZ_PROMPT_TTY:-1}" != 0 ] && (: </dev/tty) 2>/dev/null; }

# read_key <tty>: read one keypress from <tty> into $value, no Enter needed (Enter
# or Ctrl-D give an empty value, Ctrl-D also sets $eof), and echo it so the
# line looks as if it was typed. Raw mode is restored even when the read fails.
read_key() {
    local saved
    eof=
    saved=$(stty -g <"$1" 2>/dev/null) || saved=
    [ -z "$saved" ] || stty -icanon -echo min 1 time 0 <"$1" 2>/dev/null
    value=$(dd bs=1 count=1 <"$1" 2>/dev/null)
    case $value in
    "$(printf '\004')") value= eof=1 ;;
    # An arrow key sends ESC plus two more bytes: swallow them, they are not answers.
    "$(printf '\033')")
        stty min 0 time 1 <"$1" 2>/dev/null
        dd bs=1 count=2 <"$1" >/dev/null 2>&1
        value=?
        ;;
    esac
    [ -z "$saved" ] || stty "$saved" <"$1" 2>/dev/null
    printf '%s\n' "$value" >&2
}

# Ask once and read one line into $value ($eof set when input ended). A
# secret is read with echo off, restored even when read fails; echo is
# switched on the terminal when stdin is not one but the answer may come
# from it.
read_answer() {
    local tty_in=
    # shellcheck disable=SC2059 # the hint format is the caller's to choose
    printf '%b' "${BBlue}${ZZ_PROMPT_MARK:-#}${None}${question:+ $question}${hint:+ ${BBlue}$(printf "$hint" "$shown")${None}} " >&2
    if [ -n "${ZZ_PROMPT_ANSWERS:-}" ]; then
        eof=
        if [ -s "$ZZ_PROMPT_ANSWERS" ]; then
            value=$(head -n1 "$ZZ_PROMPT_ANSWERS")
            sed -i 1d "$ZZ_PROMPT_ANSWERS"
        else
            value=
            eof=1
        fi
        echo >&2
        return 0
    fi
    [ -t 0 ] || ! has_tty || tty_in=/dev/tty
    # A terminal and a single-key question: one keypress is the answer.
    if [ -z "$secret" ] && [ -n "$key_flag$choices" ] && { [ -n "$tty_in" ] || [ -t 0 ]; }; then
        read_key "${tty_in:-/dev/fd/0}"
        return 0
    fi
    stty_orig=
    if [ -n "$secret" ]; then
        stty_orig=$(stty -g <"${tty_in:-/dev/fd/0}" 2>/dev/null) || stty_orig=
        [ -z "$stty_orig" ] || stty -echo <"${tty_in:-/dev/fd/0}" 2>/dev/null
    fi
    eof=
    if [ -n "$tty_in" ]; then
        read -r value <"$tty_in" || eof=1
    else
        read -r value || eof=1
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
