#!/bin/sh
# zz-menu [-t title] [-d default] [-f footer] [-z item] [-b keys] [-c states] <item>... — interactive
# numbered menu. Each <item> is "<key>=<label>" (or just "<label>", used as its
# own key). The menu is drawn on stderr; results go to stdout.
#
# Pick mode (default): choosing a number prints that item's key.
#   Exit status:
#     0  an item was chosen (its key is on stdout; with -d <key>, a bare
#        Enter chooses that key)
#     1  the user quit (q) or input ended
#     2  a bare Enter with no default — the caller's "proceed/done" signal
#
# Cycle mode (-c "s1,s2,..."): every item carries a state, shown as [state];
# choosing a number advances that item to the next state (wrapping around)
# and redraws. Items are "<key>:<state>=<label>"; a missing ":<state>"
# starts at the first state. A bare Enter prints one "<key>=<state>" line per
# item and exits 0; q or end of input exits 1 without printing anything.
#
# -z "<key>=<label>" adds an item numbered 0, listed above the others, for an
# action that is not one of them (pick mode only): choosing 0 prints its key.
#
# -b "<key>,<key>" shows those items highlighted (bold white): the menu owns its
# style, callers only say which items matter.
#
# Pick mode is meant for callers that loop until the user is done:
#   while choice=$(zz-menu -t "Steps" "a=Alpha" "b=Beta"); do ...; done

. zz-colors

# --- arguments
# Quoted eval: unquoted, field splitting would squeeze runs of spaces inside
# the values (item labels are often column-aligned).
eval "$(
    zz-args "Interactive numbered menu" $0 "$@" <<help
        t title   title    Title line shown above the items
        d default default  Key chosen when the user just presses Enter
        f footer  footer   Hint line replacing the default one under the items
        z zero    zero     Item "<key>=<label>" numbered 0, listed first (pick mode)
        b keys    highlight Comma-separated item keys shown in bold white
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

# --- functions

# next_state <state>: next state after <state> in the comma-separated cycle
# (first one when <state> is the last or unknown).
next_state() {
    local current="$1" # state to advance from (mandatory)
    local first="" take=0
    local old_ifs state

    old_ifs=$IFS
    IFS=,
    for state in $cycle; do
        [ -z "$first" ] && first=$state
        if [ "$take" -eq 1 ]; then
            IFS=$old_ifs
            printf '%s' "$state"
            return
        fi
        [ "$state" = "$current" ] && take=1
    done
    IFS=$old_ifs
    printf '%s' "$first"
}

# render: draw the menu (title, items with their state, hint line) on stderr.
render() {
    local i key label mark state

    [ -n "$title" ] && printf '%b%s%b\n' "${BBlue}==== " "$title" " ====${End}" >&2
    [ -z "$zero" ] || printf '%b%s\n' "  ${BBlue} 0${End}) " "${zero#*=}" >&2
    i=1
    while [ "$i" -le "$count" ]; do
        eval "key=\$key_$i label=\$label_$i state=\$state_$i"
        mark=" "
        [ -n "$default" ] && [ "$key" = "$default" ] && mark="*"
        if [ -n "$cycle" ]; then
            label="[$(printf "%-${width}s" "$state")] ${label}"
        fi
        case ",$highlight," in *",$key,"*) label="${BWhite}${label}${End}" ;; esac
        printf '%b%s\n' "  ${BBlue}$(printf '%2d' "$i")${End})${mark}" "$label" >&2
        i=$((i + 1))
    done
    if [ -n "$footer" ]; then
        printf '%b\n' "${footer}" >&2
    elif [ -n "$cycle" ]; then
        printf '%b\n' "  Enter a number to cycle its state, <enter> to proceed, q to quit." >&2
    elif [ -n "$default" ]; then
        printf '%b\n' "  ${BBlue}*${End} = default; <enter> picks it, q to quit." >&2
    else
        printf '%b\n' "  Enter a number, <enter> to proceed, q to quit." >&2
    fi
}

# --- items

# Split every item into key_<N> (key), label_<N> (label) and, in cycle mode,
# state_<N> (state) - POSIX sh has no arrays, so they live in eval'd variables.
i=1
for item in "$@"; do
    case "$item" in
    *=*) left=${item%%=*} label=${item#*=} ;;
    *) left=$item label=$item ;;
    esac
    state=""
    if [ -n "$cycle" ]; then
        case "$left" in
        *:*) state=${left#*:} left=${left%%:*} ;;
        *) state=${cycle%%,*} ;;
        esac
    fi
    eval "key_$i=\$left label_$i=\$label state_$i=\$state"
    i=$((i + 1))
done

# Widest state, so the [state] column lines up.
width=0
if [ -n "$cycle" ]; then
    old_ifs=$IFS
    IFS=,
    for cycle_state in $cycle; do
        [ "${#cycle_state}" -gt "$width" ] && width=${#cycle_state}
    done
    IFS=$old_ifs
fi

# --- menu loop: draw, read a choice, then pick, cycle or finish.
while true; do
    render
    # Asked by zz-prompt; input ending quits like q.
    choice=$(zz-prompt -e) || exit 1

    case "$choice" in
    "")
        if [ -n "$cycle" ]; then
            i=1
            while [ "$i" -le "$count" ]; do
                eval "printf '%s=%s\\n' \"\$key_$i\" \"\$state_$i\""
                i=$((i + 1))
            done
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
        continue
        ;;
    esac

    # Drop leading zeros ("007" -> 7); $(( )) would read them as octal.
    choice=$(printf '%s' "$choice" | sed 's/^0*//')
    choice=${choice:-0}
    if [ "$choice" -eq 0 ] && [ -n "$zero" ] && [ -z "$cycle" ]; then
        printf '%s\n' "${zero%%=*}"
        exit 0
    fi
    if [ "$choice" -lt 1 ] || [ "$choice" -gt "$count" ]; then
        zz-log w "No such item: $choice (enter a number between 1 and ${count})."
        continue
    fi

    if [ -n "$cycle" ]; then
        eval "current=\$state_$choice"
        next=$(next_state "$current")
        eval "state_$choice=\$next"
        continue
    fi

    eval "printf '%s\\n' \"\$key_$choice\""
    exit 0
done
