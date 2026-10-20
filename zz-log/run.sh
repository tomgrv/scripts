#!/bin/sh
# zz-log <level> <msg...> — colored, leveled log line on stderr.
# level: i(nfo) n(otice) w(arning) e(rror) s(uccess) d(ebug) -(plain).
# d(ebug) is silent unless ZZ_DEBUG is set.
#
# Script log vs operation output:
#   - a script's own messages (i n w e s d -) get the level pictogram (none for -);
#   - o(utput) is what a command it ran printed (git, an installer...): each
#     line, taken from the message or from stdin when none is given, is dimmed
#     behind a "│" gutter, with no pictogram. Pipe it:
#       cmd 2>&1 | zz-log o        (or keep the status: out=$(cmd 2>&1) || rc=$?)
#
# Layout: the headline levels (i n w e s) start at column 0. A detail line (-) or
# command output (o) hangs under the headline above it behind one dim tree guide
# ("   |"). ZZ_LOG_INDENT is a nesting depth (0 by default, in levels, not
# spaces): each level adds a guide, so a caller that wants a block deeper than
# its own headline raises it by 1 for that block.
#
# Custom level: any other string is printed as the line's own prefix, the way
# json-validate nests its output ("zz-log \"$prefix -\" msg"). The caller owns
# that prefix, so ZZ_LOG_INDENT is not applied to it.
#
# Levels, by what the reader needs to know:
#   i  a step starts ("Fetching ...", "Installing ...")
#   s  a step is done
#   n  a decision the tool made for you ("Also enabling ...", "Using local ...")
#   w  something is degraded but the run continues
#   e  the run stops: say what failed, then a "-" line saying what to do
#   d  internals, only with ZZ_DEBUG
#   -  a detail line under the message above it
#   o  what a command printed (git, an installer), see above
#
# Inline colour: "{Name text}" prints text in colour Name (any zz-colors
# variable, e.g. {Purple x}, {U path}); a single capital letter is that style
# in the line's own colour ({U path} on a green line is UGreen). The line's
# colour comes back after the text. Backslash escapes in the message (\n, \t)
# are interpreted.
#
# Env: ZZ_LOG_INDENT (nesting depth, see Layout), inherited by child scripts.
#
# Everything but the GitHub Actions branch runs on shell builtins: no fork,
# no eval of the message.

. zz-colors

# --- arguments
lvl="$1" && shift

# --- parameters
depth=${ZZ_LOG_INDENT:-0}
case "$depth" in *[!0-9]*) depth=0 ;; esac

# One dim guide per level above the line; a detail line adds its own.
guides=""
n=0
while [ "$n" -lt "$depth" ]; do
    guides="$guides   |"
    n=$((n + 1))
done
[ -z "$guides" ] || guides="$BBlack$guides$End"
prefix="$guides$BBlack   |$End"

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

# --- level: pictogram, base colour, GitHub Actions annotation.
gha=""

case $lvl in
o*)
    {
        if [ "$#" -gt 0 ]; then printf '%s\n' "$*"; else cat; fi
    } | while IFS= read -r line || [ -n "$line" ]; do
        printf '%s   %s│ %s%s\n' "$guides" "$BBlack" "$line" "$End" >&2
    done
    exit 0
    ;;
d*)
    [ -n "${ZZ_DEBUG:-}" ] || exit 0
    picto="{BBlack ·} "
    base="BBlack"
    prefix=""
    ;;
i*)
    picto="{BBlue →} "
    base="White"
    prefix=""
    ;;
n*)
    picto="{BCyan i} "
    base="Cyan"
    prefix=""
    [ "${GITHUB_ACTIONS:-}" = "true" ] && gha="::notice::"
    ;;
w*)
    picto="{BYellow !} "
    base="Yellow"
    prefix=""
    [ "${GITHUB_ACTIONS:-}" = "true" ] && gha="::warning::"
    ;;
e*)
    picto="{BRed ✕} "
    base="Red"
    prefix=""
    [ "${GITHUB_ACTIONS:-}" = "true" ] && gha="::error::"
    ;;
s*)
    picto="{Green ✔} "
    base="Green"
    prefix=""
    ;;
-)
    picto="  "
    base="White"
    ;;
*)
    picto="$lvl "
    prefix=""
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
    printf '%s%s\n' "$gha" "$plain" >&2
else
    paint "$picto$*" "$base"
    printf '%s%b%s\n' "$prefix" "$out" "$End" >&2
fi
