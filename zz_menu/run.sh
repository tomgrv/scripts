#!/bin/sh
# zz_menu [-t title] [-d default] [-f footer] <item>... — interactive numbered
# menu. Each <item> is "<key>=<label>" (or just "<label>", used as its own
# key). The menu is drawn on stderr; the chosen key is printed to stdout.
#
# Exit status:
#   0  an item was chosen (its key is on stdout; with -d <key>, a bare Enter
#      chooses that key)
#   1  the user quit (q) or input ended
#   2  a bare Enter with no default — the caller's "proceed/done" signal
#
# Meant to be called in a loop by callers that let the user adjust several
# things before proceeding:
#   while choice=$(zz_menu -t "Steps" "a=Alpha" "b=Beta"); do ...; done

. zz_colors

eval $(
    zz_args "Interactive numbered menu" $0 "$@" <<- help
		t title   title    Title line shown above the items
		d default default  Key chosen when the user just presses Enter
		f footer  footer   Hint line replacing the default one under the items
		# items   items    Items: <key>=<label> or <label>
	help
)

count=$#
if [ "$count" -lt 1 ]; then
    zz_log e "zz_menu: no menu items given."
    exit 1
fi

render() {
    [ -n "$title" ] && printf '%b\n' "${BBlue}==== ${title} ====${End}" >&2
    i=1
    for item in "$@"; do
        case "$item" in
        *=*) key=${item%%=*} label=${item#*=} ;;
        *) key=$item label=$item ;;
        esac
        mark=" "
        [ -n "$default" ] && [ "$key" = "$default" ] && mark="*"
        printf '%b\n' "  ${BBlue}$(printf '%2d' "$i")${End})${mark}${label}" >&2
        i=$((i + 1))
    done
    if [ -n "$footer" ]; then
        printf '%b\n' "${footer}" >&2
    elif [ -n "$default" ]; then
        printf '%b\n' "  ${BBlue}*${End} = default; <enter> picks it, q to quit." >&2
    else
        printf '%b\n' "  Enter a number, <enter> to proceed, q to quit." >&2
    fi
}

while true; do
    render "$@"
    printf '%b' "${BBlue}>${End} " >&2
    read -r choice || exit 1

    case "$choice" in
    "")
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

    eval "item=\${$choice}"
    case "$item" in
    *=*) printf '%s\n' "${item%%=*}" ;;
    *) printf '%s\n' "$item" ;;
    esac
    exit 0
done
