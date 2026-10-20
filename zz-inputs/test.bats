#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
    WORK=$(mktemp -d)
    mkdir "$WORK/a"
    echo '{"name":"a","config":{"inputs":{"A_TOKEN":{"description":"tok","required":true,"secret":true},"A_OPT":{"default":"dflt"}}}}' >"$WORK/a/package.json"
    cd "$WORK"
}

teardown() {
    cd /
    rm -rf "$WORK"
    teardown_scripts_path
}

@test "zz-inputs -S shows each input as set, required or optional" {
    run env A_OPT=x zz-inputs -S -f "$WORK/env" a=a
    [ "$status" -eq 0 ]
    [[ "$output" == *"A_TOKEN"*"[required]"* ]]
    [[ "$output" == *"A_OPT"*"[set]"* ]]
}

@test "zz-inputs -S reads the env file for what the environment lacks" {
    echo 'A_TOKEN=s3' >"$WORK/env"
    run zz-inputs -S -f "$WORK/env" a=a
    [[ "$output" == *"A_TOKEN"*"[set]"* ]]
}

@test "zz-inputs fails on a required input that is still empty" {
    run zz-inputs -f "$WORK/env" a=a </dev/null
    [ "$status" -eq 1 ]
    [[ "$output" == *"A_TOKEN is required by 'a'"* ]]
}

@test "zz-inputs prints export lines for the resolved inputs" {
    run env A_TOKEN=t zz-inputs -f "$WORK/env" a=a </dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *"A_OPT"* && "$output" == *"dflt"* ]]
}

@test "zz-inputs without an env file prints usage" {
    run zz-inputs a=a
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage"* ]]
}
