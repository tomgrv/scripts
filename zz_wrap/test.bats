#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
    WORK_DIR=$(mktemp -d)
    cd "$WORK_DIR" || exit 1
}

teardown() {
    cd /
    rm -rf "$WORK_DIR"
    teardown_scripts_path
}

@test "zz_wrap prompts, persists, and prints an export line when var is missing" {
    run bash -c 'echo "myvalue" | zz_wrap -v MY_VAR -q "value?" -d fallback'
    [ "$status" -eq 0 ]
    [[ "$output" == *"export MY_VAR='myvalue'"* ]]
    grep -q '^MY_VAR=myvalue$' .env
}

@test "zz_wrap does not prompt or persist when var is already set" {
    run env MY_VAR=already-there bash -c 'zz_wrap -v MY_VAR'
    [ "$status" -eq 0 ]
    [[ "$output" == *"export MY_VAR='already-there'"* ]]
    [ ! -f .env ]
}

@test "zz_wrap runs the wrapped command with the var exported" {
    run bash -c 'echo "cmdvalue" | zz_wrap -v MY_VAR -q "value?" sh -c "echo got=\$MY_VAR"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"got=cmdvalue"* ]]
}

@test "zz_wrap rejects an invalid variable name" {
    run bash -c 'zz_wrap -v "not a var"'
    [ "$status" -ne 0 ]
}
