#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
}

teardown() {
    teardown_scripts_path
}

@test "zz_dispatch is on PATH and syntactically valid" {
    run bash -n "$(command -v zz_dispatch)"
    [ "$status" -eq 0 ]
}

@test "zz_dispatch requires a subcommand" {
    run zz_dispatch "_foo.sh"
    [ "$status" -ne 0 ]
}

@test "zz_dispatch executes the matching sibling executable script" {
    dir=$(mktemp -d)
    printf '#!/bin/sh\necho ran-ok\n' >"$dir/foo-bar"
    chmod +x "$dir/foo-bar"
    run zz_dispatch "$dir/_foo.sh" bar
    [ "$status" -eq 0 ]
    [[ "$output" == *"ran-ok"* ]]
    rm -rf "$dir"
}

@test "zz_dispatch passes through remaining arguments to the target script" {
    dir=$(mktemp -d)
    printf '#!/bin/sh\necho "args:$*"\n' >"$dir/foo-bar"
    chmod +x "$dir/foo-bar"
    run zz_dispatch "$dir/_foo.sh" bar one two
    [ "$status" -eq 0 ]
    [[ "$output" == *"args:one two"* ]]
    rm -rf "$dir"
}

@test "zz_dispatch falls back to running a non-executable target through sh" {
    dir=$(mktemp -d)
    printf 'echo ran-via-sh\n' >"$dir/foo-bar"
    run zz_dispatch "$dir/_foo.sh" bar
    [ "$status" -eq 0 ]
    [[ "$output" == *"ran-via-sh"* ]]
    rm -rf "$dir"
}

@test "zz_dispatch reports no target found and lists available utilities" {
    dir=$(mktemp -d)
    printf '#!/bin/sh\necho other\n' >"$dir/foo-other"
    chmod +x "$dir/foo-other"
    run zz_dispatch "$dir/_foo.sh" nonexistent
    [[ "$output" == *"No dispatch target found"* ]]
    rm -rf "$dir"
}

@test "zz_dispatch derives the subcommand family name from the caller basename, stripping leading underscore and extension" {
    dir=$(mktemp -d)
    printf '#!/bin/sh\necho matched\n' >"$dir/thing-sub"
    chmod +x "$dir/thing-sub"
    run zz_dispatch "$dir/_thing.sh" sub
    [ "$status" -eq 0 ]
    [[ "$output" == *"matched"* ]]
    rm -rf "$dir"
}
