#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
    WORK_DIR=$(mktemp -d)
    cd "$WORK_DIR" || exit 1
    printf 'host: "${host}"\nport: ${port}\nkeep: ${other}\n' >values.yaml
}

teardown() {
    cd /
    rm -rf "$WORK_DIR"
    teardown_scripts_path
}

@test "helm-render is installed on PATH and syntactically valid" {
    command -v helm-render
    run sh -n "$BATS_TEST_DIRNAME/run.sh"
    [ "$status" -eq 0 ]
}

@test "helm-render -h prints usage and exits non-zero" {
    run helm-render -h
    [ "$status" -ne 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "helm-render errors with no arguments" {
    run helm-render
    [ "$status" -ne 0 ]
}

@test "helm-render errors when the file does not exist" {
    run helm-render missing.yaml host=a
    [ "$status" -ne 0 ]
}

@test "helm-render fills NAME=value pairs and leaves other placeholders alone" {
    run helm-render values.yaml host=app.example.com port=8080
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = 'host: "app.example.com"' ]
    [ "${lines[1]}" = 'port: 8080' ]
    [ "${lines[2]}" = 'keep: ${other}' ]
}

@test "helm-render takes a bare NAME from the environment" {
    host=env.example.com port=9 run helm-render values.yaml host port
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = 'host: "env.example.com"' ]
    [ "${lines[1]}" = 'port: 9' ]
}

@test "helm-render keeps / & | and backslash in a value literal" {
    run helm-render values.yaml 'host=a/b&c|d\e' port=1
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = 'host: "a/b&c|d\e"' ]
}

@test "helm-render refuses an invalid placeholder name" {
    run helm-render values.yaml 'ho st=a'
    [ "$status" -ne 0 ]
}

@test "helm-render refuses a multi-line value from the environment" {
    host="a
b" run helm-render values.yaml host
    [ "$status" -ne 0 ]
}
