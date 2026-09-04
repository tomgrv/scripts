#!/bin/sh
set -e

zz_use zz_colors zz_args jq curl
. zz_colors

eval $(
    zz_args "Load json from specified source" $0 "$@" <<-help
        s -           schema		JSON is a schema
        - source      source		JSON file to load
help
)

# Resolve content to a variable first (rather than piping the if/elif/else
# block's stdout straight into sed|jq): jq exits 0 on empty stdin, so an
# `exit 1` inside that block would otherwise be swallowed by the pipeline's
# exit status being jq's, not the failing branch's.
if test -n "$(echo $source | grep -E '^http')"; then
    zz_log i "Downloading file from {U $source}"
    content=$(curl -L -s $source)
    if [ $? -ne 0 ]; then
        zz_log e "Unable to download file {U $source}" && exit 1
    fi
elif test -f "$source"; then
    zz_log i "Loading file {U $source}"
    content=$(cat $source)
elif test -n "$source"; then
    zz_log e "File {U $source} not found" && exit 1
else
    zz_log e "No source provided" && exit 1
fi

echo "$content" | sed -e 's:^[[:blank:]]*//.*$::g' 2>/dev/null | jq --arg source "$source" --arg schema "${schema:+true}" 'if . == null then {} else . end | if  (type != "object" or ($source != "" and has("$id")) or $schema == "") then . else . + {"$id": $source} end'
