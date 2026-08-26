#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
}

teardown() {
    teardown_scripts_path
}

@test "run-npx requires a tool argument" {
    run run-npx
    [ "$status" -ne 0 ]
}
