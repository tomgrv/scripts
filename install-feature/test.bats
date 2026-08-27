#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
}

teardown() {
    teardown_scripts_path
}

@test "install-feature errors without a caller argument" {
    run install-feature
    [ "$status" -ne 0 ]
}
