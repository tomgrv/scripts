#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
}

teardown() {
    teardown_scripts_path
}

@test "zz_ask returns the default option on empty input" {
    run bash -c 'echo "" | zz_ask "Yn" "Continue?"'
    [ "$status" -eq 0 ]
}

@test "zz_ask accepts a valid option" {
    run bash -c 'echo "n" | zz_ask "Yn" "Continue?"'
    [ "$status" -ne 0 ]
}
