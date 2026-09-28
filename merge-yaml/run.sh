#!/bin/sh
set -e

. zz_colors

eval $(
    zz_args "Merge 2 yaml files" $0 "$@" <<-help
        i indent      indent    ignored (kislyuk/yq always writes 2-space indents)
        - target      target		Target YAML file to merge into
        - source      source		Source YAML file to merge from
help
)

if [ -z "$target" ] || [ -z "$source" ]; then
    zz_log e "Usage: merge-yaml <target> <source>"
    exit 1
fi

# The pipeline below uses kislyuk/yq (python, a jq wrapper; apt's `yq`):
# `yq .` transcodes YAML to JSON, `yq -y` transcodes JSON back to YAML.
# mikefarah/yq (Go) has an incompatible CLI.
command -v yq >/dev/null 2>&1 || zz_use yq
if ! yq --help 2>&1 | grep -q 'jq wrapper'; then
    zz_log e "merge-yaml requires kislyuk/yq (jq wrapper), found {U $(command -v yq || echo none)}"
    exit 1
fi

# kislyuk/yq always emits 2-space indents; -i is accepted for compatibility.
[ -z "$indent" ] || [ "$indent" = 2 ] || zz_log d "Indent {U $indent} not supported by kislyuk/yq, using 2"

if [ ! -f "$target" ]; then
    zz_log e "Target file {U $target} not found"
    exit 1
elif ! yq_err=$(yq . "$target" 2>&1 >/dev/null); then
    zz_log e "Target file {U $target} is not a valid YAML: $yq_err"
    exit 1
fi

if [ "$source" = "-" ]; then
    source=/dev/stdin
fi

zz_log i "Merging YAML from {U $source} into {U $target}..."

target_json=$(yq . "$target")
source_json=$(yq . "$source")

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
' | yq -y --yaml-output-grammar-version 1.2 --width 4096 . >/tmp/$$.merge && mv /tmp/$$.merge "$target" && zz_log s "YAML merged successfully"
