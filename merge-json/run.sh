#!/bin/sh
set -e

zz_use zz_colors zz_args jq
. zz_colors

eval $(
    zz_args "Merge 2 json files" $0 "$@" <<-help
        t tabSize     tabSize   tab size for indentation
        - target      target		Target JSON file to merge into
        - source      source		Source JSON file to merge from
help
)

if [ -z "$target" ] || [ -z "$source" ]; then
    zz_log e "Usage: merge-json <target> <source>"
    exit 1
fi

if [ ! -f "$target" ]; then
    zz_log e "Target file {U $target} not found"
    exit 1
elif ! jq empty "$target" >/dev/null 2>&1; then
    zz_log e "Target file {U $target} is not a valid JSON"
    exit 1
fi

if [ $source = "-" ]; then
    source=/dev/stdin
fi

zz_log i "Merging JSON from {U $source} into {U $target}..."

jq 'def dedupe_ordered:
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

merge(.; input)' $target $source | normalize-json -c -a -i -t ${tabSize:-4} -f local -l true 2>/dev/null > /tmp/$$.merge && mv /tmp/$$.merge $target && zz_log s "JSON merged successfully"
