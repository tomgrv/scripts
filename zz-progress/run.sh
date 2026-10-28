#!/bin/sh
# zz-progress [<message>] — a transient progress line, for the slow part before a menu
# (reading files, running jq...). With a message it replaces the current line on stderr;
# without one it clears the line. Nothing is written off a terminal.
#   zz-progress "Reading the inputs..."
#   ... slow work ...
#   zz-progress

# No argument parser: this is called around work that is already slow.
[ -t 2 ] || exit 0
printf '\r\033[K%s' "${1:-}" >&2
