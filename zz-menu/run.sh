#!/bin/sh
# zz-menu [-t title] [-d default] [-f footer] [-c states] <item>... — interactive
# numbered menu. Each <item> is "<key>=<label>" (or just "<label>", used as its
# own key). The menu is drawn on stderr; results go to stdout. A label may hold
# TAB-separated cells: the menu aligns them in columns.
#
# Keys, the same everywhere: a number acts on its item, Enter validates, q quits.
# On a terminal a menu of up to 9 items takes the number as one keypress (no
# Enter), and cycling redraws the menu in place.
#
# Pick mode (default): choosing a number prints that item's key.
#   Exit status:
#     0  an item was chosen (its key is on stdout; with -d <key>, a bare
#        Enter chooses that key)
#     1  the user quit (q) or input ended
#     2  a bare Enter with no default — the caller's "proceed/done" signal
#
# Cycle mode (-c "s1,s2,..."): every item carries a state, shown as [state]
# (highlighted once it differs from where it started); choosing a number
# advances that item to the next state (wrapping around) and redraws. Items are
# "<key>:<state>=<label>"; a missing ":<state>" starts at the first state. A
# bare Enter prints one "<key>=<state>" line per item and exits 0; q or end of
# input exits 1 without printing anything.
#
# Pick mode is meant for callers that loop until the user is done:
#   while choice=$(zz-menu -t "Steps" "a=Alpha" "b=Beta"); do ...; done

. zz-colors

# --- arguments
# Quoted eval: unquoted, field splitting would squeeze runs of spaces inside
# the values (item labels are often column-aligned).
eval "$(
    zz-args "Interactive numbered menu" "$0" "$@" <<help
        t title   title    Title line shown above the items
        d default default  Key chosen when the user just presses Enter
        f footer  footer   Hint line replacing the default one under the items
        c cycle   cycle    Comma-separated states; choosing an item advances its state
        # items   items    Items: <key>=<label> or <label>
help
)"

# --- parameters
count=$#
if [ "$count" -lt 1 ]; then
    zz-log e "zz-menu: no menu items given."
    exit 1
fi
tab=$(printf '\t')
nl='
'

# One row per item, POSIX sh having no arrays: "<key> TAB <state> TAB <initial state> TAB <label>".
rows=
for item in "$@"; do
    case "$item" in
    *=*) left=${item%%=*} label=${item#*=} ;;
    *) left=$item label=$item ;;
    esac
    state=
    if [ -n "$cycle" ]; then
        case "$left" in
        *:*) state=${left#*:} left=${left%%:*} ;;
        *) state=${cycle%%,*} ;;
        esac
    fi
    rows="$rows$left$tab$state$tab$state$tab$label$nl"
done

# Redraw in place only where the cursor can move back, and never over scripted answers.
redraw=
[ -t 2 ] && [ -z "${ZZ_PROMPT_ANSWERS:-}" ] && redraw=1
# One keypress is enough to pick a number up to 9 (zz-prompt falls back to a line off a terminal).
[ "$count" -le 9 ] && key=-k || key=

# --- functions

# render: the numbered rows, aligned by awk (labels are read from stdin and printed
# verbatim; colours and options travel by the environment, not as awk escapes).
render() {
    printf '%s' "$rows" | NUM=$BBlue HI=$BYellow OFF=$End DEF=$default CYC=$cycle awk -F'\t' '
        BEGIN { m = split(ENVIRON["CYC"], s, ","); for (i = 1; i <= m; i++) if (length(s[i]) > sw) sw = length(s[i]) }
        { key[NR] = $1; st[NR] = $2; ini[NR] = $3; cells[NR] = NF
          for (i = 4; i <= NF; i++) { c[NR, i] = $i; if (i < NF && length($i) > w[i]) w[i] = length($i) } }
        END {
            for (r = 1; r <= NR; r++) {
                line = sprintf(" %s%*d%s)%s", ENVIRON["NUM"], length(NR), r, ENVIRON["OFF"], key[r] == ENVIRON["DEF"] ? "*" : " ")
                if (ENVIRON["CYC"] != "")
                    line = line (st[r] != ini[r] ? sprintf("%s[%-*s]%s ", ENVIRON["HI"], sw, st[r], ENVIRON["OFF"]) : sprintf("[%-*s] ", sw, st[r]))
                for (i = 4; i <= cells[r]; i++)
                    line = line (i < cells[r] ? sprintf("%-*s ", w[i], c[r, i]) : c[r, i])
                print line
            }
        }'
}

# draw: the whole menu on stderr; $lines is how many lines that took.
draw() {
    local frame hint

    if [ -n "$footer" ]; then
        hint=$footer
    elif [ -n "$cycle" ]; then
        hint=" Number cycles its state; <enter> validates; q quits."
    elif [ -n "$default" ]; then
        hint=" ${BBlue}*${End} = default; <enter> picks it; q quits."
    else
        hint=" Number picks; <enter> validates; q quits."
    fi
    frame=$(
        [ -z "$title" ] || printf '%b%s%b\n' "${BBlue}==== " "$title" " ====${End}"
        render
        printf '%b\n' "$hint"
    )
    printf '%s\n' "$frame" >&2
    lines=$(printf '%s\n' "$frame" | wc -l)
}

# field <n> <column>: column <column> of row <n>.
field() { printf '%s' "$rows" | awk -F'\t' -v n="$1" -v col="$2" 'NR == n { print $col }'; }

# cycle_row <n>: advance row <n> to the next state (the first one past the last or an unknown one).
cycle_row() {
    rows=$(printf '%s' "$rows" | awk -F'\t' -v OFS='\t' -v n="$1" -v cyc="$cycle" '
        BEGIN { m = split(cyc, s, ",") }
        NR == n { for (i = 1; i <= m; i++) if (s[i] == $2) break; $2 = s[i % m + 1] }
        { print }')$nl
}

# --- menu loop: draw, read a choice, then pick, cycle or finish.
erase=0
while :; do
    # Take the previous frame (and the line answered under it) off the screen first.
    [ "$erase" -eq 0 ] || printf '\033[%dA\033[J' "$erase" >&2
    draw
    erase=${redraw:+$((lines + 1))}
    erase=${erase:-0}

    # Asked by zz-prompt; input ending quits like q.
    choice=$(ZZ_PROMPT_MARK=">" ZZ_PROMPT_HINT= zz-prompt -e $key "") || exit 1

    case "$choice" in
    "")
        if [ -n "$cycle" ]; then
            printf '%s' "$rows" | awk -F'\t' '{ print $1 "=" $2 }'
            exit 0
        fi
        if [ -n "$default" ]; then
            printf '%s\n' "$default"
            exit 0
        fi
        exit 2
        ;;
    q | Q) exit 1 ;;
    *[!0-9]*)
        zz-log w "Invalid input: '$choice' (enter a number between 1 and ${count}, <enter> or q)."
        erase=0
        continue
        ;;
    esac

    # Drop leading zeros ("007" -> 7); $(( )) would read them as octal.
    choice=$(printf '%s' "$choice" | sed 's/^0*//')
    choice=${choice:-0}
    if [ "$choice" -lt 1 ] || [ "$choice" -gt "$count" ]; then
        zz-log w "No such item: $choice (enter a number between 1 and ${count})."
        erase=0
        continue
    fi

    [ -n "$cycle" ] || {
        field "$choice" 1
        exit 0
    }
    cycle_row "$choice"
done
