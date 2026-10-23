#!/bin/sh

. zz-colors

eval "$(
    zz-args "List workspace directories and affected workspaces" "$0" "$@" <<help
        r   range     range       Git range to check for affected workspaces (prints only affected workspaces)
        b   -         bin_flag    Keep only workspaces with a "bin" file that exists
        e   engine    engine      Keep only workspaces with an engines.<engine> entry
        o   -         order_flag  Sort by config.order (default 1000), declaration order for ties
        -   dir       dir         Package directory (default: the git toplevel, else the current directory)
help
)"

cd "${dir:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}" || {
    zz-log e "No such directory: {Purple ${dir}}"
    exit 1
}
command -v jq >/dev/null 2>&1 || zz-install jq || exit 1

list_workspace_dirs() {
    if [ -f "package.json" ]; then
        local workspaces
        workspaces=$(jq -r '(.workspaces // []) | (if type == "array" then . else .packages // [] end) | .[]' package.json 2>/dev/null || true)

        if [ -n "$workspaces" ]; then
            echo "$workspaces" | while read -r workspace_pattern; do
                if echo "$workspace_pattern" | grep -q '\*'; then
                    find . -path "./$workspace_pattern" -type d -mindepth 1 -maxdepth 2 2>/dev/null | sort || true
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
    local range="$1" dirs file d

    if [ -z "$range" ]; then
        return 0
    fi

    dirs=$(list_workspace_dirs)
    git log --name-only --pretty=format: "$range" 2>/dev/null | sort -u \
        | while read -r file; do
            [ -n "$file" ] || continue
            case "$file" in
            */*) ;;
            *) echo "." ;; # Root-level files (no path separator) belong to "."
            esac
            echo "$dirs" | while read -r d; do
                case "$file" in "${d#./}"/*) echo "$d" ;; esac
            done
        done
}

# select_workspaces: keep the directories on stdin matching -b / -e, ordered
# by config.order with -o (one jq call per directory).
select_workspaces() {
    local d row us
    us=$(printf '\037')
    while read -r d; do
        [ -f "$d/package.json" ] || continue
        row=$(jq -r --arg e "$engine" --arg b "$bin_flag" '
          select(($b == "" or .bin != null) and ($e == "" or ((.engines // {}) | has($e))))
          | [ (.config.order // 1000 | tostring),
              (.bin | if type == "string" then . elif type == "object" then (to_entries[0].value // "") else "" end) ]
          | join("\u001f")' "$d/package.json")
        [ -n "$row" ] || continue
        [ -z "$bin_flag" ] || [ -f "$d/${row#*"$us"}" ] || continue
        printf '%s%s%s\n' "${row%%"$us"*}" "$us" "$d"
    done | if [ -n "$order_flag" ]; then sort -s -t "$us" -n -k1,1; else cat; fi | cut -d "$us" -f2-
}

{
    if [ -n "$range" ]; then
        get_affected_workspaces "$range" | sort -u
    else
        list_workspace_dirs
    fi
} | if [ -n "$bin_flag$engine$order_flag" ]; then select_workspaces; else cat; fi
