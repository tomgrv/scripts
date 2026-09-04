#!/usr/bin/env bats

load ../tests/helpers.bash

setup() {
    setup_scripts_path
}

teardown() {
    teardown_scripts_path
}

@test "zz_colors is on PATH and syntactically valid" {
    run bash -n "$(command -v zz_colors)"
    [ "$status" -eq 0 ]
}

@test "zz_colors exports color variables when sourced" {
    run bash -c '. zz_colors; printf "%s" "$Red$None$End"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"["* ]]
}

@test "zz_colors defines every documented base, bold, and underline variable" {
    run bash -c '. zz_colors
    for v in None End \
        Black Red Green Yellow Blue Purple Cyan White \
        BBlack BRed BGreen BYellow BBlue BPurple BCyan BWhite \
        UBlack URed UGreen UYellow UBlue UPurple UCyan UWhite; do
        eval "val=\$$v"
        [ -n "$val" ] || { echo "MISSING:$v"; exit 1; }
    done
    echo all-present'
    [ "$status" -eq 0 ]
    [[ "$output" == *"all-present"* ]]
}

@test "zz_colors color codes are real ANSI escape sequences" {
    run bash -c '. zz_colors; printf "%b" "$Red" | od -An -tx1 | tr -d " \n"'
    [ "$status" -eq 0 ]
    # ESC (1b) 5b ('[') marks the start of an ANSI CSI sequence
    [[ "$output" == "1b5b"* ]]
}

@test "zz_colors is safe to source twice (idempotent, no errors)" {
    run bash -c '. zz_colors; . zz_colors; printf "%s" "$Red"; echo ok'
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

@test "zz_colors distinct variables carry distinct codes" {
    run bash -c '. zz_colors; [ "$Red" != "$Green" ] && [ "$Red" != "$BRed" ] && echo distinct'
    [ "$status" -eq 0 ]
    [[ "$output" == *"distinct"* ]]
}
