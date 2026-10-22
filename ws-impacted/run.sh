#!/bin/sh
set -e

eval $(
    zz-args "Print the list-packages filter selecting the workspaces impacted by changed files" $0 "$@" <<help
        r   range     range       Git range whose changed files are used (default: read one path per line on stdin)
help
)

cd "$(git rev-parse --show-toplevel)"

# Changed files; Markdown impacts nobody.
if [ -n "$range" ]; then
    changed=$(git diff --name-only "$range")
else
    changed=$(cat)
fi
changed=$(printf '%s\n' "$changed" | grep -v '\.md$' || true)

# Workspaces with a package.json, as {dir, name, deps}; ws-list enumerates the directories.
workspaces=$(
    ws-list | sed 's|^\./||' | while read -r dir; do
        [ -f "$dir/package.json" ] || continue
        jq -c --arg dir "$dir" '{
            dir: $dir,
            name: .name,
            deps: ([.dependencies, .peerDependencies, .devDependencies, .optionalDependencies] | map(keys? // []) | add)
        }' "$dir/package.json"
    done | jq -cs '.'
)

# A workspace is impacted when it owns a changed file or (transitively) depends on one
# that does. A changed file owned by no workspace (root manifest, shared test helpers,
# workflows...) impacts everybody: nothing is printed, which keeps every workspace.
jq -rn --argjson ws "$workspaces" --arg files "$changed" '
    def grow($ws): . as $s | ($s + [$ws[] | select(any(.deps[]; . as $d | $s | any(. == $d))) | .name]) | unique;
    ($files | split("\n") | map(select(length > 0))) as $changed
    | ($changed | map(. as $f | ($ws | map(select(.dir as $d | $f | startswith($d + "/"))) | .[0] // null))) as $owners
    | if any($owners[]; . == null) then ""
      else
        ([$owners[].name] | unique | until(grow($ws) == .; grow($ws))) as $names
        | [$ws[] | select(.name | IN($names[])) | .dir] as $dirs
        | if ($dirs | length) == 0 then "false"
          else "(.location | IN(" + ($dirs | map(@json) | join(",")) + "))"
          end
      end'
