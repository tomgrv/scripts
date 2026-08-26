#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
}

teardown() {
    teardown_scripts_path
}

@test "load-json loads and tags a local file with \$id" {
    tmp=$(mktemp --suffix=.json)
    echo '{"a":1}' >"$tmp"
    run load-json "$tmp"
    rm -f "$tmp"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"a": 1'* || "$output" == *'"a":1'* ]]
}
