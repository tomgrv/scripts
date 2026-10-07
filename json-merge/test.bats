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

@test "json-merge is installed on PATH and syntactically valid" {
    command -v json-merge
    run sh -n "$BATS_TEST_DIRNAME/run.sh"
    [ "$status" -eq 0 ]
}

@test "json-merge -h prints usage and exits non-zero" {
    run json-merge -h
    [ "$status" -ne 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "json-merge errors with no arguments" {
    run json-merge
    [ "$status" -ne 0 ]
}

@test "json-merge errors with only a target argument" {
    echo '{"a":1}' >target.json
    run json-merge target.json
    [ "$status" -ne 0 ]
}

@test "json-merge errors when target file does not exist" {
    echo '{"a":1}' >source.json
    run json-merge does-not-exist.json source.json
    [ "$status" -ne 0 ]
    [[ "$output" == *"not found"* ]]
}

@test "json-merge errors when target file is not valid JSON" {
    echo 'not json' >target.json
    echo '{"a":1}' >source.json
    run json-merge target.json source.json
    [ "$status" -ne 0 ]
    [[ "$output" == *"not a valid JSON"* ]]
}

@test "json-merge merges a source object into the target file in place" {
    echo '{"a":1}' >target.json
    echo '{"b":2}' >source.json
    run json-merge target.json source.json
    [ "$status" -eq 0 ]
    run cat target.json
    [[ "$output" == *'"a"'* ]]
    [[ "$output" == *'"b"'* ]]
}

@test "json-merge merges from stdin when source is -" {
    echo '{"a":1}' >target.json
    run bash -c "echo '{\"b\":2}' | json-merge target.json -"
    [ "$status" -eq 0 ]
    run cat target.json
    [[ "$output" == *'"a"'* ]]
    [[ "$output" == *'"b"'* ]]
}

@test "json-merge unions and dedupes array values" {
    echo '{"list":[1,2,3]}' >target.json
    echo '{"list":[2,3,4]}' >source.json
    run json-merge target.json source.json
    [ "$status" -eq 0 ]
    result=$(cat target.json)
    [[ "$result" == *"1"* && "$result" == *"2"* && "$result" == *"3"* && "$result" == *"4"* ]]
    # deduped: value 2 should appear only once as an array element
    count=$(echo "$result" | grep -c '^\s*2,\?$')
    [ "$count" -eq 1 ]
}

@test "json-merge recursively merges nested objects" {
    echo '{"nested":{"a":1}}' >target.json
    echo '{"nested":{"b":2}}' >source.json
    run json-merge target.json source.json
    [ "$status" -eq 0 ]
    result=$(cat target.json)
    [[ "$result" == *'"a"'* ]]
    [[ "$result" == *'"b"'* ]]
}

@test "json-merge -t sets indentation size" {
    echo '{"a":1}' >target.json
    echo '{"b":2}' >source.json
    run json-merge -t 2 target.json source.json
    [ "$status" -eq 0 ]
    # indent of 2 spaces before a key
    grep -qE '^  "' target.json
}
