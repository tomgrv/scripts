#!/bin/sh
set -e

. zz-colors

eval $(
    zz-args "Load json from specified source" $0 "$@" <<help
        s -           schema        JSON is a schema
        - source      source        JSON file to load
help
)

# Resolve content to a variable first (rather than piping zz-load straight
# into sed|jq): jq exits 0 on empty stdin, so a failing zz-load would
# otherwise be swallowed by the pipeline's exit status being jq's.
content=$(zz-load -r "$source")

printf '%s\n' "$content" | sed -e 's:^[[:blank:]]*//.*$::g' 2>/dev/null | jq --arg source "$source" --arg schema "${schema:+true}" 'if . == null then {} else . end | if  (type != "object" or ($source != "" and has("$id")) or $schema == "") then . else . + {"$id": $source} end'
