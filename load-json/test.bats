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

@test "load-json is installed on PATH and syntactically valid" {
    command -v load-json
    run sh -n "$BATS_TEST_DIRNAME/run.sh"
    [ "$status" -eq 0 ]
}

@test "load-json -h prints usage and exits non-zero" {
    run load-json -h
    [ "$status" -ne 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "load-json errors with no source provided" {
    run load-json
    [ "$status" -ne 0 ]
}

@test "load-json loads a local file and prints its content" {
    echo '{"a":1}' >x.json
    run load-json x.json
    [ "$status" -eq 0 ]
    [[ "$output" == *'"a": 1'* || "$output" == *'"a":1'* ]]
    # -s (schema mode) not passed: no $id tagging
    [[ "$output" != *'"$id"'* ]]
}

@test "load-json -s tags a schema file with \$id when not already present" {
    echo '{"type":"object"}' >x.json
    run load-json -s x.json
    [ "$status" -eq 0 ]
    [[ "$output" == *'"$id"'* ]]
    [[ "$output" == *"x.json"* ]]
}

@test "load-json -s does not overwrite an existing \$id" {
    echo '{"a":1,"$id":"keep-me"}' >x.json
    run load-json -s x.json
    [ "$status" -eq 0 ]
    [[ "$output" == *"keep-me"* ]]
}

@test "load-json -s marks the loaded JSON as a schema (still tags \$id)" {
    echo '{"type":"object"}' >x.json
    run load-json -s x.json
    [ "$status" -eq 0 ]
    [[ "$output" == *'"$id"'* ]]
}

@test "load-json errors when the local file does not exist" {
    run load-json does-not-exist.json
    [ "$status" -ne 0 ]
    [[ "$output" == *"not found"* ]]
}

@test "load-json strips // line comments before parsing" {
    cat >x.json <<'EOF'
{
    // a comment
    "a": 1
}
EOF
    run load-json x.json
    [ "$status" -eq 0 ]
    [[ "$output" == *'"a": 1'* || "$output" == *'"a":1'* ]]
}

@test "load-json returns an empty object for a null file, tagged in schema mode" {
    printf 'null' >x.json
    run load-json -s x.json
    [ "$status" -eq 0 ]
    [[ "$output" == *'"$id"'* ]]
}
