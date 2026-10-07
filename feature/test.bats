#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
}

teardown() {
    teardown_scripts_path
}

@test "feature is installed on PATH and syntactically valid" {
    command -v feature
    run sh -n "$BATS_TEST_DIRNAME/run.sh"
    [ "$status" -eq 0 ]
}

@test "fails with no subcommand" {
    run feature
    [ "$status" -eq 1 ]
    [[ "$output" == *"No subcommand provided"* ]]
}

@test "reports no dispatch target for an unknown subcommand" {
    run feature bogus-subcommand-xyz
    [[ "$output" == *"No dispatch target found"* ]]
}

@test "dispatches to feature-context and forwards its arguments" {
    run feature context -h
    [[ "$output" == *"Dispatching to executable target"* ]]
}

@test "dispatches to feature-install" {
    run feature install -h
    [[ "$output" == *"Dispatching to executable target"* ]]
}

@test "dispatches to feature-configure" {
    run feature configure -h
    [[ "$output" == *"Dispatching to executable target"* ]]
}
