#!/bin/sh
# zz-colors — ANSI color codes. Meant to be sourced: `. zz-colors`.
# The values hold the real ESC byte (not the text \033), so they print as colours
# with echo, printf %s or %b alike, and sourcing forks nothing.
# NO_COLOR (https://no-color.org), when set and non-empty, turns every code off.

None='[0m'
End='[0m'

Black='[0;30m'
Red='[0;31m'
Green='[0;32m'
Yellow='[0;33m'
Blue='[0;34m'
Purple='[0;35m'
Cyan='[0;36m'
White='[0;37m'

BBlack='[1;30m'
BRed='[1;31m'
BGreen='[1;32m'
BYellow='[1;33m'
BBlue='[1;34m'
BPurple='[1;35m'
BCyan='[1;36m'
BWhite='[1;37m'

UBlack='[4;30m'
URed='[4;31m'
UGreen='[4;32m'
UYellow='[4;33m'
UBlue='[4;34m'
UPurple='[4;35m'
UCyan='[4;36m'
UWhite='[4;37m'

if [ -n "${NO_COLOR:-}" ]; then
    None= End=
    Black= Red= Green= Yellow= Blue= Purple= Cyan= White=
    BBlack= BRed= BGreen= BYellow= BBlue= BPurple= BCyan= BWhite=
    UBlack= URed= UGreen= UYellow= UBlue= UPurple= UCyan= UWhite=
fi
