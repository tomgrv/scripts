#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
    WORK_DIR=$(mktemp -d)
    cd "$WORK_DIR" || exit 1
    printf '{"user": "${user}", "items": ${items}, "keep": "${other}"}\n' >body.json
}

teardown() {
    cd /
    rm -rf "$WORK_DIR"
    teardown_scripts_path
}

@test "json-render is installed on PATH and syntactically valid" {
    command -v json-render
    run sh -n "$BATS_TEST_DIRNAME/run.sh"
    [ "$status" -eq 0 ]
}

@test "json-render -h prints usage and exits non-zero" {
    run json-render -h
    [ "$status" -ne 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "json-render errors with no arguments" {
    run json-render
    [ "$status" -ne 0 ]
}

@test "json-render errors when the file does not exist" {
    run json-render missing.json user=a
    [ "$status" -ne 0 ]
}

@test "json-render fills NAME=value and NAME:=json, leaving other placeholders alone" {
    run json-render body.json user=ada 'items:=["a","b"]'
    [ "$status" -eq 0 ]
    [ "$output" = '{"user": "ada", "items": ["a","b"], "keep": "${other}"}' ]
}

@test "json-render takes a bare NAME from the environment" {
    user=env run json-render body.json user items:=1
    [ "$status" -eq 0 ]
    [[ "$output" == *'"user": "env"'* ]]
}

@test "json-render escapes quotes, backslashes and newlines in a string value" {
    user='say "hi" \ a&b|c' run json-render body.json user items:=1
    [ "$status" -eq 0 ]
    printf '%s' "$output" | jq -e --arg u 'say "hi" \ a&b|c' '.user == $u' 
}

@test "json-render escapes a newline coming from the environment" {
    user="a
b" run json-render body.json user items:=1
    [ "$status" -eq 0 ]
    printf '%s' "$output" | jq -e '.user == "a\nb"'
}

@test "json-render refuses invalid JSON for NAME:=json" {
    run json-render body.json user=a 'items:={nope'
    [ "$status" -ne 0 ]
}

@test "json-render refuses an invalid placeholder name" {
    run json-render body.json 'us er=a'
    [ "$status" -ne 0 ]
}
