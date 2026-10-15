#!/bin/sh

eval $(
    zz-args "List workspace directories and affected workspaces" $0 "$@" <<-help
        r   range     range       Git range to check for affected workspaces (prints only affected workspaces)
help
)

cd "$(git rev-parse --show-toplevel)"

list_workspace_dirs() {
    if [ -f "package.json" ] && command -v jq >/dev/null 2>&1; then
        local workspaces
        workspaces=$(jq -r '.workspaces[]? // empty' package.json 2>/dev/null || true)

        if [ -n "$workspaces" ]; then
            echo "$workspaces" | while read -r workspace_pattern; do
                if echo "$workspace_pattern" | grep -q '\*'; then
                    find . -path "./$workspace_pattern" -type d -mindepth 1 -maxdepth 2 2>/dev/null || true
                else
                    if [ -d "$workspace_pattern" ]; then
                        echo "./$workspace_pattern"
                    fi
                fi
            done
            return 0
        fi
    fi

    find . -mindepth 1 -maxdepth 1 -type d
}

get_affected_workspaces() {
    local range="$1"

    if [ -z "$range" ]; then
        return 0
    fi

    git log --name-only --pretty=format: "$range" 2>/dev/null \
        | while read -r line; do
            if [ -n "$line" ]; then
                list_workspace_dirs | while read -r workspace_dir; do
                    workspace_dir_clean=$(echo "$workspace_dir" | sed 's|^./||')
                    if echo "$line" | grep -q "^$workspace_dir_clean/"; then
                        echo "$workspace_dir"
                    fi
                done
                # Root-level files (no path separator) belong to "."
                if ! echo "$line" | grep -q "/"; then
                    echo "."
                fi
            fi
        done
}

if [ -n "$range" ]; then
    get_affected_workspaces "$range" | sort -u
else
    list_workspace_dirs
fi
