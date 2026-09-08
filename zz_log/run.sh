#!/bin/sh
# zz_log <level> <msg...> — colored, leveled log line on stderr.
# level: i(nfo) n(otice) w(arning) e(rror) s(uccess) -(plain).

. zz_colors

lvl="$1" && shift

gha=""

case $lvl in
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
    printf '%s%s\n' "$gha" "$plain" >&2
else
    eval "$(
        echo "printf '%b\n' \"$picto$*\${End}\"" | sed -E "s/\{([A-Z]) /{\1${base} /g;s/\{([a-zA-Z]+) ([^}]*)\}/\${\1}\2\${${base}}/g; s/\r//g; "
    )" >&2
fi
