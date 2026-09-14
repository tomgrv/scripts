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

@test "run-workspace-tests is installed on PATH and syntactically valid" {
    command -v run-workspace-tests
    run sh -n "$BATS_TEST_DIRNAME/run.sh"
    [ "$status" -eq 0 ]
}

@test "run-workspace-tests -h prints usage and exits non-zero" {
    run run-workspace-tests -h
    [ "$status" -ne 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "run-workspace-tests errors with no arguments" {
    run run-workspace-tests
    [ "$status" -ne 0 ]
}

@test "run-workspace-tests errors when the workspace directory does not exist" {
    run run-workspace-tests ./missing-workspace
    [ "$status" -ne 0 ]
}

@test "run-workspace-tests silently skips a workspace with no root json file" {
    mkdir ws
    run run-workspace-tests ws
    [ "$status" -eq 0 ]
    [[ "$output" != *"No "* ]]
    [[ "$output" != *"Running"* ]]
}

@test "run-workspace-tests warns and succeeds when scripts.test is absent" {
    mkdir ws
    echo '{"name":"ws"}' >ws/package.json
    run run-workspace-tests ws
    [ "$status" -eq 0 ]
    [[ "$output" == *"No"* ]]
}

@test "run-workspace-tests propagates a non-zero exit from the test script" {
    mkdir ws
    echo '{"scripts":{"test":"echo boom && exit 3"}}' >ws/package.json
    run run-workspace-tests ws
    [ "$status" -ne 0 ]
    [[ "$output" == *"boom"* ]]
}

@test "run-workspace-tests errors when the test script produces no output" {
    mkdir ws
    echo '{"scripts":{"test":"true"}}' >ws/package.json
    run run-workspace-tests ws
    [ "$status" -ne 0 ]
    [[ "$output" == *"no output"* ]]
}

@test "run-workspace-tests passes on the happy path" {
    mkdir ws
    echo '{"scripts":{"test":"echo all good"}}' >ws/package.json
    run run-workspace-tests ws
    [ "$status" -eq 0 ]
    [[ "$output" == *"all good"* ]]
}

@test "run-workspace-tests runs the script from within the workspace directory" {
    mkdir ws
    echo 'marker' >ws/marker.txt
    echo '{"scripts":{"test":"cat marker.txt"}}' >ws/package.json
    run run-workspace-tests ws
    [ "$status" -eq 0 ]
    [[ "$output" == *"marker"* ]]
}
