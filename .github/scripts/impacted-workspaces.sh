#!/usr/bin/env bash
# Prints the `filter` input for tomgrv/actions/list-packages that keeps only the
# workspaces impacted by the changed files read on stdin (one path per line):
# the workspaces owning a changed file, plus (transitively) the ones depending on
# them. Markdown impacts nobody. A changed file owned by no workspace (root
# manifest, shared test helpers, workflows...) impacts everybody: nothing is printed,
# which keeps every workspace.
#
# Usage: git diff --name-only HEAD^1 HEAD | .github/scripts/impacted-workspaces.sh
# Env:   WORKDIR  repository root holding the workspaces' package.json (default: .)
set -euo pipefail
cd "${WORKDIR:-.}"

workspaces=$(
  jq -r '.workspaces[]?' package.json | while read -r pattern; do
    for dir in $pattern; do
      [[ -f "$dir/package.json" ]] || continue
      jq -c --arg dir "${dir%/}" '{
        dir: $dir,
        name: .name,
        deps: ([.dependencies, .peerDependencies, .devDependencies, .optionalDependencies] | map(keys? // []) | add)
      }' "$dir/package.json"
    done
  done | jq -cs '.'
)

jq -rn --argjson ws "$workspaces" --rawfile files /dev/stdin '
  def grow($ws): . as $s | ($s + [$ws[] | select(any(.deps[]; . as $d | $s | any(. == $d))) | .name]) | unique;
  ($files | split("\n") | map(select(length > 0 and (endswith(".md") | not)))) as $changed
  | ($changed | map(. as $f | ($ws | map(select(.dir as $d | $f | startswith($d + "/"))) | .[0] // null))) as $owners
  | if any($owners[]; . == null) then ""
    else
      ([$owners[].name] | unique | until(grow($ws) == .; grow($ws))) as $names
      | [$ws[] | select(.name | IN($names[])) | .dir] as $dirs
      | if ($dirs | length) == 0 then "false"
        else "(.location | IN(" + ($dirs | map(@json) | join(",")) + "))"
        end
    end'
