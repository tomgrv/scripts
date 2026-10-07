#!/bin/sh
set -e

. zz-colors

eval $(
    zz-args "Merge 2 yaml files" $0 "$@" <<-help
        i indent      indent    indent size (default: 2)
        - target      target		Target YAML file to merge into
        - source      source		Source YAML file to merge from
help
)

if [ -z "$target" ] || [ -z "$source" ]; then
    zz-log e "Usage: yaml-merge <target> <source>"
    exit 1
fi

# The pipeline below uses mikefarah/yq (Go, v4): `yq -o=json` transcodes
# YAML to JSON, `yq -p=json -o=yaml` transcodes JSON back to YAML.
# kislyuk/yq (python jq wrapper; apt's `yq`) has an incompatible CLI.
command -v yq >/dev/null 2>&1 || zz-use yq
if ! yq --version 2>&1 | grep -q 'mikefarah'; then
    zz-log e "yaml-merge requires mikefarah/yq (https://github.com/mikefarah/yq), found {U $(command -v yq || echo none)}"
    exit 1
fi

indent=${indent:-2}

if [ ! -f "$target" ]; then
    zz-log e "Target file {U $target} not found"
    exit 1
elif ! yq_err=$(yq -o=json . "$target" 2>&1 >/dev/null); then
    zz-log e "Target file {U $target} is not a valid YAML: $yq_err"
    exit 1
fi

if [ "$source" = "-" ]; then
    source=/dev/stdin
fi

zz-log i "Merging YAML from {U $source} into {U $target}..."

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# An empty source reads as null and leaves the target unchanged. A target
# with no content (blank or comments only) takes the source as is; an
# explicit null target is content and wins like any other value.
target_json=$(yq -o=json . "$target")
source_json=$(yq -o=json . "$source")
grep -q '^[[:space:]]*[^#[:space:]]' "$target" || target_json=

jq -n --argjson a "${target_json:-"{}"}" --argjson b "${source_json:-null}" '
def dedupe_ordered:
  reduce .[] as $x ([]; if any(.[]; . == $x) then . else . + [$x] end);

# Identity key of an array element: "id" if present, else "name", else none.
def idkey:
  if type == "object" then
    (if has("id") then "id" elif has("name") then "name" else null end)
  else null end;

def merge($a; $b):
  # Reconcile arrays: elements sharing the same id (or name) are merged in
  # place; other elements are unioned and deduped as plain values.
  def merge_arrays($a; $b):
    reduce $b[] as $x ($a | dedupe_ordered;
      ($x | idkey) as $k
      | if $k != null then
          (to_entries
           | map(select(.value | type == "object" and has($k) and .[$k] == $x[$k]))
           | first | .key) as $i
          | if $i != null then .[$i] = merge(.[$i]; $x) else . + [$x] end
        elif any(.[]; . == $x) then .
        else . + [$x] end);
  if ($a | type) == "object" and ($b | type) == "object" then
    (($a | keys_unsorted) + (($b | keys_unsorted) - ($a | keys_unsorted))) as $k_all
    | reduce $k_all[] as $k ({};
      .[$k] =
        if ($a | has($k)) then
          if ($a[$k] | type) == "array" and ($b[$k] | type) == "array" then
            merge_arrays($a[$k]; $b[$k])
          else
            merge($a[$k]; $b[$k])
          end
        else
          $b[$k]
        end
    )
  else
    $a
  end;

merge($a; $b)
' | yq -p=json -o=yaml -P . >"$tmp/merged"

# jq only computes the merged values; overlay them onto the original target
# (yq "merge files" idiom) so its comments, key order and flow/block styles
# survive. The merged document is a superset of the target with the target's
# values, so the overlay only extends arrays and adds keys.
# See https://mikefarah.gitbook.io/yq/usage/tips-and-tricks
if [ -n "$target_json" ]; then
    yq ea -I "$indent" 'select(fi == 0) * select(fi == 1)' "$target" "$tmp/merged" >"$tmp/merge"
else
    yq -I "$indent" . "$tmp/merged" >"$tmp/merge"
fi
mv "$tmp/merge" "$target" && zz-log s "YAML merged successfully"
