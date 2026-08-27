#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
}

teardown() {
    teardown_scripts_path
}

@test "zz_log prints a leveled message to stderr" {
    run zz_log i "hello"
    [ "$status" -eq 0 ]
    [[ "$output" == *"hello"* ]]
}

@test "zz_log supports i/w/e/s/- levels without erroring" {
    for lvl in i w e s -; do
        run zz_log "$lvl" "msg"
        [ "$status" -eq 0 ]
    done
}
