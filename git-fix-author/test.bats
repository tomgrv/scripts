#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
}

teardown() {
    teardown_scripts_path
}

@test "git-fix-author is installed on PATH and syntactically valid" {
    command -v git-fix-author
    run sh -n "$BATS_TEST_DIRNAME/run.sh"
    [ "$status" -eq 0 ]
}
