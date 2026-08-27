#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
}

teardown() {
    teardown_scripts_path
}

@test "zz_ask prints the default option on empty input" {
    run bash -c 'echo "" | zz_ask "Yn" "Continue?" 2>/dev/null'
    [ "$status" -eq 0 ]
    [ "$output" = "y" ]
}

@test "zz_ask prints a valid non-default option" {
    run bash -c 'echo "n" | zz_ask "Yn" "Continue?" 2>/dev/null'
    [ "$status" -eq 0 ]
    [ "$output" = "n" ]
}

@test "zz_ask re-prompts on an invalid option before accepting a valid one" {
    run bash -c 'printf "x\nn\n" | zz_ask "Yn" "Continue?" 2>/dev/null'
    [ "$status" -eq 0 ]
    [ "$output" = "n" ]
}
