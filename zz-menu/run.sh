#!/bin/sh
# zz-menu [-t title] [-d default] [-f footer] [-c states] <item>... — interactive
# numbered menu. Each <item> is "<key>=<label>" (or just "<label>", used as its
# own key). The menu is drawn on stderr; results go to stdout. A label may hold
# TAB-separated cells: the menu aligns them in columns. With -g <n> the n-th
# cell (counted like cut -f) is the group of the item: items are regrouped in
# the order their groups first appear, a header line names each group, and
# that cell is not shown again on the rows.
#
# -z "<key>=<label>" adds an item numbered 0, listed first, for a special case that is
# not one of the items: choosing 0 prints its key alone and exits 0 (in cycle mode too,
# where the caller tells it from the "<key>=<state>" lines and usually redraws).
#
# Progress line, for the slow part before a menu (reading files, running jq...):
#   zz-menu -p "Reading the inputs..."   shows the message on stderr, on a terminal only
#   zz-menu -P                           clears it (a menu clears it itself when it draws)
# Both are answered before the options are parsed, so a call costs next to nothing.
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

# --- progress line: -p <message> shows it, -P clears it; a terminal only, no argument parsing
case "${1:-}" in
-p)
    [ ! -t 2 ] || printf '\r\033[K%s' "${2:-}" >&2
    exit 0
    ;;
-P)
    [ ! -t 2 ] || printf '\r\033[K' >&2
    exit 0
    ;;
esac

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
        z zero    zero     Item "<key>=<label>" numbered 0, listed first: choosing 0 prints its key
        g group   group    Number of the TAB-separated label cell naming each item's group (as cut -f)
        # items   items    Items: <key>=<label> or <label>
help
)"

# --- parameters
count=$#
if [ "$count" -lt 1 ]; then
    zz-log e "zz-menu: no menu items given."
    exit 1
fi
case "$group" in
*[!0-9]*)
    zz-log e "zz-menu: -g takes a cell number (got '$group')."
    exit 1
    ;;
esac
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

# -g: gather the items of a group under one header (groups in order of first appearance,
# items keep their order inside a group). Cells 1-3 of a row are key, state, initial state.
if [ -n "$group" ]; then
    rows=$(printf '%s' "$rows" | awk -F'\t' -v g=$((group + 3)) '
        { k = (NF > g) ? $g : ""; if (!(k in seen)) { seen[k] = 1; order[++n] = k } line[NR] = $0; grp[NR] = k }
        END { for (i = 1; i <= n; i++) for (r = 1; r <= NR; r++) if (grp[r] == order[i]) print line[r] }')$nl
fi

# Redraw in place only where the cursor can move back, and never over scripted answers.
redraw=
[ -t 2 ] && [ -z "${ZZ_PROMPT_ANSWERS:-}" ] && redraw=1
# One keypress is enough to pick a number up to 9 (zz-prompt falls back to a line off a terminal).
[ "$count" -le 9 ] && key=-k || key=

# --- functions

# render: the numbered rows, aligned by awk (labels are read from stdin and printed
# verbatim; colours and options travel by the environment, not as awk escapes).
render() {
    printf '%s' "$rows" | NUM=$BBlue HI=$BYellow OFF=$End GRP=$BPurple DEF=$default CYC=$cycle GROUP=$group awk -F'\t' '
        BEGIN { m = split(ENVIRON["CYC"], s, ","); for (i = 1; i <= m; i++) if (length(s[i]) > sw) sw = length(s[i])
                gi = ENVIRON["GROUP"] ? ENVIRON["GROUP"] + 3 : 0 }
        { key[NR] = $1; st[NR] = $2; ini[NR] = $3
          # a row with no cell past the group one (e.g. "Delete...") belongs to no group
          hid[NR] = (NF > gi) ? gi : 0; grp[NR] = hid[NR] ? $gi : ""; last[NR] = NF
          for (i = 4; i <= NF; i++) { c[NR, i] = $i; if (i != hid[NR] && i < NF && length($i) > w[i]) w[i] = length($i) } }
        END {
            prev = "\001"
            for (r = 1; r <= NR; r++) {
                if (gi && grp[r] != prev) {
                    prev = grp[r]
                    if (prev != "") print " " ENVIRON["GRP"] prev ENVIRON["OFF"]; else if (r > 1) print ""
                }
                line = sprintf(" %s%*d%s)%s", ENVIRON["NUM"], length(NR), r, ENVIRON["OFF"], key[r] == ENVIRON["DEF"] ? "*" : " ")
                if (ENVIRON["CYC"] != "")
                    line = line (st[r] != ini[r] ? sprintf("%s[%-*s]%s ", ENVIRON["HI"], sw, st[r], ENVIRON["OFF"]) : sprintf("[%-*s] ", sw, st[r]))
                for (i = 4; i <= last[r]; i++)
                    if (i != hid[r]) line = line (i < last[r] ? sprintf("%-*s ", w[i], c[r, i]) : c[r, i])
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
        [ -z "$zero" ] || printf ' %b%*d%b) %s\n' "$BBlue" "${#count}" 0 "$End" "${zero#*=}"
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
[ -z "$redraw" ] || printf '\r\033[K' >&2 # a progress line (-p) may be waiting here
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
    if [ "$choice" -eq 0 ] && [ -n "$zero" ]; then
        printf '%s\n' "${zero%%=*}"
        exit 0
    fi
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
