#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
}

teardown() {
    teardown_scripts_path
}

@test "zz_colors exports color variables when sourced" {
    run bash -c '. zz_colors; printf "%s" "$Red$None$End"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"["* ]]
}
