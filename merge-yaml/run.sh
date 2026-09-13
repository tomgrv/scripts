#!/bin/sh
set -e

zz_use zz_colors zz_args jq yq
. zz_colors

eval $(
    zz_args "Merge 2 yaml files" $0 "$@" <<-help
        i indent      indent    indent size for the merged YAML
        - target      target		Target YAML file to merge into
        - source      source		Source YAML file to merge from
help
)

if [ -z "$target" ] || [ -z "$source" ]; then
    zz_log e "Usage: merge-yaml <target> <source>"
    exit 1
fi

if [ ! -f "$target" ]; then
    zz_log e "Target file {U $target} not found"
    exit 1
elif ! yq eval '.' "$target" >/dev/null 2>&1; then
    zz_log e "Target file {U $target} is not a valid YAML"
    exit 1
fi

if [ "$source" = "-" ]; then
    source=/dev/stdin
fi

zz_log i "Merging YAML from {U $source} into {U $target}..."

target_json=$(yq -o=json eval '.' "$target")
source_json=$(yq -o=json eval '.' "$source")

jq -n --argjson a "$target_json" --argjson b "$source_json" '
def dedupe_ordered:
  reduce .[] as $x ([]; if any(.[]; . == $x) then . else . + [$x] end);

def merge($a; $b):
  if ($a | type) == "object" and ($b | type) == "object" then
    (($a | keys_unsorted) + (($b | keys_unsorted) - ($a | keys_unsorted))) as $k_all
    | reduce $k_all[] as $k ({};
      .[$k] =
        if ($a | has($k)) then
          if ($a[$k] | type) == "array" and ($b[$k] | type) == "array" then
            ($a[$k] + $b[$k]) | dedupe_ordered
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
' | yq -P eval -o=yaml --indent "${indent:-2}" '.' - >/tmp/$$.merge && mv /tmp/$$.merge "$target" && zz_log s "YAML merged successfully"
