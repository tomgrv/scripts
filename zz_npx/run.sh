#!/bin/sh
# zz_npx — run a locally installed npm package binary directly, skipping
# npx's per-invocation resolution overhead. Falls back to npx only when
# the binary isn't present locally, and only if npx itself is available.
#
# The npx fallback may install <tool> on the fly, so its lifecycle scripts
# are untrusted and skipped (--ignore-scripts) by default. Pass -s to allow
# them to run.

zz_use zz_colors zz_args
. zz_colors

eval $(
	zz_args "Run a local npm binary, falling back to npx" $0 "$@" <<-help
		s   -    withscripts  Allow npx's on-the-fly install to run lifecycle scripts
		-   tool tool         Package binary to run
		#   args args         Arguments passed through to <tool>
	help
)

if [ -z "$tool" ]; then
    zz_log e "Usage: zz_npx [-s] <tool> [args...]"
    exit 1
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
