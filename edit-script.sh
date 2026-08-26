#!/bin/sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "${SCRIPT_DIR}/zz_wrap.sh" 2>/dev/null || . zz_wrap

eval $(
	zz_args "Allow script editing" $0 "$@" <<-help
		- script    script       script to edit
	help
)

if [ ! -f "/usr/local/bin/$script" ]; then
	echo "Script $script is not defined in /usr/local/bin."
	exit 1
fi

cp /usr/local/bin/$script ./$script
chmod +x ./$script

code ./$script

zz_log i "Script {Purple $script} copied to current directory and opened in code editor."
