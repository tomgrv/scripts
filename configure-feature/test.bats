#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
}

teardown() {
    teardown_scripts_path
}

@test "configure-feature errors without a feature argument" {
    run configure-feature
    [ "$status" -ne 0 ]
}
