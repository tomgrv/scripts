#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
}

teardown() {
    teardown_scripts_path
}

@test "json is installed on PATH and syntactically valid" {
    command -v json
    run sh -n "$BATS_TEST_DIRNAME/run.sh"
    [ "$status" -eq 0 ]
}

@test "fails with no subcommand" {
    run json
    [ "$status" -eq 1 ]
    [[ "$output" == *"No subcommand provided"* ]]
}

@test "reports no dispatch target for an unknown subcommand" {
    run json bogus-subcommand-xyz
    [[ "$output" == *"No dispatch target found"* ]]
}

@test "dispatches to json-merge and forwards its arguments" {
    printf '{"a":1}\n' >"$BATS_TEST_TMPDIR/t.json"
    printf '{"b":2}\n' >"$BATS_TEST_TMPDIR/s.json"
    run json merge "$BATS_TEST_TMPDIR/t.json" "$BATS_TEST_TMPDIR/s.json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Dispatching to executable target"* ]]
    [ "$(jq -c . "$BATS_TEST_TMPDIR/t.json")" = '{"a":1,"b":2}' ]
}

@test "dispatches to json-validate" {
    run json validate -h
    [[ "$output" == *"Dispatching to executable target"* ]]
}
