#!/bin/sh
# zz-step — the up|down|summary entry point of a step. Meant to be sourced as the
# last line of a step's run.sh: `. zz-step`. It calls the caller's up() / down() /
# summary() (summary is optional) with the caller's arguments.

case "${1:-}" in
    up | down) "$1" ;;
    summary) if command -v summary >/dev/null 2>&1; then summary; fi ;;
    *) zz-log e "Usage: $0 up|down|summary" && exit 1 ;;
esac
