#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
}

teardown() {
    teardown_scripts_path
}

@test "resolve-context resolves source/feature/target from an explicit caller" {
    dir=$(mktemp -d)
    touch "$dir/install.sh"
    run resolve-context -- "$dir/install.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"source="* ]]
    [[ "$output" == *"feature="* ]]
    [[ "$output" == *"target="* ]]
    rm -rf "$dir"
}
