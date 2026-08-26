#!/usr/bin/env bats

load helpers.bash

setup() {
    setup_scripts_path
}

teardown() {
    teardown_scripts_path
}

@test "zz_log prints a leveled message to stderr" {
    run bash -c '. zz_wrap; zz_log i "hello"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"hello"* ]]
}

@test "zz_esc escapes single quotes" {
    run bash -c ". zz_wrap; zz_esc \"a'b\""
    [ "$status" -eq 0 ]
    [ "$output" = "a'\\''b" ]
}

@test "zz_args emits eval-able var assignments" {
    run bash -c '. zz_wrap; eval $(zz_args "t" "$0" -f value <<-help
f flag flag help text
help
); echo "$flag"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"value"* ]]
}

@test "zz_bindir resolves a writable directory and prints it" {
    run bash -c '. zz_wrap; INSTALL_BIN_DIR=$(mktemp -d) zz_bindir'
    [ "$status" -eq 0 ]
    [ -n "$output" ]
}
