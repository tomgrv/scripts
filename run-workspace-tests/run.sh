#!/bin/sh
set -e

zz_use zz_colors zz_log zz_args jq
. zz_colors

eval $(
    zz_args "Run each root JSON file's .scripts.test entry as a workspace's test suite" $0 "$@" <<-help
        - workspace   workspace     Workspace directory to test
help
)

if [ -z "$workspace" ]; then
    zz_log e "No workspace provided" && exit 1
fi

if [ ! -d "$workspace" ]; then
    zz_log e "Workspace {U $workspace} not found" && exit 1
fi

failed=0
found_json=0

for json in "$workspace"/*.json; do
    [ -f "$json" ] || continue
    found_json=1

    test_cmd=$(jq -r '.scripts.test // empty' "$json" 2>/dev/null || true)

    if [ -z "$test_cmd" ]; then
        zz_log w "No {B scripts.test} entry in {U $json}"
        continue
    fi

    zz_log i "Running {B $test_cmd} in {U $workspace} ({U $json})"

    output=$(cd "$workspace" && sh -c "$test_cmd" 2>&1)
    status=$?

    printf '%s\n' "$output"

    if [ "$status" -ne 0 ]; then
        zz_log e "Test script in {U $json} exited with status $status"
        failed=1
        continue
    fi

    if [ -z "$output" ]; then
        zz_log e "Test script in {U $json} produced no output"
        failed=1
        continue
    fi

    zz_log s "Tests passed for {U $json}"
done

# Silent skip: no root *.json file in this workspace at all.
if [ "$found_json" -eq 0 ]; then
    exit 0
fi

exit $failed
