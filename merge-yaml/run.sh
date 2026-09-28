#!/bin/sh
set -e

. zz_colors

eval $(
    zz_args "Merge 2 yaml files" $0 "$@" <<-help
        i indent      indent    indent size (default: 2)
        - target      target		Target YAML file to merge into
        - source      source		Source YAML file to merge from
help
)

if [ -z "$target" ] || [ -z "$source" ]; then
    zz_log e "Usage: merge-yaml <target> <source>"
    exit 1
fi

# The pipeline below uses mikefarah/yq (Go, v4): `yq -o=json` transcodes
# YAML to JSON, `yq -p=json -o=yaml` transcodes JSON back to YAML.
# kislyuk/yq (python jq wrapper; apt's `yq`) has an incompatible CLI.
command -v yq >/dev/null 2>&1 || zz_use yq
if ! yq --version 2>&1 | grep -q 'mikefarah'; then
    zz_log e "merge-yaml requires mikefarah/yq (https://github.com/mikefarah/yq), found {U $(command -v yq || echo none)}"
    exit 1
fi

indent=${indent:-2}

if [ ! -f "$target" ]; then
    zz_log e "Target file {U $target} not found"
    exit 1
elif ! yq_err=$(yq -o=json . "$target" 2>&1 >/dev/null); then
    zz_log e "Target file {U $target} is not a valid YAML: $yq_err"
    exit 1
fi

if [ "$source" = "-" ]; then
    source=/dev/stdin
fi

zz_log i "Merging YAML from {U $source} into {U $target}..."

# An empty document yields no JSON at all: treat it as null, like jq would.
target_json=$(yq -o=json . "$target")
source_json=$(yq -o=json . "$source")

jq -n --argjson a "${target_json:-null}" --argjson b "${source_json:-null}" '
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
' | yq -p=json -o=yaml -P -I "$indent" . >/tmp/$$.merge && mv /tmp/$$.merge "$target" && zz_log s "YAML merged successfully"
