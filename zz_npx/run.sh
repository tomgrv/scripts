#!/bin/sh
# zz_npx — run a locally installed npm package binary directly, skipping
# npx's per-invocation resolution overhead. Falls back to npx only when
# the binary isn't present locally, and only if npx itself is available.
#
# The npx fallback may install <tool> on the fly, so its lifecycle scripts
# are untrusted and skipped (--ignore-scripts) by default. Pass -s to allow
# them to run.
#
# -i installs <tool> (and <args>, treated as extra packages) as dev
# dependencies first, quietly (npm install -q -D --no-audit --no-fund),
# before running it.

zz_use zz_colors zz_args
. zz_colors

eval $(
	zz_args "Run a local npm binary, falling back to npx" $0 "$@" <<-help
		s   -    withscripts  Allow npx's on-the-fly install to run lifecycle scripts
		i   -    install      Install <tool> and <args> as dev dependencies first (npm install -q -D --no-audit --no-fund)
		-   tool tool         Package binary to run
		#   args args         Arguments passed through to <tool> (extra packages to install, when -i is used)
	help
)

if [ -z "$tool" ]; then
    zz_log e "Usage: zz_npx [-s] [-i] <tool> [args...]"
    exit 1
fi

if [ -n "$install" ]; then
    install_output="$(eval npm install -q -D --no-audit --no-fund "$tool" $args 2>&1)"
    install_status=$?
    if [ ${install_status} -ne 0 ]; then
        zz_log e "$install_output"
        exit ${install_status}
    fi
    exit 0
fi

bin="${INIT_CWD:-$PWD}/node_modules/.bin/$tool"

if [ -x "$bin" ]; then
    eval exec "$bin" $args
fi

if command -v npx >/dev/null 2>&1; then
    if [ -n "$withscripts" ]; then
        eval exec npx --yes "$tool" $args
    else
        eval exec npx --yes --ignore-scripts "$tool" $args
    fi
fi

zz_log e "Cannot run {B $tool}: not found in node_modules/.bin and npx is not available."
exit 1
