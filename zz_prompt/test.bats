#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
}

teardown() {
    teardown_scripts_path
}

@test "zz_prompt returns the default when input is empty" {
    run bash -c 'echo "" | zz_prompt "Question?" "fallback"'
    [ "$status" -eq 0 ]
    [ "$output" = "fallback" ]
}

@test "zz_prompt returns the entered value" {
    run bash -c 'echo "typed" | zz_prompt "Question?" "fallback"'
    [ "$status" -eq 0 ]
    [ "$output" = "typed" ]
}
