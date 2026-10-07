#!/bin/sh
set -e

. zz-colors

eval $(
	zz-args "Distribute zz-* / utility scripts to target directory" $0 "$@" <<-help
		t target    target       Target directory (required unless specified in config)
		s source    source       Source directory (default: /usr/local/share/common-utils)
		q -         quiet        Quiet mode: exit 0 if no target found instead of error
	help
)

get_target_from_config() {
	local config_target=""

	if [ -f ".zz_dist" ]; then
		config_target=$(cat .zz_dist | head -n 1 | tr -d '\r\n ')
		if [ -n "$config_target" ]; then
			zz-log i "Found target in {U .zz_dist}: {B $config_target}"
			echo "$config_target"
			return 0
		fi
	fi

	if [ -f "package.json" ]; then
		config_target=$(json-load package.json 2>/dev/null | jq -r '.config.zz_dist // empty' 2>/dev/null)
		if [ -n "$config_target" ]; then
			zz-log i "Found target in {U package.json}: {B $config_target}"
			echo "$config_target"
			return 0
		fi
	fi
}

if [ -z "$target" ]; then
	target=$(get_target_from_config);
	if [ -z "$target" ] && [ -n "$quiet" ]; then
		zz-log w "No target directory specified. Exiting quietly."
		exit 0
	elif [ -z "$target" ]; then
		zz-log e "No target directory specified. Use -t option, create .zz_dist file, or add config.zz_dist in package.json"
		exit 1
	fi
fi

target=$(readlink -f "$target")

if [ ! -d "$target" ]; then
	zz-log e "Target directory {U $target} does not exist"
	exit 1
fi

zz-log s "Resolved target directory to {U $target}"

if [ -z "$source" ]; then
	if [ -d "/usr/local/share/common-utils" ]; then
		source="/usr/local/share/common-utils"
	elif [ -d "/usr/local/bin" ]; then
		source="/usr/local/bin"
	else
		zz-log e "No source directory found. Expected /usr/local/share/common-utils or /usr/local/bin"
		exit 1
	fi
fi

zz-log i "Distributing utility scripts"
zz-log - "From: {U $source}"
zz-log - "To: {U $target}"

for file in $(ls -1 $source/*zz-* 2>/dev/null); do

	zz-log - "Processing file: {U $file}"

	if [ -f "$file" ] || [ -L "$file" ]; then
		basefile=$(basename "$file")
		if echo "$basefile" | grep -q '^_zz-.*\.sh$'; then
			targetfile=$target/$(echo "$basefile" | sed -e 's/^_//;s/\.sh$//')
		else
			targetfile=$target/$basefile
		fi

		if [ -x "$file" ]; then
			cp -u "$file" "$targetfile"
			chmod +x "$targetfile"
			zz-log s "Copied {U $basefile} to {U $targetfile}"
		else
			zz-log w "Skipping non-executable file {U $basefile}"
		fi
	fi
done

zz-log s "Successfully distributed utilities to {U $target}"
