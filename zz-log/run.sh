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
# Depth: ":N" (N an integer: :1, :2, ...) is the plain level, nested N levels
# (2 spaces each) under the message above it, on top of the depth ZZ_LOG_INDENT
# gives it. ":" alone is depth 0. Typical use: a hint under an error:
#   zz-log e "Could not fetch x"; zz-log :1 "Check the ref"
#
# Custom level: any other string is printed as the line's own prefix, the way
# json-validate nests its output ("zz-log \"$prefix -\" msg"). The caller owns
# that prefix, so neither the step tag nor ZZ_LOG_INDENT is added to it.
#
# Levels, by what the reader needs to know:
#   i  a step starts ("Fetching ...", "Installing ...")
#   s  a step is done
#   n  a decision the tool made for you ("Also enabling ...", "Using local ...")
#   w  something is degraded but the run continues
#   e  the run stops: say what failed, then a "-" line saying what to do
#   d  internals, only with ZZ_DEBUG
#   -  a detail line under the message above it (-1, -2, ... nest deeper)
#   o  what a command printed (git, an installer), see above
#
# Inline colour: "{Name text}" prints text in colour Name (any zz-colors
# variable, e.g. {Purple x}, {U path}); a single capital letter is that style
# in the line's own colour ({U path} on a green line is UGreen). The line's
# colour comes back after the text. Backslash escapes in the message (\n, \t)
# are interpreted.
#
# Env: ZZ_LOG_STEP (current step label, exported by the caller so its children
# inherit it), ZZ_LOG_INDENT (spaces to indent every line; a caller nesting a
# child script raises it by 2 for that child).
#
# Everything but the GitHub Actions branch runs on shell builtins: no fork,
# no eval of the message.

. zz-colors

# --- arguments
lvl="$1" && shift

# --- parameters
# Drop leading zeros of the depth: $((08)) would be read as octal.
depth=${depth#"${depth%%[!0]*}"}
indent=${ZZ_LOG_INDENT:-0}
case "$indent" in *[!0-9]*) indent=0 ;; esac
indent=$((indent + ${depth:-0} * 2))
# The step tag is dimmed so it recedes behind the message; step is its plain
# form (GitHub annotations have no colours).
step=""
steptag=""
[ -z "${ZZ_LOG_STEP:-}" ] || {
    step="[$ZZ_LOG_STEP] "
    steptag="{BBlack [$ZZ_LOG_STEP]} "
}

# --- functions

# code=<value of the zz-colors variable named $1>, empty unless $1 is letters
# only (the one place a name is expanded indirectly).
code_of() {
    case "$1" in
    "" | *[!A-Za-z]*) code="" ;;
    *) eval "code=\${$1:-}" ;;
    esac
}

# out=<$1 with each "{Name text}" replaced by colour(Name) text base-colour>;
# $2 is the name of the base colour, restored after every coloured text.
paint() {
    rest=$1 out="" painted_base=""
    code_of "$2"
    painted_base=$code
    while :; do
        case "$rest" in
        *"{"*"}"*) ;;
        *) break ;;
        esac
        before=${rest%%"{"*}
        tail=${rest#*"{"}
        token=${tail%%"}"*}
        after=${tail#*"}"}
        name=${token%% *}
        case "$token" in
        *" "*) ;;
        *) name="" ;;
        esac
        case "$name" in
        "" | *[!A-Za-z]*)
            # Not a colour marker: keep the brace and look further on.
            out="$out$before{"
            rest=$tail
            continue
            ;;
        [A-Z]) name="$name$2" ;;
        esac
        code_of "$name"
        out="$out$before$code${token#* }$painted_base"
        rest=$after
    done
    out="$out$rest"
}

# --- operation output: dimmed, gutter-prefixed, one line at a time.
case $lvl in
o*)
    {
        if [ "$#" -gt 0 ]; then printf '%s\n' "$*"; else cat; fi
    } | while IFS= read -r line || [ -n "$line" ]; do
        printf '%*s%s│ %s%s\n' "$indent" "" "$BBlack" "$line" "$End" >&2
    done
    exit 0
    ;;
esac

# --- level: pictogram, base colour, GitHub Actions annotation.
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
    steptag=""
    base="White"
    ;;
*)
    picto="$lvl "
    step=""
    steptag=""
    indent=0
    base="White"
    ;;
esac

# --- print.
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
    paint "$picto$steptag$*" "$base"
    printf '%*s%b%s\n' "$indent" "" "$out" "$End" >&2
fi
