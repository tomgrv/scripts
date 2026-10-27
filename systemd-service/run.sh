#!/bin/sh
# systemd-service [-r] <up|down> <unit>... — up: enable --now each unit (-r: restart it
# too, to pick up a new config) and fail when one is not active afterwards; down:
# disable --now each unit, a unit that is not there is not an error.

. zz-colors

eval "$(
    zz-args "Enable or disable systemd units and check they run" "$0" "$@" <<help
r - restart_flag Restart the units after enabling them (up only)
- action action up or down
# units units Units to act on (left in "$@")
help
)"

case "$action" in
up | down) ;;
*)
    zz-log e "Usage: systemd-service [-r] <up|down> <unit>..."
    exit 1
    ;;
esac
[ "$#" -gt 0 ] || {
    zz-log e "Usage: systemd-service [-r] <up|down> <unit>..."
    exit 1
}

if [ "$action" = down ]; then
    systemctl disable --now "$@" 2>/dev/null || true
    exit 0
fi

for unit in "$@"; do
    systemctl enable --now "$unit"
    [ -z "$restart_flag" ] || systemctl restart "$unit"
    # a .socket or .timer is the active part of its pair, so the check is the same for any unit
    systemctl is-active --quiet "$unit" || {
        zz-log e "$unit is not active after 'systemctl enable --now $unit' (see: journalctl -u $unit)."
        exit 1
    }
done
