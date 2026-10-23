#!/bin/sh
# zz-workspaces [<dir>] — list the runnable workspaces of the package in <dir>
# (default: the current directory), sorted by config.order, one per line:
#   order US name US dir US description US default US deps US conflicts US bin US summary
# (US = \037, which keeps empty fields: a tab would collapse them). name has
# its @scope/ removed; dir is relative to <dir>; deps and conflicts are
# comma-separated names; default is true|false; bin is the first bin file;
# summary is true|false (config.summary: the bin has a "summary" action).
# Runnable = has a "bin" that exists and an "engines.zz-setup" field.
# Prints nothing when there is no package.json or no runnable workspace.

. zz-colors

# --- arguments
eval "$(
    zz-args "List the runnable workspaces of a package" "$0" "$@" <<help
- dir dir Package directory (default: current directory)
help
)"

# --- parameters
cd "${dir:-.}" || {
    zz-log e "No such directory: {Purple ${dir}}"
    exit 1
}
[ -f package.json ] || exit 0
command -v jq >/dev/null 2>&1 || zz-install jq || exit 1
us=$(printf '\037')

# --- list: one jq call per workspace emits every field at once.
all=$(jq -r '(.workspaces // []) | (if type == "array" then . else .packages // [] end) | .[]' package.json)
for w in $all; do
    [ -f "$w/package.json" ] || continue
    row=$(jq -r --arg d "$w" '
      select((.bin != null) and ((.engines // {}) | has("zz-setup")))
      | [ (.config.order // 1000 | tostring),
          (.name | sub("^@[^/]*/"; "")),
          $d,
          ((.description // "") | gsub("[\n\r]"; " ")),
          ((.config.default // false) | tostring),
          (((.dependencies // {}) + (.peerDependencies // {})) | keys | map(sub("^@[^/]*/"; "")) | join(",")),
          ((.config.conflicts // []) | map(sub("^@[^/]*/"; "")) | join(",")),
          (.bin | if type == "string" then . else (to_entries[0].value // "") end),
          ((.config.summary // false) | tostring) ]
      | join("\u001f")' "$w/package.json")
    [ -n "$row" ] || continue
    bin=$(printf '%s' "$row" | cut -d"$us" -f8)
    [ -f "$w/$bin" ] || continue
    printf '%s\n' "$row"
done | sort -t "$us" -n -k1,1
