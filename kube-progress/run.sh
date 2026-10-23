#!/bin/sh
# kube-progress [-i seconds] <namespace> <label> <command...> — run a command as
# is (its output and exit status untouched) and, while it works, log a status
# line every few seconds: elapsed time, pods ready/total in the namespace and
# what the others are doing (ContainerCreating, ImagePullBackOff...), so a long
# `helm --wait` or `kubectl rollout status` does not look frozen.

. zz-colors

eval "$(
    zz-args "Run a command, logging the pod status of a namespace while it works" "$0" "$@" <<help
i seconds interval Seconds between status lines (default: PROGRESS_INTERVAL, else 15)
- namespace namespace Kubernetes namespace to watch
- label label Label of the status lines
# command command Command to run, with its arguments
help
)"

# --- parameters
if [ -z "$namespace" ] || [ -z "$label" ] || [ "$#" -eq 0 ]; then
    zz-log e "Usage: kube-progress [-i seconds] <namespace> <label> <command...>"
    exit 1
fi
interval=${interval:-${PROGRESS_INTERVAL:-15}}

# --- functions

# progress_line <elapsed>: one status line for the namespace.
progress_line() {
    local elapsed="$1" # seconds since the command started (mandatory)
    local pods ready total waiting

    pods=$(kubectl -n "$namespace" get pods --no-headers 2>/dev/null || true)
    if [ -z "$pods" ]; then
        zz-log i "$label: ${elapsed}s, no pod in $namespace yet (chart and images are still being fetched)..."
        return
    fi
    total=$(printf '%s\n' "$pods" | grep -c .)
    ready=$(printf '%s\n' "$pods" | awk '$3 == "Completed" || ($3 == "Running" && split($2, a, "/") && a[1] == a[2]) { n++ } END { print n + 0 }')
    waiting=$(printf '%s\n' "$pods" | awk '$3 != "Completed" && !($3 == "Running" && split($2, a, "/") && a[1] == a[2]) { printf "%s=%s ", $1, $3 }')
    zz-log i "$label: ${elapsed}s, $ready/$total pods ready${waiting:+ - waiting: $waiting}"
}

# --- run: a watcher in the background, the command in the foreground
parent=$$
start=$(date +%s)
(
    while sleep "$interval"; do
        kill -0 "$parent" 2>/dev/null || exit 0
        progress_line "$(($(date +%s) - start))"
    done
) &
watcher=$!
rc=0
"$@" || rc=$?
kill "$watcher" 2>/dev/null || true
wait "$watcher" 2>/dev/null || true
exit "$rc"
