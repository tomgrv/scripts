#!/bin/sh
# zz-call — resolve a caller's declared env vars with zz-vars (ask+persist if
# missing), then either exec a command with them exported, or print the
# `export` lines for the caller to `eval`. Resolving, and what a package.json
# can declare ("config.inputs", "config.output", "config.ports", "config.file"),
# is zz-vars's; running the command is all that is zz-call's.
#
# Usage:
#   zz-call [-p package.json[:more.json]] [-f envfile] [-P profile] [-n] [-e]
#           [command [args...]]
#   -p  package.json file(s) to read, ':'-separated (default: ./package.json)
#   -f  env file to read/persist (default: config.file of the first package.json, else .env)
#   -P  also export persisted values from <ZZ_PROFILE_DIR, default /etc/profile.d>/<profile>.sh
#   -n  never prompt: a missing var falls back to its default, not persisted
#   -e  also persist values already set in the environment
# With a command, every output (default: each input, under its name and alias)
# is exported to it.

set -e

. zz-colors

# --- arguments
eval "$(
    zz-args "Resolve a caller's declared env vars (ask+persist if missing), then run a command" $0 "$@" <<help
        p package   package     package.json file(s) to read, ':'-separated (default: ./package.json)
        f file      envfile     Env file to read and persist to (default: config.file, else .env)
        P profile   profile     Also export persisted values from <ZZ_PROFILE_DIR, default /etc/profile.d>/<profile>.sh
        n -         noprompt    Never prompt: missing vars fall back to their default (not persisted)
        e -         persistenv  Also persist values already set in the environment
        # cmd        cmd         Command (and args) to run once every input var is resolved
help
)"

# --- parameters: the package.json files and the env file.
pkgs="${package:-./package.json}"
first=${pkgs%%:*}
for pkg_file in $(printf '%s' "$pkgs" | tr ':' ' '); do
    [ -f "$pkg_file" ] || {
        zz-log e "No package.json found at {U $pkg_file}"
        exit 1
    }
done

file="${envfile:-$(jq -r '.config.file // ".env"' "$first")}"

# --- functions

# resolve <package.json>...: zz-vars on these files, each as a workspace named
# after its folder.
resolve() {
    local pkg_file
    local mode=-a

    [ -z "$noprompt" ] || mode=-n

    for pkg_file; do
        set -- "$@" "$(basename "$(cd "$(dirname "$pkg_file")" && pwd)")=$pkg_file"
        shift
    done
    zz-vars "$mode" ${persistenv:+-e} -f "$file" ${profile:+-P "$profile"} "$@"
}

# --- resolve, then run the command or print the export lines.
out=$(resolve $(printf '%s' "$pkgs" | tr ':' ' '))
if [ "$#" -gt 0 ]; then
    eval "$out"
    exec "$@"
fi
printf '%s\n' "$out"
