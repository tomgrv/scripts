#!/bin/sh
# Dispatcher utility used by scripts named with a leading underscore.
# Example caller: src/gitutils/_git-fix.sh invokes: dispatch-script $0 "$@"
# This script finds a counterpart script without the leading underscore
# in the same directory (or with .sh extension) and executes it.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "${SCRIPT_DIR}/zz_wrap.sh" 2>/dev/null || . zz_wrap

eval $(
     zz_args "Dispatch Utility" $0 "$@" <<- help
		-   caller caller     Caller script path
        -   subcmd subcmd     Target script to execute
        d   debug  debug      Enable debug mode
        #   params params     Remaining arguments passed to the target script
	help
)

usage() {
    zz_log i "Usage: ${name} <subcommand> [args...]" >&2
    if [ -d "${caller_dir}" ]; then
        zz_log - "Available utilities in ${caller_dir}:" >&2
        ls -1 "${caller_dir}" | grep -E "${name}(-.*)(\.sh)?$" | sed -e 's/^/_/' -e 's/^_\?//' | sed 's/^/    /' >&2 || true
    fi
}

caller_basename=$(basename "${caller}")
caller_dir=$(dirname "${caller}")

name=${caller_basename#_}
name=${name%.*}

if [ -z "${subcmd}" ]; then
    zz_log e "No subcommand provided." && usage $caller
    exit 1
fi

if [ "${caller_dir}" = "${caller_basename}" ] || [ -z "${caller_dir}" ]; then
    caller_dir="."
fi

if [ -n "${subcmd}" ]; then
    target="${caller_dir}/${name}-${subcmd}"
else
    target="${caller_dir}/${name}"
fi

if [ -x "${target}" ]; then
    zz_log i "Dispatching to executable target: ${target}"
    eval exec "${target}" $params
elif [ -f "${target}" ]; then
    zz_log i "Dispatching to subshell target: ${target}"
    eval exec sh "${target}" $params
else
    zz_log w "No dispatch target found" && usage
fi
