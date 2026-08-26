#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
}

teardown() {
    teardown_scripts_path
}

@test "zz_npx requires a tool argument" {
    run zz_npx
    [ "$status" -ne 0 ]
}
