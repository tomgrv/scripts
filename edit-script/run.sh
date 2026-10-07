#!/bin/sh
set -e

. zz-colors

eval $(
	zz-args "Allow script editing" $0 "$@" <<-help
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

zz-log i "Script {Purple $script} copied to current directory and opened in code editor."
