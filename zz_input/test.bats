#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
}

teardown() {
    teardown_scripts_path
}

@test "zz_input reads a literal argument" {
    run zz_input "hello"
    [ "$status" -eq 0 ]
    [ "$output" = "hello" ]
}

@test "zz_input reads a file argument" {
    tmp=$(mktemp)
    echo "from-file" >"$tmp"
    run zz_input "$tmp"
    rm -f "$tmp"
    [ "$status" -eq 0 ]
    [[ "$output" == *"from-file"* ]]
}

@test "zz_input reads stdin when no argument given" {
    run bash -c 'echo "from-stdin" | zz_input'
    [ "$status" -eq 0 ]
    [ "$output" = "from-stdin" ]
}
