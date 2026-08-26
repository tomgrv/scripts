#!/bin/sh
# zz_wrap — input/output core library.
#
# Source it once from any script in this repo:
#   . zz_wrap
#
# It provides, as shell functions/vars (no subprocess overhead):
#   - Colors:  $Red $Green $Yellow $Blue ... $None $End (+ Bold/Underline variants)
#   - zz_log <level> <msg...>          colored, leveled log line on stderr
#   - zz_esc <value>                   escape a value for safe re-embedding in '...'
#   - zz_args <title> <caller> <<-help ...   parse args, eval-print var assignments
#   - zz_prompt <question> [default]   interactive free-form input (stdout: value)
#   - zz_ask <options> <question...>   interactive single-char confirm (stdout: choice)
#   - zz_input [file]                  read from arg (literal or file) or stdin
#   - zz_bindir [-t target]            resolve/create a writable bin dir on PATH
#
# Guard against re-sourcing (cheap, and some callers `. zz_wrap` per-function use).
[ -n "${ZZ_WRAP_LOADED:-}" ] && return 0 2>/dev/null || true
ZZ_WRAP_LOADED=1

### Colors ###

None='\033[0m'
End='\033[0m\r'

Black='\033[0;30m'; Red='\033[0;31m'; Green='\033[0;32m'; Yellow='\033[0;33m'
Blue='\033[0;34m'; Purple='\033[0;35m'; Cyan='\033[0;36m'; White='\033[0;37m'

BBlack='\033[1;30m'; BRed='\033[1;31m'; BGreen='\033[1;32m'; BYellow='\033[1;33m'
BBlue='\033[1;34m'; BPurple='\033[1;35m'; BCyan='\033[1;36m'; BWhite='\033[1;37m'

UBlack='\033[4;30m'; URed='\033[4;31m'; UGreen='\033[4;32m'; UYellow='\033[4;33m'
UBlue='\033[4;34m'; UPurple='\033[4;35m'; UCyan='\033[4;36m'; UWhite='\033[4;37m'

### zz_esc — escape a raw value for safe re-embedding inside single quotes ###
# Without this, a value containing a single quote (e.g. `'; rm -rf / #`)
# would break out of the quoting in the var='...' assignments zz_args emits.
zz_esc() {
    printf '%s' "$1" | sed "s/'/'\\\\''/g"
}

### zz_log <level> <msg...> — colored, leveled log line on stderr ###
zz_log() {
    lvl="$1" && shift
    case $lvl in
    i*) picto="{BBlue →} "; base="White" ;;
    w*) picto="{BYellow !} "; base="Yellow" ;;
    e*) picto="{BRed ✕} "; base="Red" ;;
    s*) picto="{Green ✔} "; base="Green" ;;
    -) picto="  "; base="White" ;;
    *) picto="$lvl "; base="White" ;;
    esac

    eval "$(
        echo "printf '%b\n' \"$picto$*\${End}\"" | sed -E "s/\{([A-Z]) /{\1${base} /g;s/\{([a-zA-Z]+) ([^}]*)\}/\${\1}\2\${${base}}/g; s/\r//g; "
    )" >&2
}

### zz_args <title> <caller> <<-help ... help — parse args, eval-print assignments ###
# See individual scripts for usage; behavior matches the historical zz_args.
zz_args() {
    count="0"; value=""; argname=""; varname=""; varnames=""; argnames=""
    datatype=""; help=""; invert=""

    if test $# -lt 1; then
        echo "Usage: $(basename $0) <title> <caller> <<-help
        ...
        <argname> <datatype> <varname> <help>
        ...
        help" >&2
        echo "With <argname>:
    x   for flags x with value (e.g., -f value, -h being reserved for help)
    -   for sequential arguments in the order defined, without flags
    +   to capture all remaining arguments as a single variable with spaces as separators
    &   to capture all remaining arguments as a multiple-line variable
    #   to capture all remaining arguments with escaped spaces" >&2
        return 1
    fi

    title=$1 && shift
    caller=$1 && shift

    while read argname datatype varname help; do
        if [ "$datatype" = "-" ]; then name=""; else name="<$datatype>"; fi

        if [ "$argname" = "-" ]; then
            line="<$datatype>"
            helpinfo="$helpinfo\n\t$(printf '%-12s : %s' "$name" "$help")"
        elif [ "$argname" = "+" ]; then
            line="<$datatype...>"
            helpinfo="$helpinfo\n\t$(printf '%-12s : %s' "$name" "$help")"
        elif [ "$argname" = "&" ]; then
            line="<$datatype...>>"
            helpinfo="$helpinfo\n\t$(printf '%-12s : %s' "$name" "$help")"
        elif [ "$argname" = "#" ]; then
            line="<$datatype...>>"
            helpinfo="$helpinfo\n\t$(printf '%-12s : %s' "$name" "$help")"
        else
            if [ "$datatype" = "-" ]; then
                line="[-$argname]"; argnames="$argnames$argname"
            else
                line="[-$argname <$datatype>]"; argnames="$argnames$argname:"
            fi
            helpinfo="$helpinfo\n\t$(printf '%-3s %-8s : %s' "-$argname" "$name" "$help")"
        fi

        varnames="$varnames\n$argname\t$varname"
        lineinfo="$lineinfo $line"
        [ "$argname" = "+" ] && break
    done

    OPTIND=1
    while getopts :$argnames value "$@"; do
        if [ "$value" = "?" ]; then break; fi
        naming=$(printf '%b' "$varnames" | grep -E "^$value" | cut -f2)
        if [ -n "$OPTARG" ]; then
            echo "$naming='$(zz_esc "$OPTARG")'"
        else
            echo "$naming=-$value"
        fi
    done

    if [ "$OPTARG" = "h" ] || [ "$OPTARG" = "help" ]; then
        (
            echo "${End}"
            echo "$title${End}"
            echo "${End}"
            echo "Usage: ${Yellow}$(basename $caller)$lineinfo${None}; Use ${Yellow}-h${None} for more information.${End}"
            echo "$helpinfo${End}"
            echo "${End}"
        ) >&2
        echo "exit 1"
        return 1
    elif [ "$OPTARG" = "@" ]; then
        echo "Stop processing arguments !${End}" >&2
    else
        shift $(expr "$OPTIND" - 1)

        for arg in $(printf '%b' "$varnames" | grep -E "^-" | cut -f2); do
            if [ "$#" -gt "0" ]; then
                echo "$arg='$(zz_esc "$1")'" && shift 1
            fi
        done

        for arg in $(printf '%b' "$varnames" | grep -E "^&" | cut -f2); do
            lines=""
            while [ "$#" -gt "0" ]; do
                piece=$(zz_esc "$1")
                if [ -z "$lines" ]; then lines="$piece"; else lines="$lines\\\\n$piece"; fi
                shift 1
            done
            echo "$arg='$lines'"
        done

        for arg in $(printf '%b' "$varnames" | grep -E "^#" | cut -f2); do
            lines=""
            while [ "$#" -gt "0" ]; do
                piece=$(zz_esc "$1" | sed 's/ /\\ /g')
                if [ -z "$lines" ]; then lines="$piece"; else lines="$lines $piece"; fi
                shift 1
            done
            echo "$arg='$lines'"
        done

        for arg in $(printf '%b' "$varnames" | grep -E "^\+" | cut -f2); do
            if [ "$#" -gt "0" ]; then
                value=""
                for a in "$@"; do
                    piece=$(zz_esc "$a")
                    if [ -z "$value" ]; then value="$piece"; else value="$value $piece"; fi
                done
                echo "$arg='$value'"
                shift $#
            fi
        done
    fi
}

### zz_prompt <question> [default] — interactive free-form input ###
# Prompt is written to stderr so stdout carries only the entered value.
zz_prompt() {
    prompt=$1
    default=$2

    if [ -n "$default" ]; then
        printf '%b' "${BBlue}#${None} $prompt ${BBlue}[$default]${None} " >&2
    else
        printf '%b' "${BBlue}#${None} $prompt " >&2
    fi

    read -r value
    [ -z "$value" ] && value=$default
    printf '%s\n' "$value"
}

### zz_ask <options> <question...> — interactive single-char confirm ###
# <options> e.g. "Yn" — uppercase letter is the default. Prints the chosen
# option (lowercased) to stdout.
zz_ask() {
    default=$(echo "$1" | grep -oP '[A-Z]' | tr '[:upper:]' '[:lower:]')
    options=$1
    shift

    echo "${BBlue}#${None} $* ${BBlue}[${options}]${End}"

    while true; do
        read -r confirm

        if [ -z "$confirm" ]; then
            echo "$default"
            break
        fi

        if echo "$options" | grep -q -i "$confirm"; then
            echo "$confirm"
            break
        fi

        zz_log w "Please enter a valid option from [${options}] (default: ${default}):"
    done | grep -q -i "$default"
}

### zz_input [input] — read from arg (literal string or file path) or stdin ###
zz_input() {
    input="$1"

    if [ -n "$input" ]; then
        if [ -f "$input" ]; then
            zz_log - "Reading from file: $input"
            cat "$input"
        else
            echo "$input"
        fi
    else
        cat -
    fi
}

### zz_bindir [-t target] — resolve (and create if needed) a writable bin
### directory on PATH, exporting PATH to include it. Prints the chosen
### directory on stdout. Shared by install/link flows (zz_use, install-feature).
zz_bindir() {
    _forced_target=""
    while getopts :t: opt "$@"; do
        case "$opt" in
        t) _forced_target="$OPTARG" ;;
        esac
    done

    _candidates=""
    _creatable=""

    _add_candidate() {
        _c="$1"; _mk="${2:-0}"
        [ -n "$_c" ] || return 0
        case ":$_candidates:" in
        *":$_c:"*) ;;
        *)
            _candidates="${_candidates:+$_candidates:}$_c"
            [ "$_mk" = "1" ] && _creatable="${_creatable:+$_creatable:}$_c"
            ;;
        esac
    }

    _add_candidate "${INSTALL_BIN_DIR:-/usr/local/bin}" 1
    [ -n "$HOME" ] && _add_candidate "$HOME/.local/bin" 1

    _old_ifs=$IFS
    IFS=':'
    for _dir in $PATH; do
        case "$_dir" in
        "" | "." | "$PWD" | */node_modules/.bin) continue ;;
        esac
        _add_candidate "$_dir"
    done
    IFS=$_old_ifs
    [ -n "$_forced_target" ] && _add_candidate "$_forced_target/bin" 1

    _link_dir=""
    _old_ifs=$IFS
    IFS=':'
    for _c in $_candidates; do
        if [ -d "$_c" ] && [ -w "$_c" ] && [ -x "$_c" ]; then
            _link_dir="$_c"
            break
        fi
    done

    if [ -z "$_link_dir" ]; then
        for _c in $_creatable; do
            mkdir -p "$_c" 2>/dev/null || true
            if [ -d "$_c" ] && [ -w "$_c" ] && [ -x "$_c" ]; then
                _link_dir="$_c"
                break
            fi
        done
    fi
    IFS=$_old_ifs

    [ -n "$_link_dir" ] || { zz_log e "No writable bin directory found"; return 1; }

    case ":$PATH:" in
    *":$_link_dir:"*) ;;
    *) export PATH="$_link_dir:$PATH" ;;
    esac

    printf '%s\n' "$_link_dir"
}
