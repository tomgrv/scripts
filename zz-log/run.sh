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
#
# Run as a command (legacy) it logs and exits. Sourced as a library it only
# defines zz_log, which logs in the caller's shell (no fork per message):
#   ZZ_LOG_LIB=1; . zz-log; zz_log i "hello"

. zz-colors

# zz_log <level> <msg...>. Variables are _zl_-prefixed: sh has no `local`
# and this runs in the caller's shell when sourced.
zz_log() {
    _zl_lvl="$1" && shift

    _zl_indent=$(printf '%*s' "${ZZ_LOG_INDENT:-0}" '')
    _zl_step=""
    [ -z "${ZZ_LOG_STEP:-}" ] || _zl_step="[$ZZ_LOG_STEP] "

    # Operation output: dimmed, gutter-prefixed, one line at a time.
    case $_zl_lvl in
    o*)
        {
            if [ "$#" -gt 0 ]; then printf '%s\n' "$*"; else cat; fi
        } | while IFS= read -r _zl_line || [ -n "$_zl_line" ]; do
            printf '%b%s%b\n' "$_zl_indent${BBlack}│ " "$_zl_line" "${End}" >&2
        done
        return 0
        ;;
    esac

    _zl_gha=""

    case $_zl_lvl in
    d*)
        [ -n "${ZZ_DEBUG:-}" ] || return 0
        _zl_picto="{BBlack ·} "
        _zl_base="BBlack"
        ;;
    i*)
        _zl_picto="{BBlue →} "
        _zl_base="White"
        ;;
    n*)
        _zl_picto="{BCyan i} "
        _zl_base="Cyan"
        [ "${GITHUB_ACTIONS:-}" = "true" ] && _zl_gha="::notice::"
        ;;
    w*)
        _zl_picto="{BYellow !} "
        _zl_base="Yellow"
        [ "${GITHUB_ACTIONS:-}" = "true" ] && _zl_gha="::warning::"
        ;;
    e*)
        _zl_picto="{BRed ✕} "
        _zl_base="Red"
        [ "${GITHUB_ACTIONS:-}" = "true" ] && _zl_gha="::error::"
        ;;
    s*)
        _zl_picto="{Green ✔} "
        _zl_base="Green"
        ;;
    -)
        _zl_picto="  "
        _zl_step=""
        _zl_base="White"
        ;;
    *)
        _zl_picto="$_zl_lvl "
        _zl_base="White"
        ;;
    esac

    # Inside a GitHub Actions run, n/w/e surface as ::notice::/::warning::/
    # ::error:: workflow-command annotations instead of the colored job-log line
    # -- GitHub already renders the annotation inline in the step log (as well as
    # in the Checks/PR annotations UI), so printing the colored line too would
    # just duplicate the same message right below it.
    if [ -n "$_zl_gha" ]; then
        # GitHub requires %, CR, and LF to be percent-escaped in a workflow-command
        # message -- unescaped they can truncate the annotation or be parsed as
        # the start of another command. % must be escaped first, before the %25/
        # %0D/%0A this introduces are themselves mistaken for input.
        _zl_plain=$(
            printf '%s' "$*" | sed -E 's/\{[A-Za-z]+ ([^}]*)\}/\1/g' | awk '
                { gsub(/%/, "%25"); gsub(/\r/, "%0D"); printf "%s%s", (NR > 1 ? "%0A" : ""), $0 }
            '
        )
        printf '%s%s%s\n' "$_zl_gha" "$_zl_step" "$_zl_plain" >&2
    else
        # Escape the message's shell-special chars (\ " $ `) before it goes through
        # eval, so a message quoting e.g. a jq filter (`test("(^|/)src/")`) is
        # printed verbatim instead of breaking the generated command.
        _zl_msg=$(printf '%s' "$_zl_step$*" | sed 's/[\\"$`]/\\&/g')
        eval "$(
            printf '%s\n' "printf '%b\n' \"$_zl_indent$_zl_picto$_zl_msg\${End}\"" | sed -E "s/\{([A-Z]) /{\1${_zl_base} /g;s/\{([a-zA-Z]+) ([^}]*)\}/\${\1}\2\${${_zl_base}}/g; s/\r//g; "
        )" >&2
    fi
}

# Legacy command mode: log now, unless sourced as a library.
[ -n "${ZZ_LOG_LIB:-}" ] || zz_log "$@"
