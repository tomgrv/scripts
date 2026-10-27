#!/bin/sh
# zz-interactive — exit 0 when the caller may ask the user something, 1 otherwise. The one
# test behind every menu and prompt:
#   ZZ_INTERACTIVE=0   never (unattended run)
#   stdin is a terminal         yes
#   otherwise (curl | sh...)    yes when a controlling terminal can be read, as zz-prompt does
#                               (ZZ_PROMPT_TTY=0 turns that off)
# SYSTEM_ACCESS_MENU=false is honoured as ZZ_INTERACTIVE=0 (older name).

[ "${ZZ_INTERACTIVE:-}" != 0 ] || exit 1
[ "${SYSTEM_ACCESS_MENU:-}" != false ] || exit 1
[ -t 0 ] && exit 0
[ "${ZZ_PROMPT_TTY:-1}" != 0 ] && (: </dev/tty) 2>/dev/null
