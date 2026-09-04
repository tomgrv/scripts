#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
    WORK_DIR=$(mktemp -d)
    cd "$WORK_DIR" || exit 1
}

teardown() {
    cd /
    rm -rf "$WORK_DIR"
    teardown_scripts_path
}

@test "merge-json is installed on PATH and syntactically valid" {
    command -v merge-json
    run sh -n "$BATS_TEST_DIRNAME/run.sh"
    [ "$status" -eq 0 ]
}

@test "merge-json -h prints usage and exits non-zero" {
    run merge-json -h
    [ "$status" -ne 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "merge-json errors with no arguments" {
    run merge-json
    [ "$status" -ne 0 ]
}

@test "merge-json errors with only a target argument" {
    echo '{"a":1}' >target.json
    run merge-json target.json
    [ "$status" -ne 0 ]
}

@test "merge-json errors when target file does not exist" {
    echo '{"a":1}' >source.json
    run merge-json does-not-exist.json source.json
    [ "$status" -ne 0 ]
    [[ "$output" == *"not found"* ]]
}

@test "merge-json errors when target file is not valid JSON" {
    echo 'not json' >target.json
    echo '{"a":1}' >source.json
    run merge-json target.json source.json
    [ "$status" -ne 0 ]
    [[ "$output" == *"not a valid JSON"* ]]
}

@test "merge-json merges a source object into the target file in place" {
    echo '{"a":1}' >target.json
    echo '{"b":2}' >source.json
    run merge-json target.json source.json
    [ "$status" -eq 0 ]
    run cat target.json
    [[ "$output" == *'"a"'* ]]
    [[ "$output" == *'"b"'* ]]
}

@test "merge-json merges from stdin when source is -" {
    echo '{"a":1}' >target.json
    run bash -c "echo '{\"b\":2}' | merge-json target.json -"
    [ "$status" -eq 0 ]
    run cat target.json
    [[ "$output" == *'"a"'* ]]
    [[ "$output" == *'"b"'* ]]
}

@test "merge-json unions and dedupes array values" {
    echo '{"list":[1,2,3]}' >target.json
    echo '{"list":[2,3,4]}' >source.json
    run merge-json target.json source.json
    [ "$status" -eq 0 ]
    result=$(cat target.json)
    [[ "$result" == *"1"* && "$result" == *"2"* && "$result" == *"3"* && "$result" == *"4"* ]]
    # deduped: value 2 should appear only once as an array element
    count=$(echo "$result" | grep -c '^\s*2,\?$')
    [ "$count" -eq 1 ]
}

@test "merge-json recursively merges nested objects" {
    echo '{"nested":{"a":1}}' >target.json
    echo '{"nested":{"b":2}}' >source.json
    run merge-json target.json source.json
    [ "$status" -eq 0 ]
    result=$(cat target.json)
    [[ "$result" == *'"a"'* ]]
    [[ "$result" == *'"b"'* ]]
}

@test "merge-json -t sets indentation size" {
    echo '{"a":1}' >target.json
    echo '{"b":2}' >source.json
    run merge-json -t 2 target.json source.json
    [ "$status" -eq 0 ]
    # indent of 2 spaces before a key
    grep -qE '^  "' target.json
}
