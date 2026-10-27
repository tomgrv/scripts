#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
}

teardown() {
    teardown_scripts_path
}

@test "zz-interactive is installed on PATH and syntactically valid" {
    command -v zz-interactive
    run sh -n "$BATS_TEST_DIRNAME/run.sh"
    [ "$status" -eq 0 ]
}

@test "not interactive without a terminal" {
    run zz-interactive </dev/null
    [ "$status" -eq 1 ]
}

@test "interactive on a terminal, unless ZZ_INTERACTIVE=0 or SYSTEM_ACCESS_MENU=false" {
    run script -qec "zz-interactive" /dev/null
    [ "$status" -eq 0 ]
    run script -qec "env ZZ_INTERACTIVE=0 zz-interactive" /dev/null
    [ "$status" -ne 0 ]
    run script -qec "env SYSTEM_ACCESS_MENU=false zz-interactive" /dev/null
    [ "$status" -ne 0 ]
}
