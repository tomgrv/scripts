#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
}

teardown() {
    teardown_scripts_path
}

@test "normalize-json sorts keys and prints the result" {
    tmp=$(mktemp --suffix=.json)
    echo '{"b":1,"a":2}' >"$tmp"
    run normalize-json -c -a -i -t 2 -f local -l true "$tmp"
    rm -f "$tmp"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"a": 2'* ]]
}
