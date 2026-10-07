#!/bin/sh
# zz — front door to the zz-* family. `zz <name> [args...]` runs `zz-<name>`
# when it is available, exactly like a dispatcher; otherwise it installs
# <name> on demand and runs it, i.e. `zz-use -x <name> [args...]`.
#
#   zz log i "hello"      -> zz-log i "hello"
#   zz json merge a b     -> (no zz-json) zz-use -x json merge a b
#
# Deliberately free of any dependency (not even zz-log): this is the command
# you reach for when nothing else is installed yet.

if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    {
        echo "[i] Usage: zz <name> [args...]"
        echo "    Runs zz-<name> when installed, else installs <name> and runs it (zz-use -x)."
    } >&2
    exit 1
fi

name=$1
shift

if command -v "zz-${name}" >/dev/null 2>&1; then
    exec "zz-${name}" "$@"
fi

exec zz-use -x "${name}" "$@"
