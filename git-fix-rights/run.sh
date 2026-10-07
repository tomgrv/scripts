#!/bin/sh

eval $(
	zz-args "Fix git access rights - set appropriate permissions for files and directories" $0 "$@" <<-help

	help
)

cd "$(git rev-parse --show-toplevel)" >/dev/null

# Only touches files tracked by git, not ignored/untracked ones
set_permissions() {
    perm="$1"
    shift
    zz-log i "Setting permissions $perm for: ${*:-<all tracked files>}"
    git ls-files -z "$@" | xargs -0 -r chmod "$perm"
}

set_permissions 644
set_permissions 755 '*.sh'
set_permissions 600 '*.conf' '*.env'

# git does not track directories, so derive them from the working tree instead
find "." -type d -not -path '*/.git' -not -path '*/.git/*' -exec chmod 755 {} +

find "." -type d \( -name logs -o -name cache \) -not -path '*/.git/*' -exec chmod 700 {} +

zz-log s "Access rights have been set according to best practices."
