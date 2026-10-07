#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
}

teardown() {
    teardown_scripts_path
}

@test "yaml is installed on PATH and syntactically valid" {
    command -v yaml
    run sh -n "$BATS_TEST_DIRNAME/run.sh"
    [ "$status" -eq 0 ]
}

@test "fails with no subcommand" {
    run yaml
    [ "$status" -eq 1 ]
    [[ "$output" == *"No subcommand provided"* ]]
}

@test "reports no dispatch target for an unknown subcommand" {
    run yaml bogus-subcommand-xyz
    [[ "$output" == *"No dispatch target found"* ]]
}

@test "dispatches to yaml-merge and forwards its arguments" {
    run yaml merge -h
    [[ "$output" == *"Dispatching to executable target"* ]]
}
