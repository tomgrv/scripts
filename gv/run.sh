#!/bin/sh

# Call GitVersion against this repo's .gitversion configuration. Tries each
# backend in $steps, in order: if its run command isn't already on PATH,
# runs that backend's own config/install-<name>.sh (which decides for
# itself whether it even *can* install -- e.g. install-docker.sh no-ops
# out when Docker isn't actually usable) and re-checks; the first backend
# whose run command resolves is the one gv uses.
#
# Adding a backend is: one more "name:run-command" entry in $steps, a
# config/install-<name>.sh next to this file, and a run_<name> function
# below with that backend's own calling convention (docker-gitversion and
# dotnet-gitversion don't take the same arguments, so this only unifies
# the *dispatch* across backends, not their individual CLIs).
#
# Neither step exits on its own -- nothing is invoked until a run command
# is confirmed actually resolvable, and the one call after the loop is
# what runs it or fails loudly. That keeps a failed install (network down,
# no GitVersion.Tool feed, etc.) from aborting silently mid-script via
# `set -e`: it just leaves that backend's run command unresolved, so the
# loop moves on to the next one, or falls through to the same clear error
# every "nothing worked" case hits.

set -eu

dir=$(dirname "$(readlink -f "$0")")

run_docker() {
    exec docker-gitversion -config ".gitversion" "$@"
}

run_dotnet() {
    exec dotnet-gitversion "$(git rev-parse --show-toplevel)" -config ".gitversion" "$@"
}

# <name>:<run-command-to-check-on-PATH>, tried in this order.
steps="docker:docker-gitversion dotnet:dotnet-gitversion"

for step in $steps; do
    name=${step%%:*}
    check=${step#*:}

    if ! command -v "$check" > /dev/null 2>&1; then
        sh "$dir/config/install-$name.sh" || true
    fi

    if command -v "$check" > /dev/null 2>&1; then
        zz_log s "Using $name ($check)"
        run_"$name" "$@"
    fi
done

zz_log e "Could not run GitVersion -- none of these backends resolved: $steps"
exit 1
