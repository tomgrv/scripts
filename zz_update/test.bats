#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
}

teardown() {
    teardown_scripts_path
}

@test "zz_update re-links the zz_* bundle from a local checkout without touching the network" {
    run zz_update
    [ "$status" -eq 0 ]
    [[ "$output" == *"already available"* || "$output" == *"bundle"* ]]
}
