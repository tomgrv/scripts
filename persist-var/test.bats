#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
}

teardown() {
    teardown_scripts_path
}

@test "persist-var upserts KEY=VALUE into an env file" {
    tmp=$(mktemp)
    run persist-var -f "$tmp" FOO bar
    [ "$status" -eq 0 ]
    grep -q '^FOO=bar$' "$tmp"
    run persist-var -f "$tmp" FOO baz
    grep -q '^FOO=baz$' "$tmp"
    rm -f "$tmp"
}
