#!/bin/sh
# zz_log <level> <msg...> — colored, leveled log line on stderr.
# level: i(nfo) w(arning) e(rror) s(uccess) -(plain).

. zz_colors

lvl="$1" && shift

case $lvl in
i*)
    picto="{BBlue →} "
    base="White"
    ;;
w*)
    picto="{BYellow !} "
    base="Yellow"
    ;;
e*)
    picto="{BRed ✕} "
    base="Red"
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

eval "$(
    echo "printf '%b\n' \"$picto$*\${End}\"" | sed -E "s/\{([A-Z]) /{\1${base} /g;s/\{([a-zA-Z]+) ([^}]*)\}/\${\1}\2\${${base}}/g; s/\r//g; "
)" >&2
