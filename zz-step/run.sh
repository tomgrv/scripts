#!/bin/sh
# . zz-step — SOURCE it (it runs in the caller's shell) at the end of a zz-setup
# step, after defining its up(), down() and summary() functions. It runs the
# one named by the step's first argument (default up):
#   up, down  first check config.requires of the step's package.json (see
#             zz-require), then run the function; down without down() is an error;
#   summary   run summary() if the step has one, else print nothing.
# Anything else is an error. The step's own package.json is the one beside $0.

step_action=${1:-up}

case "$step_action" in
up | down)
    step_requires=$(jq -r '(.config.requires // {}) | to_entries[] | if .value == true then .key else "\(.key)=\(.value)" end' "$(dirname "$0")/package.json" 2>/dev/null) || step_requires=
    # shellcheck disable=SC2086
    [ -z "$step_requires" ] || zz-require -n "$(basename "$(cd "$(dirname "$0")" && pwd)")" $step_requires || exit 1
    if [ "$step_action" = up ]; then
        up
    elif command -v down >/dev/null 2>&1; then
        down
    else
        zz-log e "This step has no 'down' action (nothing to undo)."
        exit 1
    fi
    ;;
summary)
    if command -v summary >/dev/null 2>&1; then summary; fi
    ;;
*)
    zz-log e "Unknown action '$step_action' (expected 'up', 'down' or 'summary')."
    exit 1
    ;;
esac
