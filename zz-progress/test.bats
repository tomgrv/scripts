#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
}

teardown() {
    teardown_scripts_path
}

@test "zz-progress is installed on PATH and syntactically valid" {
    command -v zz-progress
    run sh -n "$BATS_TEST_DIRNAME/run.sh"
    [ "$status" -eq 0 ]
}

@test "zz-progress shows the message on a terminal and clears the line with no argument" {
    command -v script >/dev/null || skip "script(1) not installed"
    run bash -c 'script -qec "zz-progress Working..." /dev/null | od -An -c | tr -d " \n"'
    [[ "$output" == *'\r033[K'*'W'*'o'*'r'*'k'*'i'*'n'*'g'* ]]
    run bash -c 'script -qec "zz-progress" /dev/null | od -An -c | tr -d " \n"'
    [[ "$output" == *'\r033[K' ]]
}

@test "zz-progress writes nothing when stderr is not a terminal" {
    run bash -c 'zz-progress Working... 2>&1; zz-progress 2>&1'
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}
