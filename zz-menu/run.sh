#!/bin/sh
# zz-menu [-t title] [-d default] [-f footer] [-c states] [-z item] [-b keys] [-g n] [-D n] <item>... —
# interactive numbered menu, drawn on stderr; the result goes to stdout. Details: README.md.
# An <item> is "<key>=<label>" (or "<label>", its own key). Keys, the same everywhere: a number acts
# on its item, Enter validates, q quits.
#
# Pick mode (default): choosing a number prints the item's key. Exit status: 0 an item was chosen
#   (a bare Enter chooses -d <key>); 1 quit (q) or input ended; 2 a bare Enter with no default.
# Cycle mode (-c "s1,s2,..."): items are "<key>:<state>=<label>"; a number advances that item's
#   state (wrapping) and redraws in place; Enter prints one "<key>=<state>" line per item.
# -z "<key>=<label>": an item numbered 0, listed first; choosing it prints its key alone (also in
#   cycle mode).
#
# A label may hold TAB-separated cells, aligned in columns. -g <n> takes the n-th cell (as cut -f) as
# the item's group: items are regrouped in order of first appearance under a header. A label may end
# in RS (ASCII 036) and a detail, printed under the item, indented under the -D <n>th shown cell.
#
# Highlighting: a row is shown whole in yellow when -b lists its key (the caller says what that
# means: set, saved...) or, in cycle mode, when its state moved off where it started. With NO_COLOR a
# + takes the mark slot instead.

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
        b bold    bold     Comma-separated item keys shown highlighted
        D detail  detail   Cell number the detail line of an item is indented under (default 1)
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
case "$group$detail" in
*[!0-9]*)
    zz-log e "zz-menu: -g and -D take a cell number (got '$group' '$detail')."
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

# --- functions

# render: the numbered rows, aligned by awk (labels are read from stdin and printed
# verbatim; colours and options travel by the environment, not as awk escapes).
render() {
    printf '%s' "$rows" | NUM=$BBlue HI=$BYellow OFF=$End GRP=$BPurple DEF=$default CYC=$cycle GROUP=$group DETAIL=$detail BOLD=",$bold," awk -F'\t' '
        BEGIN { m = split(ENVIRON["CYC"], s, ","); for (i = 1; i <= m; i++) if (length(s[i]) > sw) sw = length(s[i])
                gi = ENVIRON["GROUP"] ? ENVIRON["GROUP"] + 3 : 0 }
        { dpos = index($0, "\036"); det[NR] = ""   # RS starts the detail line, if any
          if (dpos) { det[NR] = substr($0, dpos + 1); $0 = substr($0, 1, dpos - 1) }
          key[NR] = $1; st[NR] = $2; ini[NR] = $3
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
                # highlighted: listed by -b, or a cycle state that moved off where it started
                hl = index(ENVIRON["BOLD"], "," key[r] ",") || (ENVIRON["CYC"] != "" && st[r] != ini[r])
                # the mark slot: * default; + highlighted when there is no colour to show it
                mark = key[r] == ENVIRON["DEF"] ? "*" : (hl && ENVIRON["HI"] == "" ? "+" : " ")
                body = ENVIRON["CYC"] != "" ? sprintf("[%-*s] ", sw, st[r]) : ""
                shown = 0; pad = 3 + length(NR)   # " " number ")" mark
                indent = pad + length(body)
                for (i = 4; i <= last[r]; i++)
                    if (i != hid[r]) {
                        if (++shown == (ENVIRON["DETAIL"] ? ENVIRON["DETAIL"] : 1)) indent = pad + length(body)
                        body = body (i < last[r] ? sprintf("%-*s ", w[i], c[r, i]) : c[r, i])
                    }
                sub(/ +$/, "", body)   # an empty last cell leaves only padding
                print sprintf(" %s%*d%s)%s", ENVIRON["NUM"], length(NR), r, ENVIRON["OFF"], mark) (hl ? ENVIRON["HI"] body ENVIRON["OFF"] : body)
                if (det[r] != "") print sprintf("%*s", indent, "") (hl ? ENVIRON["HI"] det[r] ENVIRON["OFF"] : det[r])
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
    choice=$(ZZ_PROMPT_MARK=">" ZZ_PROMPT_HINT= zz-prompt -e "") || exit 1

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
        printf '%s' "$rows" | awk -F'\t' -v n="$choice" 'NR == n { print $1 }'
        exit 0
    }
    cycle_row "$choice"
done
