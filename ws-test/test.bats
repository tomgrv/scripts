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

@test "ws-test is installed on PATH and syntactically valid" {
    command -v ws-test
    run sh -n "$BATS_TEST_DIRNAME/run.sh"
    [ "$status" -eq 0 ]
}

@test "ws-test -h prints usage and exits non-zero" {
    run ws-test -h
    [ "$status" -ne 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "ws-test errors with no arguments" {
    run ws-test
    [ "$status" -ne 0 ]
}

@test "ws-test errors when the workspace directory does not exist" {
    run ws-test ./missing-workspace
    [ "$status" -ne 0 ]
}

@test "ws-test silently skips a workspace with no root json file" {
    mkdir ws
    run ws-test ws
    [ "$status" -eq 0 ]
    [[ "$output" != *"No "* ]]
    [[ "$output" != *"Running"* ]]
}

@test "ws-test warns and succeeds when scripts.test is absent" {
    mkdir ws
    echo '{"name":"ws"}' >ws/package.json
    run ws-test ws
    [ "$status" -eq 0 ]
    [[ "$output" == *"No"* ]]
}

@test "ws-test propagates a non-zero exit from the test script" {
    mkdir ws
    echo '{"scripts":{"test":"echo boom && exit 3"}}' >ws/package.json
    run ws-test ws
    [ "$status" -ne 0 ]
    [[ "$output" == *"boom"* ]]
}

@test "ws-test errors when the test script produces no output" {
    mkdir ws
    echo '{"scripts":{"test":"true"}}' >ws/package.json
    run ws-test ws
    [ "$status" -ne 0 ]
    [[ "$output" == *"no output"* ]]
}

@test "ws-test passes on the happy path" {
    mkdir ws
    echo '{"scripts":{"test":"echo all good"}}' >ws/package.json
    run ws-test ws
    [ "$status" -eq 0 ]
    [[ "$output" == *"all good"* ]]
}

@test "ws-test runs the script from within the workspace directory" {
    mkdir ws
    echo 'marker' >ws/marker.txt
    echo '{"scripts":{"test":"cat marker.txt"}}' >ws/package.json
    run ws-test ws
    [ "$status" -eq 0 ]
    [[ "$output" == *"marker"* ]]
}
