#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
}

teardown() {
    teardown_scripts_path
}

@test "edit-script fails when the script isn't installed in /usr/local/bin" {
    run edit-script definitely-not-installed-xyz
    [ "$status" -ne 0 ]
}
