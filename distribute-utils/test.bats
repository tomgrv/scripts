#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
}

teardown() {
    teardown_scripts_path
}

@test "distribute-utils errors without a target directory" {
    run distribute-utils
    [ "$status" -ne 0 ]
}

@test "distribute-utils exits quietly with -q and no target" {
    run distribute-utils -q
    [ "$status" -eq 0 ]
}
