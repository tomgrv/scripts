#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
}

teardown() {
    teardown_scripts_path
}

@test "zz-prompt is on PATH and syntactically valid" {
    run bash -n "$(command -v zz-prompt)"
    [ "$status" -eq 0 ]
}

@test "zz-prompt returns the default when input is empty" {
    run bash -c 'echo "" | zz-prompt "Question?" "fallback" 2>/dev/null'
    [ "$status" -eq 0 ]
    [ "$output" = "fallback" ]
}

@test "zz-prompt returns the entered value" {
    run bash -c 'echo "typed" | zz-prompt "Question?" "fallback" 2>/dev/null'
    [ "$status" -eq 0 ]
    [ "$output" = "typed" ]
}

@test "zz-prompt with no default and empty input returns empty output" {
    run bash -c 'echo "" | zz-prompt "Question?" 2>/dev/null'
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "zz-prompt writes only the question (with default) to stderr, not stdout" {
    run bash -c 'echo "" | zz-prompt "Question?" "fallback" 2>&1 1>/dev/null'
    [[ "$output" == *"Question?"* ]]
    [[ "$output" == *"[fallback]"* ]]
}

@test "zz-prompt with no default omits the bracketed default from the prompt text" {
    run bash -c 'echo "x" | zz-prompt "Question?" 2>&1 1>/dev/null'
    [[ "$output" == *"Question?"* ]]
    [[ "$output" != *"["*"]"* ]]
}

@test "zz-prompt stdout carries only the entered/default value, cleanly separated from the prompt" {
    run bash -c 'echo "typed" | zz-prompt "Question?" "fallback" 2>/dev/null'
    [ "$(echo "$output" | wc -l)" -eq 1 ]
}
