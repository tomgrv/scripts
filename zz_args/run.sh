#!/bin/sh
# zz_args <title> <caller> <<-help ... help — parse "$@" per the heredoc spec,
# print `var=value` assignments for the caller to `eval`. See any functional
# script (e.g. merge-json) for a usage example.

. zz_colors

# Escape a raw value so it can be safely re-embedded inside single quotes
# in the `var='...'` assignments this script emits for the caller's `eval`.
# Without this, a value containing a single quote (e.g. `'; rm -rf / #`)
# would break out of the quoting and be executed by the caller's eval.
zz_esc() {
    printf '%s' "$1" | sed "s/'/'\\\\''/g"
}

count="0"
value=""
argname=""
varname=""
varnames=""
argnames=""
datatype=""
help=""
invert=""

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

    if [ "$datatype" = "-" ]; then
        name=""
    else
        name="<$datatype>"
    fi

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
            line="[-$argname]"
            argnames="$argnames$argname"
        else
            line="[-$argname <$datatype>]"
            argnames="$argnames$argname:"
        fi

        helpinfo="$helpinfo\n\t$(printf '%-3s %-8s : %s' "-$argname" "$name" "$help")"
    fi

    varnames="$varnames\n$argname\t$varname"
    lineinfo="$lineinfo $line"

    [ "$argname" = "+" ] && break
done

# Parse the command-line arguments (OPTIND is a plain shell var, not
# function-local: reset it so a value inherited from the environment can't
# make getopts start mid-way through "$@")
OPTIND=1
while getopts :$argnames value "$@"; do
    if [ "$value" = "?" ]; then
        break
    fi

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
    exit 1

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
            if [ -z "$lines" ]; then
                lines="$piece"
            else
                lines="$lines\\\\n$piece"
            fi
            shift 1
        done
        echo "$arg='$lines'"
    done

    for arg in $(printf '%b' "$varnames" | grep -E "^#" | cut -f2); do
        lines=""
        while [ "$#" -gt "0" ]; do
            piece=$(zz_esc "$1" | sed 's/ /\\ /g')
            if [ -z "$lines" ]; then
                lines="$piece"
            else
                lines="$lines $piece"
            fi
            shift 1
        done
        echo "$arg='$lines'"
    done

    for arg in $(printf '%b' "$varnames" | grep -E "^\+" | cut -f2); do
        if [ "$#" -gt "0" ]; then
            value=""
            for a in "$@"; do
                piece=$(zz_esc "$a")
                if [ -z "$value" ]; then
                    value="$piece"
                else
                    value="$value $piece"
                fi
            done
            echo "$arg='$value'"
            shift $#
        fi
    done

fi
