#!/bin/sh
# zz-log <level> <msg...> — colored, leveled log line on stderr.
# level: i(nfo) n(otice) w(arning) e(rror) s(uccess) d(ebug) -(plain).
# d(ebug) is silent unless ZZ_DEBUG is set.
#
# Script log vs operation output:
#   - a script's own messages (i n w e s d -) get the level pictogram and, when
#     ZZ_LOG_STEP is set, a "[step]" tag naming the current step;
#   - o(utput) is what a command it ran printed (git, an installer...): each
#     line, taken from the message or from stdin when none is given, is dimmed
#     behind a "│" gutter, with no pictogram and no step tag. Pipe it:
#       cmd 2>&1 | zz-log o        (or keep the status: out=$(cmd 2>&1) || rc=$?)
#
# Env: ZZ_LOG_STEP (current step label, exported by the caller so its children
# inherit it), ZZ_LOG_INDENT (spaces to indent every line; a caller nesting a
# child script raises it by 2 for that child).

. zz-colors

lvl="$1" && shift

indent=$(printf '%*s' "${ZZ_LOG_INDENT:-0}" '')
step=""
[ -z "${ZZ_LOG_STEP:-}" ] || step="[$ZZ_LOG_STEP] "

# Operation output: dimmed, gutter-prefixed, one line at a time.
case $lvl in
o*)
    {
        if [ "$#" -gt 0 ]; then printf '%s\n' "$*"; else cat; fi
    } | while IFS= read -r line || [ -n "$line" ]; do
        printf '%b%s%b\n' "$indent${BBlack}│ " "$line" "${End}" >&2
    done
    exit 0
    ;;
esac

gha=""

case $lvl in
d*)
    [ -n "${ZZ_DEBUG:-}" ] || exit 0
    picto="{BBlack ·} "
    base="BBlack"
    ;;
i*)
    picto="{BBlue →} "
    base="White"
    ;;
n*)
    picto="{BCyan i} "
    base="Cyan"
    [ "${GITHUB_ACTIONS:-}" = "true" ] && gha="::notice::"
    ;;
w*)
    picto="{BYellow !} "
    base="Yellow"
    [ "${GITHUB_ACTIONS:-}" = "true" ] && gha="::warning::"
    ;;
e*)
    picto="{BRed ✕} "
    base="Red"
    [ "${GITHUB_ACTIONS:-}" = "true" ] && gha="::error::"
    ;;
s*)
    picto="{Green ✔} "
    base="Green"
    ;;
-)
    picto="  "
    step=""
    base="White"
    ;;
*)
    picto="$lvl "
    base="White"
    ;;
esac

# Inside a GitHub Actions run, n/w/e surface as ::notice::/::warning::/
# ::error:: workflow-command annotations instead of the colored job-log line
# -- GitHub already renders the annotation inline in the step log (as well as
# in the Checks/PR annotations UI), so printing the colored line too would
# just duplicate the same message right below it.
if [ -n "$gha" ]; then
    # GitHub requires %, CR, and LF to be percent-escaped in a workflow-command
    # message -- unescaped they can truncate the annotation or be parsed as
    # the start of another command. % must be escaped first, before the %25/
    # %0D/%0A this introduces are themselves mistaken for input.
    plain=$(
        printf '%s' "$*" | sed -E 's/\{[A-Za-z]+ ([^}]*)\}/\1/g' | awk '
            { gsub(/%/, "%25"); gsub(/\r/, "%0D"); printf "%s%s", (NR > 1 ? "%0A" : ""), $0 }
        '
    )
    printf '%s%s%s\n' "$gha" "$step" "$plain" >&2
else
    # Escape the message's shell-special chars (\ " $ `) before it goes through
    # eval, so a message quoting e.g. a jq filter (`test("(^|/)src/")`) is
    # printed verbatim instead of breaking the generated command.
    msg=$(printf '%s' "$step$*" | sed 's/[\\"$`]/\\&/g')
    eval "$(
        printf '%s\n' "printf '%b\n' \"$indent$picto$msg\${End}\"" | sed -E "s/\{([A-Z]) /{\1${base} /g;s/\{([a-zA-Z]+) ([^}]*)\}/\${\1}\2\${${base}}/g; s/\r//g; "
    )" >&2
fi
