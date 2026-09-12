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

@test "merge-yaml is installed on PATH and syntactically valid" {
    command -v merge-yaml
    run sh -n "$BATS_TEST_DIRNAME/run.sh"
    [ "$status" -eq 0 ]
}

@test "merge-yaml -h prints usage and exits non-zero" {
    run merge-yaml -h
    [ "$status" -ne 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "merge-yaml errors with no arguments" {
    run merge-yaml
    [ "$status" -ne 0 ]
}

@test "merge-yaml errors with only a target argument" {
    printf 'a: 1\n' >target.yaml
    run merge-yaml target.yaml
    [ "$status" -ne 0 ]
}

@test "merge-yaml errors when target file does not exist" {
    printf 'a: 1\n' >source.yaml
    run merge-yaml does-not-exist.yaml source.yaml
    [ "$status" -ne 0 ]
    [[ "$output" == *"not found"* ]]
}

@test "merge-yaml errors when target file is not valid YAML" {
    printf ':\n  - broken: [\n' >target.yaml
    printf 'a: 1\n' >source.yaml
    run merge-yaml target.yaml source.yaml
    [ "$status" -ne 0 ]
    [[ "$output" == *"not a valid YAML"* ]]
}

@test "merge-yaml merges a source object into the target file in place" {
    printf 'a: 1\n' >target.yaml
    printf 'b: 2\n' >source.yaml
    run merge-yaml target.yaml source.yaml
    [ "$status" -eq 0 ]
    run cat target.yaml
    [[ "$output" == *"a: 1"* ]]
    [[ "$output" == *"b: 2"* ]]
}

@test "merge-yaml merges from stdin when source is -" {
    printf 'a: 1\n' >target.yaml
    run bash -c "printf 'b: 2\n' | merge-yaml target.yaml -"
    [ "$status" -eq 0 ]
    run cat target.yaml
    [[ "$output" == *"a: 1"* ]]
    [[ "$output" == *"b: 2"* ]]
}

@test "merge-yaml unions and dedupes array values" {
    printf 'list:\n  - 1\n  - 2\n  - 3\n' >target.yaml
    printf 'list:\n  - 2\n  - 3\n  - 4\n' >source.yaml
    run merge-yaml target.yaml source.yaml
    [ "$status" -eq 0 ]
    result=$(cat target.yaml)
    count=$(echo "$result" | grep -c '^\s*- 2\s*$')
    [ "$count" -eq 1 ]
    [[ "$result" == *"- 4"* ]]
}

@test "merge-yaml recursively merges nested objects" {
    printf 'nested:\n  a: 1\n' >target.yaml
    printf 'nested:\n  b: 2\n' >source.yaml
    run merge-yaml target.yaml source.yaml
    [ "$status" -eq 0 ]
    result=$(cat target.yaml)
    [[ "$result" == *"a: 1"* ]]
    [[ "$result" == *"b: 2"* ]]
}

@test "merge-yaml -i sets indentation size" {
    printf 'nested:\n  a: 1\n' >target.yaml
    printf 'nested:\n  b: 2\n' >source.yaml
    run merge-yaml -i 4 target.yaml source.yaml
    [ "$status" -eq 0 ]
    grep -qE '^    a: 1' target.yaml
}
