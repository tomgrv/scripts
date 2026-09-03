#!/bin/sh

# Function to print help and manage arguments
eval $(
	zz_args "Fix git access rights - set appropriate permissions for files and directories" $0 "$@" <<-help

	help
)

# Navigate to the repository root
cd "$(git rev-parse --show-toplevel)" >/dev/null

# Apply the given permission to the tracked files matching the given pathspecs.
# Operates on files tracked by git (not ignored/untracked ones), matching the
# stated intent of normalising the repository's own file permissions.
set_permissions() {
    perm="$1"
    shift
    zz_log i "Setting permissions $perm for: ${*:-<all tracked files>}"
    git ls-files -z "$@" | xargs -0 -r chmod "$perm"
}

# Regular files default to 644, scripts to 755, sensitive files to 600
set_permissions 644
set_permissions 755 '*.sh'
set_permissions 600 '*.conf' '*.env'

# Directories default to 755 (git does not track directories, so derive them
# from the working tree, excluding the .git internals)
find "." -type d -not -path '*/.git' -not -path '*/.git/*' -exec chmod 755 {} +

# Tighten well-known sensitive directories (e.g. logs, cache) to 700
find "." -type d \( -name logs -o -name cache \) -not -path '*/.git/*' -exec chmod 700 {} +

zz_log s "Access rights have been set according to best practices."
