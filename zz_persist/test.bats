#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
}

teardown() {
    teardown_scripts_path
}

@test "zz_persist upserts KEY=VALUE into an env file" {
    tmp=$(mktemp)
    run zz_persist -f "$tmp" FOO bar
    [ "$status" -eq 0 ]
    grep -q '^FOO=bar$' "$tmp"
    run zz_persist -f "$tmp" FOO baz
    grep -q '^FOO=baz$' "$tmp"
    rm -f "$tmp"
}
