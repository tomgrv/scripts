#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
}

teardown() {
    teardown_scripts_path
}

@test "zz-ask is on PATH and syntactically valid" {
    run bash -n "$(command -v zz-ask)"
    [ "$status" -eq 0 ]
}

@test "zz-ask prints the default option on empty input" {
    run bash -c 'echo "" | zz-ask "Yn" "Continue?" 2>/dev/null'
    [ "$status" -eq 0 ]
    [ "$output" = "y" ]
}

@test "zz-ask prints a valid non-default option" {
    run bash -c 'echo "n" | zz-ask "Yn" "Continue?" 2>/dev/null'
    [ "$status" -eq 0 ]
    [ "$output" = "n" ]
}

@test "zz-ask echoes back a valid answer's own case (no lowercasing of typed input)" {
    run bash -c 'echo "N" | zz-ask "Yn" "Continue?" 2>/dev/null'
    [ "$status" -eq 0 ]
    [ "$output" = "N" ]
}

@test "zz-ask re-prompts on an invalid option before accepting a valid one" {
    run bash -c 'printf "x\nn\n" | zz-ask "Yn" "Continue?" 2>/dev/null'
    [ "$status" -eq 0 ]
    [ "$output" = "n" ]
}

@test "zz-ask writes the question and options prompt to stderr" {
    run bash -c 'echo "" | zz-ask "Yn" "Continue?" 2>&1 1>/dev/null'
    [[ "$output" == *"Continue?"* ]]
    [[ "$output" == *"[Yn]"* ]]
}

@test "zz-ask default option is derived from the uppercase letter, not necessarily first char" {
    run bash -c 'echo "" | zz-ask "nY" "Proceed?" 2>/dev/null'
    [ "$status" -eq 0 ]
    [ "$output" = "y" ]
}

@test "zz-ask re-prompts with a warning message on invalid input" {
    run bash -c 'printf "z\ny\n" | zz-ask "Yn" "Continue?" 2>&1 1>/dev/null'
    [[ "$output" == *"valid option"* ]]
}
