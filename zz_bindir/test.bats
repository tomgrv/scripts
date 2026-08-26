#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
}

teardown() {
    teardown_scripts_path
}

@test "zz_bindir resolves a writable directory and prints it" {
    run env INSTALL_BIN_DIR="$(mktemp -d)" zz_bindir
    [ "$status" -eq 0 ]
    [[ "$output" == *"dir="* ]]
}
