#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
}

teardown() {
    teardown_scripts_path
}

@test "kube is installed on PATH and syntactically valid" {
    command -v kube
    run sh -n "$BATS_TEST_DIRNAME/run.sh"
    [ "$status" -eq 0 ]
}

@test "fails with no subcommand" {
    run kube
    [ "$status" -eq 1 ]
    [[ "$output" == *"No subcommand provided"* ]]
}

@test "reports no dispatch target for an unknown subcommand" {
    run kube bogus-subcommand-xyz
    [[ "$output" == *"No dispatch target found"* ]]
}

@test "dispatches to kube-apply and forwards its arguments" {
    run kube apply
    [ "$status" -eq 1 ]
    [[ "$output" == *"Dispatching to executable target"* ]]
    [[ "$output" == *"Usage: kube-apply"* ]]
}
