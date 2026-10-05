#!/bin/sh
# zz_menu [-t title] [-d default] [-f footer] [-c states] <item>... — interactive
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
# Pick mode is meant for callers that loop until the user is done:
#   while choice=$(zz_menu -t "Steps" "a=Alpha" "b=Beta"); do ...; done

. zz_colors

# Quoted eval: unquoted, field splitting would squeeze runs of spaces inside
# the values (item labels are often column-aligned).
eval "$(
    zz_args "Interactive numbered menu" $0 "$@" <<- help
		t title   title    Title line shown above the items
		d default default  Key chosen when the user just presses Enter
		f footer  footer   Hint line replacing the default one under the items
		c cycle   cycle    Comma-separated states; choosing an item advances its state
		# items   items    Items: <key>=<label> or <label>
	help
)"

count=$#
if [ "$count" -lt 1 ]; then
    zz_log e "zz_menu: no menu items given."
    exit 1
fi

# Split every item into _k<N> (key), _l<N> (label) and, in cycle mode, _s<N>
# (state) - POSIX sh has no arrays, so they live in eval'd variables.
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
    eval "_k$i=\$left _l$i=\$label _s$i=\$state"
    i=$((i + 1))
done

# Next state after $1 in the comma-separated cycle (first one when $1 is
# the last or unknown).
next_state() {
    _first="" _take=0 _old_ifs=$IFS
    IFS=,
    for _s in $cycle; do
        [ -z "$_first" ] && _first=$_s
        if [ "$_take" -eq 1 ]; then
            IFS=$_old_ifs
            printf '%s' "$_s"
            return
        fi
        [ "$_s" = "$1" ] && _take=1
    done
    IFS=$_old_ifs
    printf '%s' "$_first"
}

# Widest state, so the [state] column lines up.
width=0
if [ -n "$cycle" ]; then
    _old_ifs=$IFS
    IFS=,
    for _s in $cycle; do
        [ "${#_s}" -gt "$width" ] && width=${#_s}
    done
    IFS=$_old_ifs
fi

render() {
    [ -n "$title" ] && printf '%b\n' "${BBlue}==== ${title} ====${End}" >&2
    i=1
    while [ "$i" -le "$count" ]; do
        eval "key=\$_k$i label=\$_l$i state=\$_s$i"
        mark=" "
        [ -n "$default" ] && [ "$key" = "$default" ] && mark="*"
        if [ -n "$cycle" ]; then
            label="[$(printf "%-${width}s" "$state")] ${label}"
        fi
        printf '%b\n' "  ${BBlue}$(printf '%2d' "$i")${End})${mark}${label}" >&2
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

while true; do
    render
    printf '%b' "${BBlue}>${End} " >&2
    read -r choice || exit 1

    case "$choice" in
    "")
        if [ -n "$cycle" ]; then
            i=1
            while [ "$i" -le "$count" ]; do
                eval "printf '%s=%s\\n' \"\$_k$i\" \"\$_s$i\""
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
        zz_log w "Invalid input: '$choice' (enter a number between 1 and ${count}, <enter> or q)."
        continue
        ;;
    esac

    choice=$(expr "$choice" + 0)
    if [ "$choice" -lt 1 ] || [ "$choice" -gt "$count" ]; then
        zz_log w "No such item: $choice (enter a number between 1 and ${count})."
        continue
    fi

    if [ -n "$cycle" ]; then
        eval "_cur=\$_s$choice"
        _new=$(next_state "$_cur")
        eval "_s$choice=\$_new"
        continue
    fi

    eval "printf '%s\\n' \"\$_k$choice\""
    exit 0
done
