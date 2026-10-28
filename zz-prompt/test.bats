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

@test "zz-prompt -s hides the default" {
    run bash -c 'echo "" | zz-prompt -s "Secret?" "hunter2" 2>&1 1>/dev/null'
    [[ "$output" == *"[***]"* && "$output" != *hunter2* ]]
}

@test "zz-prompt -e fails when input ends, plain call still answers the default" {
    run bash -c 'zz-prompt -e "Q?" dflt </dev/null 2>/dev/null'
    [ "$status" -eq 1 ]
    run bash -c 'zz-prompt "Q?" dflt </dev/null 2>/dev/null'
    [ "$output" = dflt ]
}

@test "zz-prompt -c accepts a listed letter, defaults on Enter, re-asks on junk" {
    run bash -c 'printf "x\nN\n" | zz-prompt -c Yn "Go?" 2>/dev/null'
    [ "$output" = n ]
    run bash -c 'echo | zz-prompt -c Yn "Go?" 2>/dev/null'
    [ "$output" = y ]
}

@test "zz-prompt -c prints the default option on empty input" {
    run bash -c 'echo "" | zz-prompt -c Yn "Continue?" 2>/dev/null'
    [ "$status" -eq 0 ]
    [ "$output" = "y" ]
}

@test "zz-prompt -c prints a valid non-default option" {
    run bash -c 'echo "n" | zz-prompt -c Yn "Continue?" 2>/dev/null'
    [ "$status" -eq 0 ]
    [ "$output" = "n" ]
}

@test "zz-prompt -c lowercases a valid answer, so callers can compare with y/n" {
    run bash -c 'echo "N" | zz-prompt -c Yn "Continue?" 2>/dev/null'
    [ "$status" -eq 0 ]
    [ "$output" = "n" ]
}

@test "zz-prompt -c re-prompts on an invalid option before accepting a valid one" {
    run bash -c 'printf "x\nn\n" | zz-prompt -c Yn "Continue?" 2>/dev/null'
    [ "$status" -eq 0 ]
    [ "$output" = "n" ]
}

@test "zz-prompt -c writes the question and options prompt to stderr" {
    run bash -c 'echo "" | zz-prompt -c Yn "Continue?" 2>&1 1>/dev/null'
    [[ "$output" == *"Continue?"* ]]
    [[ "$output" == *"[Yn]"* ]]
}

@test "zz-prompt -c default option is derived from the uppercase letter, not necessarily first char" {
    run bash -c 'echo "" | zz-prompt -c nY "Proceed?" 2>/dev/null'
    [ "$status" -eq 0 ]
    [ "$output" = "y" ]
}

@test "zz-prompt -c re-prompts with a warning message on invalid input" {
    run bash -c 'printf "z\ny\n" | zz-prompt -c Yn "Continue?" 2>&1 1>/dev/null'
    [[ "$output" == *"valid option"* ]]
}

@test "zz-prompt takes its answers from ZZ_PROMPT_ANSWERS, one line per prompt" {
    printf 'first\n\nlast\n' >"$BATS_TEST_TMPDIR/ans"
    export ZZ_PROMPT_ANSWERS="$BATS_TEST_TMPDIR/ans"
    [ "$(zz-prompt Q1 2>/dev/null)" = "first" ]
    [ "$(zz-prompt Q2 dflt 2>/dev/null)" = "dflt" ]
    [ "$(zz-prompt Q3 2>/dev/null)" = "last" ]
    run zz-prompt -e Q4
    [ "$status" -eq 1 ]
}

@test "zz-prompt ZZ_PROMPT_MARK and ZZ_PROMPT_HINT set the prompt grammar" {
    run bash -c 'echo "" | NO_COLOR=1 ZZ_PROMPT_MARK="?" ZZ_PROMPT_HINT="(%s)" zz-prompt "Q?" dflt 2>&1 1>/dev/null'
    [[ "$output" == "? Q? (dflt) "* ]]
}

@test "zz-prompt with an empty ZZ_PROMPT_HINT shows no hint" {
    run bash -c 'echo "" | NO_COLOR=1 ZZ_PROMPT_HINT= zz-prompt -c Yn "Go?" 2>&1 1>/dev/null'
    [[ "$output" == "# Go? "* && "$output" != *"["* ]]
}

# The keypress path needs a terminal: script(1) gives zz-prompt a pty and types into it.
@test "zz-prompt -c answers on one keypress, no Enter needed" {
    command -v script >/dev/null || skip "script(1) not installed"
    run bash -c 'printf n | script -qec "ZZ_PROMPT_TTY=1 zz-prompt -c Yn \"Go?\"" /dev/null | tr -d "\r" | tail -n1'
    [ "$output" = "n" ]
}

@test "zz-prompt -c ignores an arrow key instead of reading it as an answer" {
    command -v script >/dev/null || skip "script(1) not installed"
    run bash -c '{ printf "\033[A"; sleep 1; printf y; } | script -qec "ZZ_PROMPT_TTY=1 zz-prompt -c Yn \"Go?\"" /dev/null | tr -d "\r" | tail -n1'
    [ "$output" = "y" ]
}
