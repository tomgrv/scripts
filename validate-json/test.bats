#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
}

teardown() {
    teardown_scripts_path
}

@test "validate-json accepts an object against the default fallback schema" {
    tmp=$(mktemp --suffix=.json)
    echo '{"name":"x"}' >"$tmp"
    run validate-json -a -f local -l true "$tmp"
    rm -f "$tmp"
    [ "$status" -eq 0 ]
}
