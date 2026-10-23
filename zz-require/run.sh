#!/bin/sh
# zz-require [-n name] <requirement>... — check what a step needs from its host,
# before it changes anything. A requirement is `root` (running as root) or
# `os=<id>` (/etc/os-release ID, e.g. os=ubuntu). Exits 1, saying which one is
# missing, on the first that is not met.

. zz-colors

eval "$(
    zz-args "Check the requirements of a step" "$0" "$@" <<help
n name name Name of the step, for the messages
# requirements requirements root, os=<id>
help
)"

who=${name:-this step}

for req in "$@"; do
    case "$req" in
    root)
        [ "$(id -u)" -eq 0 ] || {
            zz-log e "$who must run as root (use sudo)"
            exit 1
        }
        ;;
    os=*)
        want=${req#os=}
        # shellcheck disable=SC1091
        have=$(. /etc/os-release 2>/dev/null && printf '%s' "$ID")
        [ "$have" = "$want" ] || {
            zz-log e "$who targets $want only (detected: ${have:-unknown})"
            exit 1
        }
        ;;
    *)
        zz-log e "Unknown requirement {Purple $req} (expected root or os=<id>)"
        exit 1
        ;;
    esac
done
